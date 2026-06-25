# Spatial Join Preview

Preview how two layers relate spatially — match counts, sample intersections, and orphan rates — before building full `curated` spatial joins.

## Purpose

Use `ST_Intersects` (and related predicates) on `raw.raw_parcels`, `raw.raw_roads`, and `raw.raw_boundary` to estimate join cardinality and data-quality issues without materializing a large `curated` table.

## When to Use

- After geometry validity, null, and [CRS check](crs_check.md) pass
- Before point-in-polygon or overlay logic in `curated`
- When estimating how many parcels touch a boundary or how many roads cross a study area
- To catch CRS mismatch (0% intersects when extents should overlap)

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

### Intersect count: parcels inside boundary

```sql
SELECT
  COUNT(*) AS parcel_count,
  SUM(CASE WHEN ST_Intersects(p.geom, b.geom) THEN 1 ELSE 0 END) AS parcels_intersecting_boundary,
  ROUND(100.0 * SUM(CASE WHEN ST_Intersects(p.geom, b.geom) THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_intersecting
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE p.geom IS NOT NULL
  AND b.geom IS NOT NULL
  AND NOT ST_IsEmpty(p.geom)
  AND NOT ST_IsEmpty(b.geom);
```

### Orphan parcels (no intersection with boundary)

```sql
SELECT
  p.parcel_id,
  ST_GeometryType(p.geom) AS geom_type
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE p.geom IS NOT NULL
  AND b.geom IS NOT NULL
  AND NOT ST_Intersects(p.geom, b.geom)
LIMIT 50;
```

### Roads intersecting boundary — match count

```sql
SELECT
  COUNT(*) AS road_count,
  SUM(CASE WHEN ST_Intersects(r.geom, b.geom) THEN 1 ELSE 0 END) AS roads_intersecting_boundary
FROM raw.raw_roads r
CROSS JOIN raw.raw_boundary b
WHERE r.geom IS NOT NULL
  AND b.geom IS NOT NULL;
```

### Sample attribute preview (parcel + boundary flag)

```sql
SELECT
  p.parcel_id,
  p.zoning_code,
  ST_Intersects(p.geom, b.geom) AS inside_boundary
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE p.geom IS NOT NULL
  AND b.geom IS NOT NULL
LIMIT 25;
```

### Pairwise join cardinality warning (parcels × roads sample)

```sql
SELECT
  COUNT(*) AS intersecting_pairs
FROM raw.raw_parcels p
INNER JOIN raw.raw_roads r
  ON ST_Intersects(p.geom, r.geom)
WHERE p.geom IS NOT NULL
  AND r.geom IS NOT NULL;
```

High counts imply a many-to-many relationship — use `ST_Intersects` with care in `curated`; consider `ST_Within`, buffers, or dedupe rules.

## Notebook Usage

```python
# Quick intersect rate: parcels vs boundary
preview = con.sql("""
  SELECT
    COUNT(*) AS parcels,
    SUM(CASE WHEN ST_Intersects(p.geom, b.geom) THEN 1 ELSE 0 END) AS hits
  FROM raw.raw_parcels p
  CROSS JOIN raw.raw_boundary b
  WHERE p.geom IS NOT NULL AND b.geom IS NOT NULL
""").df()
preview["pct"] = 100.0 * preview.hits / preview.parcels
preview
```

```python
# Sample rows for manual map check
display(con.sql("""
  SELECT p.parcel_id, ST_Intersects(p.geom, b.geom) AS inside
  FROM raw.raw_parcels p
  CROSS JOIN raw.raw_boundary b
  WHERE p.geom IS NOT NULL
  LIMIT 20
""").df())
```

Practice with online boundary:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_boundary AS
SELECT * FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

