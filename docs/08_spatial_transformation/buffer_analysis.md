# Buffer Analysis

Create offset zones around points, lines, or polygons for proximity, access, and impact analysis.

## Purpose

Generate buffer polygons around `staging.stg_roads`, parcel centroids, or facilities using `ST_Buffer`, then use those zones in spatial joins, area summaries, or curated delivery layers.

## When to Use

- Find parcels within 100 m of an arterial road
- Build service areas around facilities (schools, fire stations)
- Create setback zones for regulatory review
- Pre-filter candidate features before expensive nearest-neighbor queries

Buffers belong in `curated` when they are reusable analysis outputs; keep ephemeral buffers in notebook cells or `staging` scratch tables.

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Fixed-distance buffer around roads (planar CRS — meters in EPSG:3857):

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.geo_road_buffers AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  100.0 AS buffer_distance_m,
  ST_Buffer(
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
    100.0
  ) AS geom
FROM staging.stg_roads r
WHERE r.geom IS NOT NULL
  AND NOT ST_IsEmpty(r.geom);
```

Parcels within road buffer — buffer then `ST_Intersects`:

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
WITH road_buffer AS (
  SELECT
    road_id,
    road_name,
    ST_Buffer(ST_Transform(geom, 'EPSG:4326', 'EPSG:3857'), 100.0) AS geom
  FROM staging.stg_roads
  WHERE geom IS NOT NULL
)
SELECT DISTINCT
  p.parcel_id,
  p.owner_name,
  rb.road_id,
  rb.road_name,
  ST_Area(p.geom) AS parcel_area,
  p.geom
FROM staging.stg_parcels p
JOIN road_buffer rb
  ON ST_Intersects(
    ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
    rb.geom
  )
WHERE p.geom IS NOT NULL;
```

Buffer around parcel centroids for point-based proximity:

```sql
CREATE OR REPLACE TABLE curated.geo_parcel_buffers AS
SELECT
  parcel_id,
  50.0 AS buffer_distance_m,
  ST_Buffer(ST_Centroid(geom), 50.0) AS geom
FROM staging.stg_parcels
WHERE geom IS NOT NULL;
```

Dissolved union buffer around all roads in boundary (single service polygon):

```sql
CREATE OR REPLACE TABLE curated.geo_roads_buffer_union AS
SELECT
  ST_Union_Agg(
    ST_Buffer(ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'), 100.0)
  ) AS geom,
  100.0 AS buffer_distance_m
FROM staging.stg_roads r
JOIN staging.stg_boundary b
  ON ST_Intersects(r.geom, b.geom)
WHERE r.geom IS NOT NULL;
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

BUFFER_M = 100.0

con.execute(f"""
CREATE OR REPLACE TABLE curated.geo_road_buffers AS
SELECT
  road_id,
  road_name,
  {BUFFER_M} AS buffer_distance_m,
  ST_Buffer(ST_Transform(geom, 'EPSG:4326', 'EPSG:3857'), {BUFFER_M}) AS geom
FROM staging.stg_roads
WHERE geom IS NOT NULL;
""")

# Parcels near roads
con.execute(f"""
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT DISTINCT
  p.parcel_id,
  p.owner_name,
  ST_Area(p.geom) AS parcel_area,
  p.geom
FROM staging.stg_parcels p
JOIN curated.geo_road_buffers rb
  ON ST_Intersects(
    ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
    rb.geom
  );
""")

con.sql("""
  SELECT COUNT(*) AS parcels_near_roads FROM curated.geo_parcels
""").df()
```

