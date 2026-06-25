# Export-Ready Spatial Layer

Validate `curated` spatial tables and export to `output` formats (GeoParquet, GeoJSON) for maps, sharing, and downstream tools.

## Purpose

Run final QA on `curated.geo_parcels` and `curated.geo_roads_in_boundary`, then write consumer-ready files under `data/output/` without recomputing business logic.

## When to Use

- After [build curated spatial layer](build_curated_spatial_layer.md) completes
- Before handing data to GIS analysts, web maps, or external partners
- When you need a repeatable export cell at the end of a spatial notebook
- After validation checks pass (geometry validity, keys, extent)

This is the `curated → output` step in the spatial workflow.

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Pre-export validation view — fail fast in notebook:

```sql
CREATE OR REPLACE VIEW curated.v_export_qa_geo_parcels AS
SELECT
  'geo_parcels' AS layer_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT parcel_id) AS distinct_parcel_id,
  SUM(CASE WHEN geom IS NULL OR ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS null_or_empty_geom,
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom,
  ST_Extent(geom) AS bbox
FROM curated.geo_parcels;
```

Export GeoParquet — preferred for analytics and re-ingest:

```sql
COPY (
  SELECT
    parcel_id,
    owner_name,
    zoning_code,
    boundary_name,
    area_sqm,
    geom
  FROM curated.geo_parcels
  WHERE geom IS NOT NULL
    AND NOT ST_IsEmpty(geom)
    AND ST_IsValid(geom)
) TO 'data/output/geo_parcels.parquet'
(FORMAT PARQUET);
```

Export GeoJSON for web maps (simplify if needed):