# After loading local or sample parcels into raw.raw_parcels
con.sql("""
  SELECT SUM(CASE WHEN ST_Intersects(p.geom, b.geom) THEN 1 ELSE 0 END) AS hits
  FROM raw.raw_parcels p
  CROSS JOIN raw.raw_boundary b
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Left table | `raw.raw_parcels` | Typically many features |
| Right table | `raw.raw_boundary` | Typically fewer (study area) |
| Predicate | `ST_Intersects`, `ST_Within` | Stricter containment |
| ID columns | `parcel_id`, `road_id` | Sample listings |
| CRS | Reproject in subquery | Both layers same CRS |

## Expected Output

**Intersect rate (parcels vs boundary):**

| parcel_count | parcels_intersecting_boundary | pct_intersecting |
|--------------|-------------------------------|------------------|
| 12475 | 12410 | 99.48 |

**Orphan sample:**

| parcel_id | geom_type |
|-----------|-----------|
| P-00881 | POLYGON |

**Roads intersecting boundary:**

| road_count | roads_intersecting_boundary |
|------------|----------------------------|
| 8420 | 6150 |

Healthy study-area clips: **high** pct for parcels fully inside jurisdiction; orphans may be cross-border parcels or CRS issues.

## Interpretation Guidance

- **~100% parcels intersect boundary** — expected when boundary is the jurisdiction hull and parcels are clipped.
- **0% intersects, extents overlap visually** — CRS mismatch; run [CRS check](crs_check.md) and align with `ST_Transform`.
- **Many orphans** — boundary too small, wrong admin polygon, or parcels include neighboring county.
- **Parcels × roads pair count very high** — normal for dense networks; full join explodes rows — use preview before `curated`.
- **Invalid geometry** — can cause false negatives; run [invalid geometry check](invalid_geometry_check.md) first.

## Common Variations

### Reproject both layers in preview

```sql
SELECT
  SUM(CASE WHEN ST_Intersects(
    ST_Transform(p.geom, 'EPSG:4326'),
    ST_Transform(b.geom, 'EPSG:4326')
  ) THEN 1 ELSE 0 END) AS hits
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE p.geom IS NOT NULL AND b.geom IS NOT NULL;
```

### Strict containment (`ST_Within`)

```sql
SELECT
  COUNT(*) AS parcels,
  SUM(CASE WHEN ST_Within(p.geom, b.geom) THEN 1 ELSE 0 END) AS fully_inside
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE p.geom IS NOT NULL AND b.geom IS NOT NULL;
```

Intersects includes edge-touching parcels; `ST_Within` is stricter.

### Nearest-neighbor count preview (roads near parcels, limited)

```sql
SELECT
  p.parcel_id,
  COUNT(*) AS roads_within_buffer
FROM raw.raw_parcels p
JOIN raw.raw_roads r
  ON ST_DWithin(
    ST_Transform(p.geom, 'EPSG:3857'),
    ST_Transform(r.geom, 'EPSG:3857'),
    100
  )
WHERE p.geom IS NOT NULL AND r.geom IS NOT NULL
GROUP BY p.parcel_id
ORDER BY roads_within_buffer DESC
LIMIT 20;
```

### Promote to staging join (after preview passes)

```sql
CREATE OR REPLACE TABLE staging.stg_parcels_in_boundary AS
SELECT
  p.parcel_id,
  p.zoning_code,
  p.geom
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE ST_Intersects(p.geom, b.geom)
  AND p.geom IS NOT NULL;
```

## Known Limitations

- `CROSS JOIN` with single-row boundary is fine; multi-row boundary tables need explicit key or `UNION`/`JOIN` logic.
- Full `INNER JOIN ... ON ST_Intersects` on large layers can be **slow** — use counts and `LIMIT` samples in EDA only.
- Preview does not replace deduplication — one parcel can intersect many roads.
- Predicate choice matters: `ST_Intersects` ≠ `ST_Contains` ≠ `ST_Within`.
- Spatial indexes are not covered here; performance tuning belongs in production `curated` pipelines.

## Related Pages

- [CRS check](crs_check.md)
- [Spatial extent](spatial_extent.md)
- [Invalid geometry check](invalid_geometry_check.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [ST_Intersects](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_intersects) · [ST_Within](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_within)
