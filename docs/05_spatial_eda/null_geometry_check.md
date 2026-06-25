# Null Geometry Check

Find rows with missing or empty geometries before spatial joins, area calculations, or export to GeoParquet.

## Purpose

Quantify `NULL` and empty (`ST_IsEmpty`) geometry rates so you can filter or repair features in `staging` without silently dropping records in `curated` models.

## When to Use

- After ingest when source feature count ≠ `COUNT(*)` with valid geometry
- Before [area / length summary](area_length_summary.md) or [spatial join preview](spatial_join_preview.md)
- When map preview shows gaps or missing features
- Regression gate: null rate should not spike between ingest runs

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Summary metrics for one table:

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(geom) AS non_null_geom,
  COUNT(*) - COUNT(geom) AS null_geom,
  ROUND(100.0 * (COUNT(*) - COUNT(geom)) / COUNT(*), 2) AS null_geom_pct,
  SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS empty_geom,
  ROUND(100.0 * SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END) / COUNT(*), 2) AS empty_geom_pct
FROM raw.raw_parcels;
```

List rows with null or empty geometry:

```sql
SELECT
  parcel_id,
  CASE
    WHEN geom IS NULL THEN 'NULL'
    WHEN ST_IsEmpty(geom) THEN 'EMPTY'
    ELSE 'OK'
  END AS geom_status
FROM raw.raw_parcels
WHERE geom IS NULL OR ST_IsEmpty(geom)
LIMIT 100;
```

Cross-layer null profile:

```sql
SELECT 'raw_parcels' AS table_name,
  COUNT(*) AS total,
  COUNT(*) - COUNT(geom) AS null_geom,
  SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS empty_geom
FROM raw.raw_parcels
UNION ALL
SELECT 'raw_roads', COUNT(*), COUNT(*) - COUNT(geom),
  SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END)
FROM raw.raw_roads
UNION ALL
SELECT 'raw_boundary', COUNT(*), COUNT(*) - COUNT(geom),
  SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END)
FROM raw.raw_boundary;
```

## Notebook Usage

```python
null_report = con.sql("""
  SELECT
    COUNT(*) AS total_rows,
    COUNT(geom) AS non_null_geom,
    COUNT(*) - COUNT(geom) AS null_geom,
    SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS empty_geom
  FROM raw.raw_roads
""").df()
null_report
```

```python
# Flag if null rate exceeds threshold
THRESHOLD_PCT = 0.5
row = null_report.iloc[0]
null_pct = 100.0 * row.null_geom / row.total_rows
assert null_pct <= THRESHOLD_PCT, f"Null geometry rate {null_pct:.2f}% exceeds {THRESHOLD_PCT}%"
```

Practice dataset:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_boundary AS
SELECT * FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.sql("""
  SELECT COUNT(*) AS total, COUNT(geom) AS with_geom
  FROM raw.raw_boundary
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_parcels` | Target table |
| `geom` | `geom` | Geometry column |
| ID column | `parcel_id`, `road_id` | List bad rows |
| `THRESHOLD_PCT` | `0.5` | Notebook assertion |

## Expected Output

| total_rows | non_null_geom | null_geom | null_geom_pct | empty_geom | empty_geom_pct |
|------------|---------------|-----------|---------------|------------|----------------|
| 12475 | 12470 | 5 | 0.04 | 2 | 0.02 |

Detail listing:

| parcel_id | geom_status |
|-----------|-------------|
| P-00921 | NULL |
| P-04402 | EMPTY |

## Interpretation Guidance

- **0% null on required layers** — ideal for parcels and boundaries used in overlays.
- **NULL vs EMPTY** — `NULL` means no geometry stored; `EMPTY` means a geometry object with no coordinates (both fail spatial predicates).
- **Small null rate** — may be acceptable if source documents known gaps; filter in `staging` with `WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)`.
- **Sudden increase** — driver change, wrong layer, or truncated ingest; compare to source metadata feature count.
- **Boundary should rarely have nulls** — any null on `raw.raw_boundary` blocks clipping and join previews.

## Common Variations

### Gate query (fail if any null geometry on keys)

```sql
SELECT COUNT(*) AS bad_rows
FROM raw.raw_parcels
WHERE geom IS NULL OR ST_IsEmpty(geom)
HAVING COUNT(*) > 0;
```

### Null geometry by source file

```sql
SELECT
  source_file,
  COUNT(*) - COUNT(geom) AS null_geom
FROM raw.raw_parcels
GROUP BY source_file
ORDER BY null_geom DESC;
```

### After staging repair

```sql
SELECT
  COUNT(*) FILTER (WHERE geom IS NULL OR ST_IsEmpty(geom)) AS still_bad
FROM staging.stg_parcels;
```

Compare to `raw` to confirm `ST_MakeValid` / filters in `staging` resolved issues.

## Known Limitations

- `ST_IsEmpty` requires non-NULL input — always check `geom IS NULL` first.
- WKB columns from `read_parquet` without `ST_GeomFromWKB` may look non-null but fail conversion — validate in `staging`.
- Empty multipolygons are empty; multipart with some empty parts need [invalid geometry check](invalid_geometry_check.md).
- Listing queries without `LIMIT` can flood notebooks on large bad batches.

## Related Pages

- [Geometry type count](geometry_type_count.md)
- [Invalid geometry check](invalid_geometry_check.md)
- [Null profile](../04_eda/null_profile.md)

Official reference: [ST_IsEmpty](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_isempty)
