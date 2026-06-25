# Spatial Geometry Cleaning

Repair, filter, and standardize geometries from spatial `raw` tables into analysis-ready `staging` layers.

## Purpose

Handle null geometries, invalid topology, mixed geometry types, and CRS issues so spatial joins, area calculations, and exports do not fail silently or produce wrong results.

## When to Use

- After Shapefile, GeoJSON, GeoParquet, or FileGDB ingest into `raw`
- When [null geometry check](../05_spatial_eda/null_geometry_check.md) or [invalid geometry check](../05_spatial_eda/invalid_geometry_check.md) flags issues
- Before [spatial join preview](../05_spatial_eda/spatial_join_preview.md) or `curated` overlay models
- When map previews show missing features or slivers

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Filter null/empty geometries and repair invalid shapes:

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_ca_regions AS
SELECT
  "properties.NAME" AS region_name,
  ST_MakeValid(geom) AS geom
FROM raw.raw_ca_regions_geojson
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);
```

Flag null geometries instead of dropping (audit-friendly):

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT
  parcel_id,
  owner_name,
  geom,
  geom IS NULL OR ST_IsEmpty(geom) AS has_null_geometry,
  CASE
    WHEN geom IS NULL THEN NULL
    WHEN ST_IsEmpty(geom) THEN NULL
    ELSE ST_MakeValid(geom)
  END AS geom_clean
FROM raw.raw_parcels_shp;
```

Drop nulls and keep only polygon boundaries for overlay work:

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT
  parcel_id,
  owner_name,
  ST_MakeValid(geom) AS geom
FROM raw.raw_parcels_shp
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom)
  AND ST_GeometryType(geom) IN ('POLYGON', 'MULTIPOLYGON');
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

con.execute("""
CREATE OR REPLACE TABLE raw.raw_ca_regions_geojson AS
SELECT * FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

# Null geometry profile on raw
con.sql("""
  SELECT
    COUNT(*) AS total_rows,
    COUNT(geom) AS non_null_geom,
    COUNT(*) - COUNT(geom) AS null_geom,
    SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS empty_geom
  FROM raw.raw_ca_regions_geojson
""").df()
```

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_ca_regions AS
SELECT
  "properties.NAME" AS region_name,
  ST_MakeValid(geom) AS geom
FROM raw.raw_ca_regions_geojson
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);
""")

con.sql("""
  SELECT
    ST_GeometryType(geom) AS geom_type,
    COUNT(*) AS n
  FROM staging.stg_ca_regions
  GROUP BY 1;
""").df()
```

Practice with intentional null row:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_sites AS
SELECT * FROM (VALUES
  ('SITE-001', ST_GeomFromText('POINT(-122.4 37.8)')),
  ('SITE-002', NULL),
  ('SITE-003', ST_GeomFromText('POLYGON EMPTY'))
) AS t(site_id, geom);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_sites AS
SELECT
  site_id,
  CASE
    WHEN geom IS NULL OR ST_IsEmpty(geom) THEN NULL
    ELSE ST_MakeValid(geom)
  END AS geom,
  geom IS NULL OR ST_IsEmpty(geom) AS has_null_geometry
FROM raw.raw_sites
WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom);
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_parcels_shp` | Spatial raw table |
| `{stg_table}` | `staging.stg_parcels` | Cleaned geometry layer |
| Geometry column | `geom` | Primary geometry |
| ID column | `parcel_id`, `site_id` | Trace dropped features |
| Filter predicate | `geom IS NOT NULL AND NOT ST_IsEmpty(geom)` | Required for overlays |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Examples:

- `raw.raw_parcels_shp`
- `raw.raw_ca_regions_geojson`
- `raw.raw_zoning_gdb`

| parcel_id | owner_name | geom |
|-----------|------------|------|
| P-001 | Smith | POLYGON(...) |
| P-002 | Jones | NULL |
| P-003 | Lee | POLYGON EMPTY |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_parcels` — valid non-empty geometries (or flagged audit table).

| parcel_id | owner_name | geom |
|-----------|------------|------|
| P-001 | Smith | POLYGON(...) |

Optional audit companion:

| parcel_id | has_null_geometry | geom_clean |
|-----------|-------------------|------------|
| P-002 | true | NULL |

## Validation Checks

```sql
-- Zero null or empty geometries in required staging table
SELECT COUNT(*) AS bad_geom
FROM staging.stg_parcels
WHERE geom IS NULL OR ST_IsEmpty(geom);
```

```sql
-- Invalid geometry count after ST_MakeValid
SELECT COUNT(*) AS still_invalid
FROM staging.stg_parcels
WHERE NOT ST_IsValid(geom);
```

```sql
-- Row reconciliation: raw vs staging
SELECT
  (SELECT COUNT(*) FROM raw.raw_parcels_shp) AS raw_rows,
  (SELECT COUNT(*) FROM staging.stg_parcels) AS stg_rows,
  (SELECT COUNT(*) FROM raw.raw_parcels_shp
   WHERE geom IS NULL OR ST_IsEmpty(geom)) AS dropped_null_geom;
```

```sql
-- Geometry type distribution
SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM staging.stg_parcels
GROUP BY 1
ORDER BY n DESC;
```

Compare to [CRS check](../05_spatial_eda/crs_check.md) before spatial joins across layers.

## Common Variations

### Separate table for null geometries (do not lose audit trail)

```sql
CREATE OR REPLACE TABLE staging.stg_parcels_null_geom AS
SELECT parcel_id, owner_name, geom
FROM raw.raw_parcels_shp
WHERE geom IS NULL OR ST_IsEmpty(geom);
```

### `COALESCE` is not for geometry repair

Use `ST_MakeValid` and explicit filters — do not `COALESCE(geom, ST_Point(0,0))` unless you intentionally want placeholder points.

### Cast to consistent dimension

```sql
ST_Force2D(geom) AS geom
```

### Buffer zero to fix minor topology (use sparingly)

```sql
ST_MakeValid(ST_Buffer(geom, 0)) AS geom
```

### Harmonize CRS in staging

```sql
ST_Transform(geom, 'EPSG:4326', 'EPSG:3857') AS geom
```

Confirm source CRS with [CRS check](../05_spatial_eda/crs_check.md) first.

### GeoParquet / WKB columns

```sql
ST_GeomFromWKB(wkb_geometry) AS geom
```

Validate non-null WKB converts successfully before filtering.

## Known Limitations

- `ST_MakeValid` may change area slightly or split multipolygons — compare areas for critical parcels.
- Filtering null geometries reduces row counts — document drops for GIS stakeholders.
- Empty geometries (`POLYGON EMPTY`) are not `NULL` — always check both conditions.
- CRS mismatches are not fixed by `ST_MakeValid` — transform explicitly when layers disagree.
- Very large invalid batches can be slow to repair — sample and profile in `raw` first.

## Related Pages

- [Null geometry check](../05_spatial_eda/null_geometry_check.md)
- [Invalid geometry check](../05_spatial_eda/invalid_geometry_check.md)
- [CRS check](../05_spatial_eda/crs_check.md)
- [Column standardization](column_standardization.md)
- [Shapefile ingest](../03_spatial_ingestion/shapefile.md)

Official reference: [Spatial functions](https://duckdb.org/docs/current/core_extensions/spatial/functions.html)