```sql
COPY (
  SELECT
    road_id,
    road_name,
    road_class,
    road_length_m,
    geom
  FROM curated.geo_roads_in_boundary
  WHERE geom IS NOT NULL
    AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_roads_in_boundary.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

Export via `ST_Write` (spatial-native write):

```sql
COPY (
  SELECT * FROM curated.geo_parcels
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_parcels.parquet'
WITH (FORMAT GDAL, DRIVER 'Parquet');
```

Tabular attributes without geometry (CSV companion):

```sql
COPY (
  SELECT
    parcel_id,
    owner_name,
    zoning_code,
    boundary_name,
    area_sqm,
    perimeter_m
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_attributes.csv'
(HEADER, DELIMITER ',');
```

## Notebook Usage

```python
from pathlib import Path

output_dir = Path("data/output")
output_dir.mkdir(parents=True, exist_ok=True)

con.execute("INSTALL spatial; LOAD spatial;")

# QA gate
qa = con.sql("SELECT * FROM curated.v_export_qa_geo_parcels").df()
assert qa.null_or_empty_geom.iloc[0] == 0, "Null geometries in geo_parcels"
assert qa.invalid_geom.iloc[0] == 0, "Invalid geometries in geo_parcels"
assert qa.row_count.iloc[0] == qa.distinct_parcel_id.iloc[0], "Duplicate parcel_id"
qa
```

```python
# Export parcels and roads
con.execute("""
COPY (
  SELECT parcel_id, owner_name, zoning_code, area_sqm, geom
  FROM curated.geo_parcels
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_parcels.parquet' (FORMAT PARQUET);
""")

con.execute("""
COPY (
  SELECT road_id, road_name, road_class, road_length_m, geom
  FROM curated.geo_roads_in_boundary
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_roads_in_boundary.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
""")

list(output_dir.glob("geo_*"))
```

```python
# Round-trip check: read exported GeoParquet back
con.execute("""
CREATE OR REPLACE TABLE staging.stg_parcels_roundtrip AS
SELECT * FROM ST_Read('data/output/geo_parcels.parquet');
""")
con.sql("""
  SELECT
    (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_n,
    (SELECT COUNT(*) FROM staging.stg_parcels_roundtrip) AS roundtrip_n
""").df()
```

Practice pipeline from online boundary through export:

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_boundary AS
SELECT
  "properties.NAME" AS boundary_name,
  ST_MakeValid(geom) AS geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

# ... build curated.geo_parcels per build_curated_spatial_layer.md ...

con.execute("""
COPY (SELECT boundary_name, geom FROM staging.stg_boundary)
TO 'data/output/stg_boundary.geojson' (FORMAT GDAL, DRIVER 'GeoJSON');
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.geo_parcels` | Source table |
| `{output_path}` | `data/output/geo_parcels.parquet` | File destination |
| `{format}` | `PARQUET`, `GDAL` + driver | GeoParquet vs GeoJSON |
| `{geometry_column}` | `geom` | Default in this repo |
| `{where_clause}` | `ST_IsValid(geom)` | Export filter |
| `{simplify_tolerance}` | `0.0001` | Optional for web GeoJSON |

## Input Table Pattern

```text
curated.geo_<entity>
```

Export reads from validated curated tables — not `staging` or `raw`.

**`curated.geo_parcels`**

| parcel_id | owner_name | zoning_code | area_sqm | geom |
|-----------|------------|-------------|----------|------|
| P-001 | Smith | R-1 | 4500.2 | POLYGON(...) |

**`curated.geo_roads_in_boundary`**

| road_id | road_name | road_class | road_length_m | geom |
|---------|-----------|------------|---------------|------|
| R-100 | Main St | arterial | 3200.5 | LINESTRING(...) |

## Output Table Pattern

```text
data/output/geo_<entity>.<ext>
data/output/geo_<entity>_attributes.csv   -- optional non-spatial companion
```

| File | Format | Use case |
|------|--------|----------|
| `data/output/geo_parcels.parquet` | GeoParquet | Analytics, DuckDB re-ingest, QGIS |
| `data/output/geo_roads_in_boundary.geojson` | GeoJSON | Web maps, lightweight sharing |
| `data/output/geo_parcels_attributes.csv` | CSV | Spreadsheets without geometry |

Round-trip validation (optional): `staging.stg_parcels_roundtrip` from `ST_Read` of exported file.

## Validation Checks

```sql
-- Pre-export QA view (create once per layer)
SELECT * FROM curated.v_export_qa_geo_parcels;
```

```sql
-- Required fields non-null
SELECT COUNT(*) AS bad_rows
FROM curated.geo_parcels
WHERE parcel_id IS NULL
   OR geom IS NULL
   OR ST_IsEmpty(geom);
```

```sql
-- Geometry validity (export gate)
SELECT COUNT(*) AS invalid
FROM curated.geo_parcels
WHERE NOT ST_IsValid(geom);
```

```sql
-- Extent sanity vs boundary
SELECT
  ST_Extent(p.geom) AS export_extent,
  ST_Extent(b.geom) AS boundary_extent
FROM curated.geo_parcels p
CROSS JOIN staging.stg_boundary b;
```

```sql
-- Post-export file row count (in notebook after ST_Read)
SELECT
  (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_rows,
  (SELECT COUNT(*) FROM ST_Read('data/output/geo_parcels.parquet')) AS file_rows;
```

```sql
-- Roads export length sum reconciliation
SELECT
  SUM(road_length_m) AS curated_length,
  (SELECT SUM(road_length_m) FROM curated.geo_roads_in_boundary) AS check_length
FROM curated.geo_roads_in_boundary;
```

## Common Variations

### ZSTD compression for Parquet

```sql
COPY (...) TO 'data/output/geo_parcels.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
```

### Simplified GeoJSON for web performance

```sql
COPY (
  SELECT
    parcel_id,
    owner_name,
    ST_SimplifyPreserveTopology(geom, 0.0001) AS geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_web.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

### Export only columns consumers need

```sql
SELECT parcel_id, owner_name, area_sqm, geom
```

Avoid internal QA columns (`curated_at`, pipeline ids) unless requested.

### Dated output folder

```python
from datetime import date
out = Path(f"data/output/delivery_{date.today().isoformat()}")
out.mkdir(parents=True, exist_ok=True)
```

### Partitioned export by attribute

```sql
COPY (SELECT * FROM curated.geo_parcels)
TO 'data/output/geo_parcels'
(FORMAT PARQUET, PARTITION_BY (boundary_name));
```

### Shapefile export (legacy GIS consumers)

```sql
COPY (SELECT * FROM curated.geo_parcels)
TO 'data/output/geo_parcels.shp'
(FORMAT GDAL, DRIVER 'ESRI Shapefile');
```

Shapefile field name length limits apply — shorten columns in `SELECT`.

## Performance Notes

- Export from `curated` only — do not recompute transforms at export time.
- GeoParquet is smaller and faster than GeoJSON for large polygon layers.
- Simplify geometry before GeoJSON export to reduce file size.
- Filter invalid rows in `COPY` subquery to prevent GDAL write failures.
- CSV attribute export is cheap — pair with GeoParquet for full stack delivery.

## Known Limitations

- GeoJSON does not scale to millions of features — use GeoParquet for large parcels.
- `COPY ... FORMAT GDAL` requires GDAL drivers in the spatial extension environment.
- CRS metadata in exported files depends on driver and source geometry — verify in QGIS or `ST_Read_Meta`.
- Shapefile exports truncate column names and have 2 GB size limits.
- Simplification changes geometry — keep `curated.geo_parcels` authoritative; export simplified copies separately.
- Web Mercator reprojection for web maps should happen in the tile server or GIS client if you store WGS 84 in export.

## Related Pages

- [Build curated spatial layer](build_curated_spatial_layer.md)
- [Clip / intersection](clip_intersection.md)
- [Workflow layers](../00_overview/workflow_layers.md)
- [Invalid geometry check](../05_spatial_eda/invalid_geometry_check.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html) · [ST_Read / spatial IO](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
