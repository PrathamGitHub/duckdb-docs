# GeoParquet Export

Export `curated` spatial tables to GeoParquet files under `data/output/` for analytics, GIS tools, and fast DuckDB re-ingest.

## Purpose

Write validated geometry layers from `curated.geo_*` tables to columnar GeoParquet using DuckDB `COPY`, preserving geometry types and CRS metadata for downstream spatial workflows.

## When to Use

- Publishing parcel, boundary, or road layers after spatial validation
- Handoff to QGIS, GeoPandas, or another DuckDB pipeline
- Preferred spatial export format for large polygon layers
- Final `curated → output` step in spatial notebooks

Use [GeoJSON export](geojson_export.md) for small web-map shares. Use [CSV export](csv_export.md) for attribute-only spreadsheets.

## SQL Template

Native Parquet export (geometry column preserved):

```sql
INSTALL spatial;
LOAD spatial;

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

GDAL driver export (explicit spatial write):

```sql
COPY (
  SELECT parcel_id, owner_name, zoning_code, area_sqm, geom
  FROM curated.geo_parcels
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_parcels.parquet'
WITH (FORMAT GDAL, DRIVER 'Parquet');
```

With ZSTD compression:

```sql
COPY (
  SELECT parcel_id, owner_name, zoning_code, geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
```

## Notebook Usage

```python
from pathlib import Path

output_dir = Path("data/output")
output_dir.mkdir(parents=True, exist_ok=True)

con.execute("INSTALL spatial; LOAD spatial;")

# Practice: build curated layer from online GeoJSON
con.execute("""
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  ROW_NUMBER() OVER () AS parcel_id,
  'Owner ' || ROW_NUMBER() OVER () AS owner_name,
  'R-1' AS zoning_code,
  'California' AS boundary_name,
  ST_Area(geom) AS area_sqm,
  ST_MakeValid(geom) AS geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.execute("""
COPY (
  SELECT parcel_id, owner_name, zoning_code, boundary_name, area_sqm, geom
  FROM curated.geo_parcels
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/geo_parcels.parquet'
(FORMAT PARQUET);
""")

list(output_dir.glob("geo_*.parquet"))
```

```python
# Round-trip validation via ST_Read
con.execute("""
CREATE OR REPLACE TABLE staging.stg_parcels_roundtrip AS
SELECT * FROM ST_Read('data/output/geo_parcels.parquet');
""")

con.sql("""
SELECT
  (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_n,
  (SELECT COUNT(*) FROM staging.stg_parcels_roundtrip) AS file_n,
  (SELECT SUM(area_sqm) FROM curated.geo_parcels) AS curated_area,
  (SELECT SUM(area_sqm) FROM staging.stg_parcels_roundtrip) AS file_area
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.geo_parcels` | Spatial source table |
| `{output_path}` | `data/output/geo_parcels.parquet` | Single GeoParquet file |
| `{geometry_column}` | `geom` | Default in this repo |
| `{where_clause}` | `ST_IsValid(geom)` | Filter invalid rows before write |
| `{compression}` | `ZSTD` | Recommended for large layers |
| `{columns}` | `parcel_id, geom` | Project consumer-facing fields |

## Input Table / Query

```text
curated.geo_parcels
```

| parcel_id | owner_name | zoning_code | area_sqm | geom |
|-----------|------------|-------------|----------|------|
| P-001 | Smith | R-1 | 4500.2 | POLYGON(...) |
| P-002 | Jones | C-2 | 1200.8 | POLYGON(...) |

Export from validated `curated` spatial tables — run [spatial validity check](../09_validation/spatial_validity_check.md) first.

## Output Path

```text
data/output/geo_parcels.parquet
data/output/geo_roads_in_boundary.parquet
data/output/geo_parcels_attributes.csv     -- optional non-spatial companion
```

## Validation After Export

```sql
-- Pre-export QA
SELECT
  COUNT(*) AS row_count,
  SUM(CASE WHEN geom IS NULL OR ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS null_geom,
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom,
  ST_Extent(geom) AS bbox
FROM curated.geo_parcels;
```

```sql
-- Post-export row count via ST_Read
SELECT
  (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_rows,
  (SELECT COUNT(*) FROM ST_Read('data/output/geo_parcels.parquet')) AS file_rows;
```

```sql
-- Geometry type check after round-trip
SELECT DISTINCT ST_GeometryType(geom) AS geom_type
FROM ST_Read('data/output/geo_parcels.parquet');
```

```python
qa = con.sql("""
  SELECT
    (SELECT COUNT(*) FROM curated.geo_parcels) =
    (SELECT COUNT(*) FROM ST_Read('data/output/geo_parcels.parquet')) AS rows_match
""").df()
assert qa.rows_match.iloc[0], "GeoParquet row count mismatch"
```

## Common Variations

### ZSTD compression

```sql
COPY (...) TO 'data/output/geo_parcels.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
```

### Reproject before export (target CRS)

```sql
COPY (
  SELECT
    parcel_id,
    owner_name,
    ST_Transform(geom, 'EPSG:4326', 'EPSG:3857') AS geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_3857.parquet'
(FORMAT PARQUET);
```

### Partitioned GeoParquet by region

```sql
COPY (
  SELECT parcel_id, boundary_name, zoning_code, geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels'
(FORMAT PARQUET, PARTITION_BY (boundary_name));
```

See [partitioned Parquet export](partitioned_parquet_export.md).

### Attribute CSV companion (no geometry)

```sql
COPY (
  SELECT parcel_id, owner_name, zoning_code, area_sqm
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_attributes.csv'
WITH (HEADER, DELIMITER ',');
```

### ST_Write alternative

```sql
-- Equivalent spatial-native write path
COPY (SELECT * FROM curated.geo_parcels)
TO 'data/output/geo_parcels.parquet'
WITH (FORMAT GDAL, DRIVER 'Parquet');
```

## Performance Notes

- GeoParquet is far smaller and faster than GeoJSON for large polygon layers.
- Filter invalid geometries in the `COPY` subquery to avoid GDAL write failures.
- `COMPRESSION ZSTD` reduces file size with modest CPU overhead.
- Export from `curated` only — do not recompute transforms at export time.
- Simplify geometry in a separate export file if web consumers need lighter data — keep `curated` authoritative.

## Known Limitations

- CRS metadata in exported files depends on driver and source geometry — verify in QGIS or `ST_Read_Meta`.
- `FORMAT PARQUET` vs `FORMAT GDAL` may differ in GeoParquet metadata completeness — test round-trip with `ST_Read`.
- Invalid or empty geometries cause write errors or silent drops — validate before export.
- Very complex polygons increase file size — consider `ST_SimplifyPreserveTopology` for derivative exports only.
- Partitioned spatial exports may not carry full GeoParquet spec metadata in all driver versions.
- Geometry repair at export (`ST_MakeValid`) changes shapes — prefer repairing in `staging`/`curated`.

## Related Pages

- [GeoJSON export](geojson_export.md)
- [Export-ready spatial layer](../08_spatial_transformation/export_ready_spatial_layer.md)
- [GeoParquet ingestion](../03_spatial_ingestion/geoparquet.md)
- [Spatial validity check](../09_validation/spatial_validity_check.md)
- [Delivery package](delivery_package.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html) · [ST_Read / spatial IO](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
