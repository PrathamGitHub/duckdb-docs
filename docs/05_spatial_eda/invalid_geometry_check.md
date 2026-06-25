# Invalid Geometry Check

Detect topologically invalid geometries before `ST_Intersects`, buffers, unions, or export — invalid features often fail silently or skew join counts.

## Purpose

Count and sample rows where `ST_IsValid(geom)` is false so you can repair with `ST_MakeValid` in `staging` or quarantine bad features before `curated` spatial models.

## When to Use

- After ingest on polygon layers (`raw.raw_parcels`, `raw.raw_boundary`)
- Before [area / length summary](area_length_summary.md) — invalid polygons may return NULL or wrong area
- Before [spatial join preview](spatial_join_preview.md) — invalid geometries affect `ST_Intersects` results
- After editing geometries in external GIS tools

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Invalid count summary:

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(geom) AS with_geom,
  SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom,
  ROUND(100.0 * SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END)
    / NULLIF(COUNT(geom), 0), 2) AS invalid_geom_pct
FROM raw.raw_parcels;
```

List invalid features with reason (when supported):

```sql
SELECT
  parcel_id,
  ST_GeometryType(geom) AS geom_type,
  ST_IsValid(geom) AS is_valid,
  ST_IsValidReason(geom) AS invalid_reason
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsValid(geom)
LIMIT 50;
```

Cross-layer validity report:

```sql
SELECT 'raw_parcels' AS layer,
  SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM raw.raw_parcels
UNION ALL
SELECT 'raw_roads',
  SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END)
FROM raw.raw_roads
UNION ALL
SELECT 'raw_boundary',
  SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END)
FROM raw.raw_boundary;
```

## Notebook Usage

```python
validity = con.sql("""
  SELECT
    SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom,
    COUNT(geom) AS with_geom
  FROM raw.raw_parcels
  WHERE geom IS NOT NULL
""").df()
validity
```

```python
# Sample invalid rows for manual review
display(con.sql("""
  SELECT parcel_id, ST_IsValidReason(geom) AS reason
  FROM raw.raw_parcels
  WHERE geom IS NOT NULL AND NOT ST_IsValid(geom)
  LIMIT 20
""").df())
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
  SELECT SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
  FROM raw.raw_boundary
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_parcels` | Polygon-heavy layers first |
| `geom` | `geom` | Geometry column |
| ID column | `parcel_id` | Sample listing |
| `LIMIT` | `50` | Cap notebook output |

## Expected Output

| total_rows | with_geom | invalid_geom | invalid_geom_pct |
|------------|-----------|--------------|------------------|
| 12475 | 12470 | 38 | 0.30 |

Sample invalid rows:

| parcel_id | geom_type | is_valid | invalid_reason |
|-----------|-----------|----------|----------------|
| P-12044 | POLYGON | false | Ring Self-intersection |

Healthy layers often show **0** invalid features; Shapefile and GDB sources commonly show a small non-zero rate.

## Interpretation Guidance

- **0 invalid** — proceed to CRS and join checks.
- **Low rate (&lt;1%)** — typical for legacy parcels; repair in `staging` with `ST_MakeValid(geom)`.
- **High rate** — wrong CRS interpretation, corrupted file, or geometry type mismatch; inspect [geometry type count](geometry_type_count.md) and [spatial extent](spatial_extent.md).
- **`ST_IsValidReason`** — use text to prioritize fixes (self-intersection vs ring orientation).
- **Lines and points** — less often invalid than polygons; still check if joins misbehave.

## Common Variations

### Repair preview in staging

```sql
SELECT
  parcel_id,
  ST_IsValid(geom) AS before_valid,
  ST_IsValid(ST_MakeValid(geom)) AS after_valid
FROM raw.raw_parcels
WHERE geom IS NOT NULL AND NOT ST_IsValid(geom)
LIMIT 20;
```

### Persist repaired geometries

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT
  parcel_id,
  owner_name,
  ST_MakeValid(geom) AS geom
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);
```

### Validity after transform

```sql
SELECT
  SUM(CASE WHEN NOT ST_IsValid(ST_Transform(geom, 'EPSG:4326')) THEN 1 ELSE 0 END) AS invalid_after_transform
FROM raw.raw_parcels
WHERE geom IS NOT NULL;
```

Reprojection can occasionally surface validity issues — check before `curated` exports.

## Known Limitations

- `ST_IsValid` / `ST_IsValidReason` support depends on DuckDB spatial version — confirm in your session if reason text is NULL.
- `ST_MakeValid` may change topology slightly (slivers, extra vertices) — document repairs for GIS consumers.
- Very large invalid sets: use `LIMIT` and aggregate counts only in notebooks.
- Invalidity checks do not replace [null geometry check](null_geometry_check.md) — NULL geometries are not "invalid", they are missing.

## Related Pages

- [Null geometry check](null_geometry_check.md)
- [Area / length summary](area_length_summary.md)
- [Spatial join preview](spatial_join_preview.md)
- [Workflow layers](../00_overview/workflow_layers.md) — `ST_MakeValid` in staging

Official reference: [ST_IsValid](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_isvalid) · [ST_MakeValid](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_makevalid)
