# Nearest Feature

Find the closest road, facility, or boundary feature for each parcel (or point) using `ST_Distance`.

## Purpose

Attach nearest-neighbor attributes — road name, distance, travel context — to `staging.stg_parcels` without a full spatial join explosion, producing one row per parcel in `curated.geo_parcels`.

## When to Use

- Assign each parcel its nearest arterial road
- Distance to study-area boundary for edge parcels
- Site selection: closest facility within a search radius
- QA: flag parcels unusually far from the road network

Use [buffer analysis](buffer_analysis.md) when you need all features within a zone, not just the single closest.

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Nearest road per parcel with `ROW_NUMBER` over distance:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.geo_parcels AS
WITH distances AS (
  SELECT
    p.parcel_id,
    p.owner_name,
    r.road_id,
    r.road_name,
    r.road_class,
    ST_Distance(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
    ) AS distance_m,
    p.geom
  FROM staging.stg_parcels p
  CROSS JOIN staging.stg_roads r
  WHERE p.geom IS NOT NULL
    AND r.geom IS NOT NULL
)
SELECT
  parcel_id,
  owner_name,
  road_id AS nearest_road_id,
  road_name AS nearest_road_name,
  road_class AS nearest_road_class,
  distance_m AS nearest_road_distance_m,
  geom
FROM distances
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY parcel_id
  ORDER BY distance_m ASC, road_id ASC
) = 1;
```

Nearest road with maximum search radius:

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
WITH distances AS (
  SELECT
    p.parcel_id,
    p.owner_name,
    r.road_id,
    r.road_name,
    ST_Distance(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
    ) AS distance_m,
    p.geom
  FROM staging.stg_parcels p
  JOIN staging.stg_roads r
    ON ST_DWithin(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
      500.0
    )
  WHERE p.geom IS NOT NULL
)
SELECT
  parcel_id,
  owner_name,
  road_id AS nearest_road_id,
  road_name AS nearest_road_name,
  distance_m AS nearest_road_distance_m,
  geom
FROM distances
QUALIFY ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY distance_m, road_id) = 1;
```

