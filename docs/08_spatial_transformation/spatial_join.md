# Spatial Join

Join attributes from one spatial layer to another using geometry predicates — point-in-polygon, intersects, contains, or within.

## Purpose

Materialize analysis-ready tables by attaching boundary, zoning, or network attributes to parcels and roads in `curated`, after staging layers are cleaned and CRS-aligned.

## When to Use

- Enrich `staging.stg_parcels` with jurisdiction or study-area attributes from `staging.stg_boundary`
- Tag roads that cross a boundary before clip or export
- Point-in-polygon: assign each parcel to exactly one admin polygon
- Many-to-many intersects (parcel × road) when you need crossing counts or flags — document grain carefully

Run [spatial join preview](../05_spatial_eda/spatial_join_preview.md) first to estimate cardinality.

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Point-in-polygon — parcels fully inside boundary (`ST_Within`):

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  p.zoning_code,
  b.boundary_name,
  b.jurisdiction_code,
  p.geom,
  ST_Area(p.geom) AS parcel_area
FROM staging.stg_parcels p
INNER JOIN staging.stg_boundary b
  ON ST_Within(p.geom, b.geom)
WHERE p.geom IS NOT NULL
  AND b.geom IS NOT NULL
  AND NOT ST_IsEmpty(p.geom)
  AND NOT ST_IsEmpty(b.geom);
```

Intersect flag — keep all parcels, mark boundary overlap (`ST_Intersects`):

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  p.zoning_code,
  b.boundary_name,
  ST_Intersects(p.geom, b.geom) AS intersects_boundary,
  ST_Within(p.geom, b.geom) AS fully_within_boundary,
  p.geom
FROM staging.stg_parcels p
CROSS JOIN staging.stg_boundary b
WHERE p.geom IS NOT NULL
  AND b.geom IS NOT NULL;
```

Boundary contains parcel centroid (common for approximate assignment):

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  b.boundary_name,
  p.geom
FROM staging.stg_parcels p
INNER JOIN staging.stg_boundary b
  ON ST_Contains(b.geom, ST_Centroid(p.geom))
WHERE p.geom IS NOT NULL;
```

Roads intersecting boundary — many-to-many preview before dedupe:

```sql
CREATE OR REPLACE TABLE staging.stg_roads_in_boundary_flag AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  b.boundary_name,
  ST_Intersects(r.geom, b.geom) AS intersects_boundary,
  ST_Length(r.geom) AS road_length,
  r.geom
FROM staging.stg_roads r
CROSS JOIN staging.stg_boundary b
WHERE r.geom IS NOT NULL
  AND b.geom IS NOT NULL
  AND ST_Intersects(r.geom, b.geom);
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

# Practice boundary from online GeoJSON
con.execute("""
CREATE OR REPLACE TABLE staging.stg_boundary AS
SELECT
  "properties.NAME" AS boundary_name,
  'CA' AS jurisdiction_code,
  ST_MakeValid(geom) AS geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom);
""")

# After staging.stg_parcels is loaded from Shapefile / GeoParquet ingest
con.execute("""
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  b.boundary_name,
  b.jurisdiction_code,
  ST_Within(p.geom, b.geom) AS fully_within_boundary,
  p.geom
FROM staging.stg_parcels p
CROSS JOIN staging.stg_boundary b
WHERE p.geom IS NOT NULL AND b.geom IS NOT NULL;
""")

con.sql("""
  SELECT
    COUNT(*) AS parcels,
    SUM(CASE WHEN fully_within_boundary THEN 1 ELSE 0 END) AS inside_boundary
  FROM curated.geo_parcels
""").df()
```

```python
# Map-ready sample for manual QA
display(con.sql("""
  SELECT parcel_id, boundary_name, fully_within_boundary
  FROM curated.geo_parcels
  LIMIT 20
""").df())
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{left_table}` | `staging.stg_parcels` | Typically the feature layer you preserve grain for |
| `{right_table}` | `staging.stg_boundary` | Typically fewer polygons (study area, zone) |
| `{predicate}` | `ST_Within`, `ST_Intersects`, `ST_Contains` | Stricter containment vs any touch |
| `{output_table}` | `curated.geo_parcels` | Materialized join result |
| `{id_column}` | `parcel_id`, `road_id` | Business keys for validation |
| CRS | `ST_Transform(geom, 'EPSG:4326')` | Both sides must share CRS |

## Input Table Pattern

```text
staging.stg_<entity>
```

**`staging.stg_parcels`** — polygon features

| parcel_id | owner_name | zoning_code | geom |
|-----------|------------|-------------|------|
| P-001 | Smith | R-1 | POLYGON(...) |
| P-002 | Jones | C-2 | POLYGON(...) |

**`staging.stg_boundary`** — single or few polygons

| boundary_name | jurisdiction_code | geom |
|---------------|-------------------|------|
| Study Area | SA-01 | POLYGON(...) |

**`staging.stg_roads`** — line features (for intersect joins)

| road_id | road_name | road_class | geom |
|---------|-----------|------------|------|
| R-100 | Main St | arterial | LINESTRING(...) |

## Output Table Pattern

```text
curated.geo_<entity>[_<qualifier>]
```

Example: **`curated.geo_parcels`** — parcels with boundary attributes

| parcel_id | owner_name | boundary_name | fully_within_boundary | geom |
|-----------|------------|---------------|----------------------|------|
| P-001 | Smith | Study Area | true | POLYGON(...) |
| P-002 | Jones | Study Area | false | POLYGON(...) |

Intermediate flag table (optional): **`staging.stg_roads_in_boundary_flag`**

## Validation Checks

```sql
-- Row count vs join type
SELECT
  (SELECT COUNT(*) FROM staging.stg_parcels) AS stg_parcels,
  (SELECT COUNT(*) FROM curated.geo_parcels) AS geo_parcels;