Practice with online boundary to clip buffers:

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
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{source_table}` | `staging.stg_roads` | Layer to buffer |
| `{buffer_distance}` | `100.0` | Units follow CRS (meters in EPSG:3857) |
| `{target_crs}` | `EPSG:3857` | Planar CRS for meter buffers |
| `{output_table}` | `curated.geo_road_buffers` | Buffer polygon table |
| `{join_table}` | `staging.stg_parcels` | Features to test against buffer |
| Segment cap style | default / quadrant segments | Affects buffer smoothness |

## Input Table Pattern

```text
staging.stg_<entity>
```

**`staging.stg_roads`** — lines to buffer

| road_id | road_name | road_class | geom |
|---------|-----------|------------|------|
| R-100 | Main St | arterial | LINESTRING(...) |

**`staging.stg_parcels`** — polygons to test or centroid-buffer

| parcel_id | owner_name | geom |
|-----------|------------|------|
| P-001 | Smith | POLYGON(...) |

**`staging.stg_boundary`** — optional clip extent

| boundary_name | geom |
|---------------|------|
| Study Area | POLYGON(...) |

## Output Table Pattern

```text
curated.geo_<entity>_buffers
curated.geo_<entity>          -- when buffer used as filter, not stored
```

Example: **`curated.geo_road_buffers`**

| road_id | road_name | buffer_distance_m | geom |
|---------|-----------|-------------------|------|
| R-100 | Main St | 100.0 | POLYGON(...) |

Filtered parcels: **`curated.geo_parcels`** (near-road subset)

| parcel_id | owner_name | parcel_area | geom |
|-----------|------------|-------------|------|
| P-001 | Smith | 4500.2 | POLYGON(...) |

## Validation Checks

```sql
-- Buffer row count matches source (one buffer per road)
SELECT
  (SELECT COUNT(*) FROM staging.stg_roads WHERE geom IS NOT NULL) AS roads,
  (SELECT COUNT(*) FROM curated.geo_road_buffers) AS buffers;
```

```sql
-- Buffer area is positive
SELECT COUNT(*) AS empty_buffers
FROM curated.geo_road_buffers
WHERE geom IS NULL OR ST_IsEmpty(geom) OR ST_Area(geom) <= 0;
```

```sql
-- Buffered geometry is valid
SELECT COUNT(*) AS invalid
FROM curated.geo_road_buffers
WHERE NOT ST_IsValid(geom);
```

```sql
-- Parcels near roads should be subset of all parcels
SELECT
  (SELECT COUNT(DISTINCT parcel_id) FROM staging.stg_parcels) AS all_parcels,
  (SELECT COUNT(DISTINCT parcel_id) FROM curated.geo_parcels) AS near_road_parcels;
```

```sql
-- Spot-check distance: centroid within buffer
SELECT p.parcel_id
FROM staging.stg_parcels p
JOIN curated.geo_road_buffers rb
  ON ST_Intersects(
    ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
    rb.geom
  )
LIMIT 10;
```

## Common Variations

### Negative buffer (shrink polygons)

```sql
ST_Buffer(geom, -10.0) AS geom
```

Use only when resulting polygon remains valid.

### Variable buffer by road class

```sql
ST_Buffer(
  ST_Transform(geom, 'EPSG:4326', 'EPSG:3857'),
  CASE road_class
    WHEN 'arterial' THEN 200.0
    WHEN 'collector' THEN 100.0
    ELSE 50.0
  END
) AS geom
```

### Buffer in geographic CRS (degrees — use with caution)

```sql
ST_Buffer(geom, 0.001)  -- ~111 m at equator; not uniform by latitude
```

Prefer projected CRS for meter-based analysis.

### Clip buffer to boundary

```sql
SELECT
  r.road_id,
  ST_Intersection(
    ST_Buffer(ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'), 100.0),
    ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS geom
FROM staging.stg_roads r
CROSS JOIN staging.stg_boundary b
WHERE ST_Intersects(r.geom, b.geom);
```

### `ST_DWithin` instead of buffer + intersect

```sql
ST_DWithin(
  ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
  ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
  100.0
)
```

Faster for point-to-line proximity without materializing buffer polygons.

## Performance Notes

- Buffering every road segment is expensive — filter to `staging.stg_boundary` first.
- `ST_DWithin` avoids storing large buffer polygons when you only need a yes/no proximity test.
- Union of many buffers (`ST_Union_Agg`) can be slow — dissolve only when you need one polygon.
- Transform once per feature in a CTE rather than per join condition.
- Simplify dense linework before buffering if topological detail is unnecessary.

## Known Limitations

- `ST_Buffer` distance units are CRS-dependent — degrees ≠ meters.
- Buffers around long lines in geographic CRS distort at high latitudes.
- Negative buffers can collapse small polygons to empty geometry.
- Overlapping road buffers double-count parcels in simple intersect joins — dedupe by `parcel_id` or dissolve buffers.
- Very large buffer distances on dense road networks produce huge polygons and slow joins.
- Buffer segment count affects smoothness and compute time — defaults are usually sufficient for analysis.

## Related Pages

- [Spatial join](spatial_join.md)
- [Nearest feature](nearest_feature.md)
- [Clip / intersection](clip_intersection.md)
- [Area / length summary](../05_spatial_eda/area_length_summary.md)

Official reference: [ST_Buffer](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_buffer) · [ST_Intersects](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_intersects)