Distance to boundary (single polygon):

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  ST_Distance(
    ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS distance_to_boundary_m,
  ST_Within(p.geom, b.geom) AS inside_boundary,
  p.geom
FROM staging.stg_parcels p
CROSS JOIN staging.stg_boundary b
WHERE p.geom IS NOT NULL AND b.geom IS NOT NULL;
```

K-nearest roads (top 3 per parcel):

```sql
CREATE OR REPLACE TABLE curated.geo_parcel_nearest_roads AS
SELECT
  p.parcel_id,
  r.road_id,
  r.road_name,
  ST_Distance(
    ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS distance_m,
  ROW_NUMBER() OVER (
    PARTITION BY p.parcel_id
    ORDER BY ST_Distance(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
    )
  ) AS rank_nearest
FROM staging.stg_parcels p
CROSS JOIN staging.stg_roads r
WHERE p.geom IS NOT NULL AND r.geom IS NOT NULL
QUALIFY rank_nearest <= 3;
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

MAX_DISTANCE_M = 500.0

con.execute(f"""
CREATE OR REPLACE TABLE curated.geo_parcels AS
WITH distances AS (
  SELECT
    p.parcel_id,
    p.owner_name,
    r.road_id,
    r.road_name,
    ST_Distance(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
    ) AS distance_m,
    p.geom
  FROM staging.stg_parcels p
  JOIN staging.stg_roads r
    ON ST_DWithin(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
      {MAX_DISTANCE_M}
    )
)
SELECT
  parcel_id,
  owner_name,
  road_id AS nearest_road_id,
  road_name AS nearest_road_name,
  distance_m AS nearest_road_distance_m,
  geom
FROM distances
QUALIFY ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY distance_m, road_id) = 1;
""")

con.sql("""
  SELECT
    COUNT(*) AS parcels,
    AVG(nearest_road_distance_m) AS avg_distance_m,
    MAX(nearest_road_distance_m) AS max_distance_m
  FROM curated.geo_parcels
""").df()
```

```python
# Flag parcels with no road within search radius
orphans = con.sql("""
  SELECT p.parcel_id
  FROM staging.stg_parcels p
  LEFT JOIN curated.geo_parcels g ON p.parcel_id = g.parcel_id
  WHERE g.parcel_id IS NULL
""").df()
orphans
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{point_table}` | `staging.stg_parcels` | Parcel polygons — use centroid for distance |
| `{candidate_table}` | `staging.stg_roads` | Features to search |
| `{max_distance}` | `500.0` | Search radius in meters (projected CRS) |
| `{tie_breaker}` | `road_id ASC` | Stable sort when distances tie |
| `{k}` | `3` | K-nearest count |
| `{output_table}` | `curated.geo_parcels` | One row per parcel |

## Input Table Pattern

```text
staging.stg_<entity>
```

**`staging.stg_parcels`**

| parcel_id | owner_name | geom |
|-----------|------------|------|
| P-001 | Smith | POLYGON(...) |

**`staging.stg_roads`**

| road_id | road_name | road_class | geom |
|---------|-----------|------------|------|
| R-100 | Main St | arterial | LINESTRING(...) |
| R-101 | Oak Ave | local | LINESTRING(...) |

**`staging.stg_boundary`** (optional — distance-to-edge)

| boundary_name | geom |
|---------------|------|
| Study Area | POLYGON(...) |

## Output Table Pattern

```text
curated.geo_<entity>
curated.geo_<entity>_nearest_<candidate>   -- K-nearest long format
```

Example: **`curated.geo_parcels`** — one row per parcel

| parcel_id | nearest_road_id | nearest_road_name | nearest_road_distance_m | geom |
|-----------|-----------------|-------------------|-------------------------|------|
| P-001 | R-100 | Main St | 12.4 | POLYGON(...) |

K-nearest: **`curated.geo_parcel_nearest_roads`**

| parcel_id | road_id | road_name | distance_m | rank_nearest |
|-----------|---------|-----------|------------|--------------|
| P-001 | R-100 | Main St | 12.4 | 1 |
| P-001 | R-101 | Oak Ave | 45.2 | 2 |

## Validation Checks

```sql
-- One row per parcel in nearest-neighbor output
SELECT parcel_id, COUNT(*) AS n
FROM curated.geo_parcels
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Distance non-negative
SELECT COUNT(*) AS bad_distance
FROM curated.geo_parcels
WHERE nearest_road_distance_m < 0;
```

```sql
-- Nearest road should be closer than a random other road (spot check)
SELECT
  g.parcel_id,
  g.nearest_road_distance_m,
  ST_Distance(
    ST_Transform(ST_Centroid(g.geom), 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS other_road_distance_m
FROM curated.geo_parcels g
JOIN staging.stg_roads r ON r.road_id <> g.nearest_road_id
LIMIT 20;
```

```sql
-- Coverage: parcels with no match inside max distance
SELECT COUNT(*) AS unmatched
FROM staging.stg_parcels p
LEFT JOIN curated.geo_parcels g ON p.parcel_id = g.parcel_id
WHERE g.parcel_id IS NULL;
```

```sql
-- Distribution summary
SELECT
  MIN(nearest_road_distance_m) AS min_m,
  APPROX_QUANTILE(nearest_road_distance_m, 0.5) AS median_m,
  MAX(nearest_road_distance_m) AS max_m
FROM curated.geo_parcels;
```

## Common Variations

### Nearest polygon edge (not centroid)

```sql
ST_Distance(
  ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
  ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
)
```

Uses minimum distance between polygon boundary and line.

### Filter candidate roads by class

```sql
FROM staging.stg_roads r
WHERE r.road_class IN ('arterial', 'collector')
```

### Nearest only among roads intersecting boundary

```sql
FROM staging.stg_roads r
JOIN staging.stg_boundary b ON ST_Intersects(r.geom, b.geom)
```

### Keep parcel grain with left join after subquery

```sql
SELECT
  p.parcel_id,
  n.nearest_road_id,
  n.nearest_road_distance_m,
  p.geom
FROM staging.stg_parcels p
LEFT JOIN (
  SELECT * FROM distances
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY distance_m) = 1
) n ON p.parcel_id = n.parcel_id;
```

## Performance Notes

- `CROSS JOIN` + `ROW_NUMBER` is O(parcels × roads) — use `ST_DWithin` pre-filter or boundary clip on roads first.
- Restrict `staging.stg_roads` to study area before distance calculation.
- Transform geometries once in a CTE; reuse transformed columns in distance and window.
- For very large road networks, consider tiling by grid or aggregating roads to major classes only.
- K-nearest with small `k` still requires all candidates unless pre-filtered.

## Known Limitations

- Centroid distance misrepresents large or irregular parcels — use polygon-to-line distance when precision matters.
- Equidistant ties need explicit `ORDER BY` tie-breaker (`road_id`).
- Geographic CRS distances are not true meters — project to EPSG:3857 or local state plane.
- Nearest straight-line distance ≠ network (driving) distance.
- Parcels beyond `max_distance` are dropped unless you use `LEFT JOIN` pattern.
- No built-in spatial index guarantee — performance depends on data size and predicates.

## Related Pages

- [Spatial join](spatial_join.md)
- [Buffer analysis](buffer_analysis.md)
- [Spatial join preview](../05_spatial_eda/spatial_join_preview.md)

Official reference: [ST_Distance](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_distance) · [ST_DWithin](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_dwithin)
