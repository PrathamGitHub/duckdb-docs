# Spatial Validity Check

Assert geometries in curated spatial layers are present, valid, and ready for export.

## Purpose

Return features with null, empty, or invalid geometries before `output` GeoParquet or GeoJSON delivery. **Zero rows means pass.**

## When to Use

- On `curated.geo_parcels` before [export](../08_spatial_transformation/export_ready_spatial_layer.md)
- After `ST_MakeValid` in `staging` — confirm repair succeeded
- After clip, buffer, or spatial join transforms
- Alongside [CRS check](../05_spatial_eda/crs_check.md) in delivery QA

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Invalid geometries:

```sql
SELECT
  parcel_id,
  ST_GeometryType(geom) AS geom_type,
  ST_IsValid(geom) AS is_valid,
  ST_IsValidReason(geom) AS invalid_reason
FROM curated.geo_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsValid(geom)
ORDER BY parcel_id
LIMIT 100;
```

Null or empty geometry:

```sql
SELECT
  parcel_id,
  owner_name,
  CASE
    WHEN geom IS NULL THEN 'null geometry'
    WHEN ST_IsEmpty(geom) THEN 'empty geometry'
  END AS violation_type
FROM curated.geo_parcels
WHERE geom IS NULL
   OR ST_IsEmpty(geom);
```

Combined validity gate (single query):

```sql
SELECT
  parcel_id,
  CASE
    WHEN geom IS NULL THEN 'null geometry'
    WHEN ST_IsEmpty(geom) THEN 'empty geometry'
    WHEN NOT ST_IsValid(geom) THEN 'invalid geometry'
  END AS violation_type,
  ST_IsValidReason(geom) AS invalid_reason
FROM curated.geo_parcels
WHERE geom IS NULL
   OR ST_IsEmpty(geom)
   OR NOT ST_IsValid(geom);
```

Missing CRS / SRID check:

```sql
SELECT
  parcel_id,
  ST_SRID(geom) AS srid
FROM curated.geo_parcels
WHERE geom IS NOT NULL
  AND (ST_SRID(geom) IS NULL OR ST_SRID(geom) = 0);
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

violations = con.sql("""
  SELECT parcel_id,
         CASE
           WHEN geom IS NULL THEN 'null'
           WHEN ST_IsEmpty(geom) THEN 'empty'
           WHEN NOT ST_IsValid(geom) THEN 'invalid'
         END AS issue,
         ST_IsValidReason(geom) AS reason
  FROM curated.geo_parcels
  WHERE geom IS NULL
     OR ST_IsEmpty(geom)
     OR NOT ST_IsValid(geom)
  LIMIT 50
""").df()

assert violations.empty, f"Spatial validity failures: {len(violations)}"
violations
```

Practice dataset — ingest then validate:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_boundary AS
SELECT * FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.sql("""
  SELECT COUNT(*) AS invalid_n
  FROM raw.raw_boundary
  WHERE geom IS NOT NULL AND NOT ST_IsValid(geom)
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `curated.geo_parcels` | Pre-export spatial table |
| Geometry column | `geom` | Standard name in this repo |
| ID column | `parcel_id` | Sample listing |
| SRID expectation | `4326` or project CRS | Optional separate check |
| `LIMIT` | `100` | Cap notebook output |

## Expected Output

**On fail:**

| parcel_id | violation_type | invalid_reason |
|-----------|----------------|----------------|
| P-12044 | invalid geometry | Ring Self-intersection |
| P-88301 | null geometry | NULL |

**On pass:** zero rows.

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero rows | **Pass** — all features have valid non-empty geometry |
| Invalid polygons | **Fail** — repair with `ST_MakeValid` in `staging` or quarantine |
| Null / empty geom | **Fail** — block export; see [null geometry check (EDA)](../05_spatial_eda/null_geometry_check.md) |
| SRID 0 or NULL | **Fail** for delivery — assign CRS before export |
| Low invalid rate from legacy GDB | Fix in `staging`; re-run until pass |

## Common Variations

### Cross-layer validity report (summary, not pass/fail gate)

```sql
SELECT 'curated.geo_parcels' AS layer,
  SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom,
  SUM(CASE WHEN geom IS NULL OR ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS null_or_empty
FROM curated.geo_parcels;
```

### Validity after reprojection

```sql
SELECT parcel_id
FROM curated.geo_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsValid(ST_Transform(geom, 'EPSG:4326'));
```

### Polygon-only validity (ignore points)

```sql
SELECT parcel_id, ST_IsValidReason(geom) AS reason
FROM curated.geo_parcels
WHERE ST_GeometryType(geom) IN ('POLYGON', 'MULTIPOLYGON')
  AND NOT ST_IsValid(geom);
```

### Scalar for summary table

```sql
SELECT
  'spatial_validity_check' AS check_name,
  'curated.geo_parcels' AS table_name,
  COUNT(*) AS violating_rows
FROM curated.geo_parcels
WHERE geom IS NULL
   OR ST_IsEmpty(geom)
   OR NOT ST_IsValid(geom);
```

## How to Document Results

```text
Check: VAL-009 Spatial validity check
Table: curated.geo_parcels
Result: FAIL — 3 invalid polygons (repaired in staging.stg_parcels)
Re-run: PASS (0 violations)
CRS: EPSG:4326 confirmed
```

Attach `invalid_reason` samples for GIS consumers. Log pass/fail in [validation summary table](validation_summary_table.md).

## Related Pages

- [Invalid geometry check (EDA)](../05_spatial_eda/invalid_geometry_check.md)
- [Null geometry check (EDA)](../05_spatial_eda/null_geometry_check.md)
- [CRS check (EDA)](../05_spatial_eda/crs_check.md)
- [Export-ready spatial layer](../08_spatial_transformation/export_ready_spatial_layer.md)

Official reference: [ST_IsValid](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_isvalid) · [ST_MakeValid](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_makevalid)
