# GeoJSON Export

Export `curated` spatial tables to GeoJSON files under `data/output/` for web maps, lightweight sharing, and tools that expect FeatureCollection JSON.

## Purpose

Write validated geometry layers from `curated.geo_*` tables to `.geojson` files using DuckDB `COPY` with the GDAL GeoJSON driver, optimized for human-readable spatial handoffs.

## When to Use

- Sharing boundary or point layers with web mapping teams
- Delivering small-to-medium spatial slices to partners without GIS desktop software
- Quick visual QA in geojson.io, MapLibre, or Leaflet prototypes
- Final `curated → output` step when consumers do not need Parquet

For large polygon datasets, use [GeoParquet export](geoparquet_export.md). GeoJSON does not scale to millions of features.

## SQL Template

Basic GeoJSON export:

```sql
INSTALL spatial;
LOAD spatial;

COPY (
  SELECT
    parcel_id,
    owner_name,
    zoning_code,
    area_sqm,
    geom
  FROM curated.geo_parcels
  WHERE geom IS NOT NULL
    AND NOT ST_IsEmpty(geom)
    AND ST_IsValid(geom)
) TO 'data/output/geo_parcels.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

Simplified geometry for web performance:

```sql
COPY (
  SELECT
    road_id,
    road_name,
    road_class,
    ST_SimplifyPreserveTopology(geom, 0.0001) AS geom
  FROM curated.geo_roads_in_boundary
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_roads_in_boundary.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

Reproject to WGS 84 for web maps:

```sql
COPY (
  SELECT
    parcel_id,
    owner_name,
    ST_Transform(geom, 'EPSG:3857', 'EPSG:4326') AS geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_wgs84.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

## Notebook Usage

```python
from pathlib import Path

output_dir = Path("data/output")
output_dir.mkdir(parents=True, exist_ok=True)

con.execute("INSTALL spatial; LOAD spatial;")

# Practice: export California boundary from online GeoJSON
con.execute("""
CREATE OR REPLACE TABLE curated.geo_boundary AS
SELECT
  "properties.NAME" AS boundary_name,
  ST_MakeValid(geom) AS geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.execute("""
COPY (
  SELECT boundary_name, geom
  FROM curated.geo_boundary
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_boundary.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
""")

Path("data/output/geo_boundary.geojson").stat().st_size  # file size bytes
```

```python
# Round-trip validation
con.execute("""
CREATE OR REPLACE TABLE staging.stg_boundary_roundtrip AS
SELECT * FROM ST_Read('data/output/geo_boundary.geojson');
""")

con.sql("""
SELECT
  (SELECT COUNT(*) FROM curated.geo_boundary) AS curated_n,
  (SELECT COUNT(*) FROM staging.stg_boundary_roundtrip) AS file_n
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.geo_parcels` | Source spatial table |
| `{output_path}` | `data/output/geo_parcels.geojson` | Destination file |
| `{geometry_column}` | `geom` | Must be in `SELECT` |
| `{simplify_tolerance}` | `0.0001` | Degrees — tune per layer |
| `{target_crs}` | `EPSG:4326` | Use `ST_Transform` when needed |
| `{where_clause}` | `ST_IsValid(geom)` | Pre-filter invalid features |

## Input Table / Query

```text
curated.geo_parcels
curated.geo_roads_in_boundary
```

**`curated.geo_parcels`**

| parcel_id | owner_name | zoning_code | area_sqm | geom |
|-----------|------------|-------------|----------|------|
| P-001 | Smith | R-1 | 4500.2 | POLYGON(...) |

**`curated.geo_roads_in_boundary`**

| road_id | road_name | road_class | road_length_m | geom |
|---------|-----------|------------|---------------|------|
| R-100 | Main St | arterial | 3200.5 | LINESTRING(...) |

## Output Path

```text
data/output/geo_parcels.geojson
data/output/geo_roads_in_boundary.geojson
data/output/geo_parcels_web.geojson          -- simplified derivative
```

## Validation After Export

```sql
-- Pre-export gate
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid,
  ST_Extent(geom) AS bbox
FROM curated.geo_parcels;
```

```sql
-- Post-export feature count
SELECT
  (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_n,
  (SELECT COUNT(*) FROM ST_Read('data/output/geo_parcels.geojson')) AS file_n;
```

```sql
-- Geometry types in exported file
SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM ST_Read('data/output/geo_parcels.geojson')
GROUP BY 1;
```

```python
import json
from pathlib import Path

path = Path("data/output/geo_boundary.geojson")
with path.open() as f:
    gj = json.load(f)
assert gj["type"] == "FeatureCollection"
assert len(gj["features"]) > 0
len(gj["features"])
```

## Common Variations

### Simplified web export (keep curated authoritative)

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

### Export subset by attribute

```sql
COPY (
  SELECT parcel_id, owner_name, geom
  FROM curated.geo_parcels
  WHERE zoning_code = 'R-1'
) TO 'data/output/geo_parcels_r1.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

### Points-only layer

```sql
COPY (
  SELECT site_id, site_name, geom
  FROM curated.geo_sites
  WHERE ST_GeometryType(geom) IN ('POINT', 'MULTIPOINT')
) TO 'data/output/geo_sites.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

### Newline-delimited GeoJSON (NDJSON) — via Python

```python
import geopandas as gpd  # optional dependency

gdf = con.sql("SELECT parcel_id, owner_name, geom FROM curated.geo_parcels").df()
# If using geopandas with WKB from DuckDB, convert geometry column first
```

For most workflows, FeatureCollection GeoJSON via `COPY` is sufficient.

### Pair with GeoParquet for full delivery

```python
# GeoParquet for analysts + GeoJSON for web team
con.execute("COPY (SELECT * FROM curated.geo_parcels) TO 'data/output/geo_parcels.parquet' (FORMAT PARQUET);")
con.execute("COPY (SELECT parcel_id, owner_name, geom FROM curated.geo_parcels) TO 'data/output/geo_parcels.geojson' (FORMAT GDAL, DRIVER 'GeoJSON');")
```

## Performance Notes

- GeoJSON is text-based and verbose — files are 5–20× larger than equivalent GeoParquet.
- Simplify polygons before export to cut file size for web use.
- Filter to valid geometries only — invalid features block GDAL writes.
- Limit feature count for interactive web maps (typically < 50k features depending on complexity).
- Export from `curated` — do not recompute spatial joins at export time.

## Known Limitations

- Does not scale to millions of polygon features — use GeoParquet for large layers.
- `COPY ... FORMAT GDAL` requires GDAL drivers in the spatial extension environment.
- Field name length and type constraints follow GDAL GeoJSON driver rules.
- Simplification changes geometry — never overwrite curated; export simplified copies separately.
- CRS may not be embedded as expected — verify in QGIS or `ST_Read_Meta` after export.
- Single-file GeoJSON loads entirely into memory in many web clients — partition by region if needed.
- Numeric precision in coordinates may differ slightly after round-trip through GeoJSON text.

## Related Pages

- [GeoParquet export](geoparquet_export.md)
- [Export-ready spatial layer](../08_spatial_transformation/export_ready_spatial_layer.md)
- [GeoJSON ingestion](../03_spatial_ingestion/geojson.md)
- [Delivery package](delivery_package.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html) · [ST_Read / spatial IO](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