-- ST_Within inner join: geo_parcels <= stg_parcels
-- CROSS JOIN + flag: geo_parcels = stg_parcels × boundary rows
```

```sql
-- Duplicate parcel keys after point-in-polygon (should be 0 or 1 per boundary)
SELECT parcel_id, COUNT(*) AS n
FROM curated.geo_parcels
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Orphans: parcels with no boundary match (inner join only)
SELECT p.parcel_id
FROM staging.stg_parcels p
LEFT JOIN curated.geo_parcels g ON p.parcel_id = g.parcel_id
WHERE g.parcel_id IS NULL
LIMIT 50;
```

```sql
-- Predicate sanity: within implies intersects
SELECT COUNT(*) AS inconsistent
FROM curated.geo_parcels
WHERE fully_within_boundary
  AND NOT ST_Intersects(geom, (SELECT geom FROM staging.stg_boundary LIMIT 1));
```

```sql
-- Invalid geometry in output
SELECT COUNT(*) AS invalid_geom
FROM curated.geo_parcels
WHERE NOT ST_IsValid(geom);
```

## Common Variations

### Left join — keep all parcels, null boundary when no match

```sql
SELECT
  p.parcel_id,
  p.geom,
  b.boundary_name
FROM staging.stg_parcels p
LEFT JOIN staging.stg_boundary b
  ON ST_Within(p.geom, b.geom);
```

### Reproject before join

```sql
ON ST_Within(
  ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
  ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
)
```

### Deduplicate many-to-many parcel × road

```sql
SELECT DISTINCT ON (p.parcel_id, r.road_id)
  p.parcel_id,
  r.road_id,
  ST_Intersects(p.geom, r.geom) AS crosses_road
FROM staging.stg_parcels p
JOIN staging.stg_roads r ON ST_Intersects(p.geom, r.geom);
```

### Aggregate roads per parcel

```sql
SELECT
  p.parcel_id,
  COUNT(r.road_id) AS roads_intersecting,
  p.geom
FROM staging.stg_parcels p
LEFT JOIN staging.stg_roads r ON ST_Intersects(p.geom, r.geom)
GROUP BY p.parcel_id, p.geom;
```

## Performance Notes

- Filter null and empty geometries before joining — smaller build side.
- When `staging.stg_boundary` is a single polygon, `CROSS JOIN` + predicate is idiomatic.
- Pre-filter by bounding box: `ST_Intersects(ST_Envelope(p.geom), ST_Envelope(b.geom))` before exact predicate (if supported in your DuckDB version).
- Deduplicate the right table to one row per zone key before join to prevent explosion.
- Run intersect **counts** in EDA before full materialization on large layers.
- `EXPLAIN` expensive joins; consider materializing a clipped subset first.

## Known Limitations

- `ST_Intersects` on parcel × road is many-to-many — one parcel can match dozens of road segments.
- `ST_Within` excludes parcels that touch the boundary edge but extend outside.
- `ST_Contains` vs `ST_Within` differ by argument order — `ST_Contains(A, B)` ≡ `ST_Within(B, A)`.
- CRS mismatch produces false negatives — align CRS in `staging` before `curated`.
- Invalid geometry can cause missed matches — repair with `ST_MakeValid` in `staging`.
- DuckDB spatial indexing behavior evolves — test performance on your data sizes.

## Related Pages

- [Spatial join preview](../05_spatial_eda/spatial_join_preview.md)
- [Spatial geometry cleaning](../06_cleaning/spatial_geometry_cleaning.md)
- [Clip / intersection](clip_intersection.md)
- [Build curated spatial layer](build_curated_spatial_layer.md)

Official reference: [ST_Intersects](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_intersects) · [ST_Within](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_within) · [ST_Contains](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_contains)
