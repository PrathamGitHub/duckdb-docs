# Clip / Intersection

Clip lines and polygons to a boundary or compute geometric intersections for overlay analysis.

## Purpose

Trim `staging.stg_roads` to a study area, split parcels at boundaries, or extract the overlapping portion of two layers using `ST_Intersection` and containment predicates (`ST_Within`, `ST_Intersects`).

## When to Use

- Produce `curated.geo_roads_in_boundary` for maps limited to jurisdiction
- Clip parcel polygons to analysis extent
- Compute shared area between parcels and zones
- Remove features entirely outside `staging.stg_boundary`

Typical workflow: `staging` → clip in `curated` → validate geometry → [export](export_ready_spatial_layer.md).

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Clip roads to boundary — keep only intersecting segments, geometry trimmed:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.geo_roads_in_boundary AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  b.boundary_name,
  ST_Intersection(
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS geom,
  ST_Length(
    ST_Intersection(
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
    )
  ) AS clipped_length_m
FROM staging.stg_roads r
CROSS JOIN staging.stg_boundary b
WHERE r.geom IS NOT NULL
  AND b.geom IS NOT NULL
  AND ST_Intersects(r.geom, b.geom)
  AND NOT ST_IsEmpty(
    ST_Intersection(
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
    )
  );
```

Filter-only clip (no geometry change) — roads inside boundary:

```sql
CREATE OR REPLACE TABLE curated.geo_roads_in_boundary AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  ST_Length(r.geom) AS road_length,
  r.geom
FROM staging.stg_roads r
JOIN staging.stg_boundary b
  ON ST_Intersects(r.geom, b.geom)
WHERE r.geom IS NOT NULL;
```

Clip parcels — polygon intersection with boundary:

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  b.boundary_name,
  ST_Intersection(
    ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS geom,
  ST_Area(
    ST_Intersection(
      ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
    )
  ) AS clipped_area
FROM staging.stg_parcels p
CROSS JOIN staging.stg_boundary b
WHERE ST_Intersects(p.geom, b.geom)
  AND p.geom IS NOT NULL;
```

Parcels fully inside boundary (attribute clip, preserve original geom):

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  ST_Area(p.geom) AS parcel_area,
  p.geom
FROM staging.stg_parcels p
JOIN staging.stg_boundary b
  ON ST_Within(p.geom, b.geom)
WHERE p.geom IS NOT NULL;
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

# Online boundary for practice clip
con.execute("""
CREATE OR REPLACE TABLE staging.stg_boundary AS
SELECT
  "properties.NAME" AS boundary_name,
  ST_MakeValid(geom) AS geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
WHERE geom IS NOT NULL;
""")

con.execute("""
CREATE OR REPLACE TABLE curated.geo_roads_in_boundary AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  ST_Intersection(
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS geom,
  ST_Length(ST_Intersection(
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
    ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
  )) AS clipped_length_m
FROM staging.stg_roads r
CROSS JOIN staging.stg_boundary b
WHERE ST_Intersects(r.geom, b.geom);
""")

con.sql("""
  SELECT
    COUNT(*) AS clipped_roads,
    SUM(clipped_length_m) AS total_length_m
  FROM curated.geo_roads_in_boundary
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
""").df()
```

```python
# Compare road counts before and after clip
con.sql("""
  SELECT
    (SELECT COUNT(*) FROM staging.stg_roads) AS all_roads,
    (SELECT COUNT(*) FROM curated.geo_roads_in_boundary) AS clipped_roads
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{feature_table}` | `staging.stg_roads` | Layer to clip |
| `{clip_table}` | `staging.stg_boundary` | Boundary polygon |
| `{predicate}` | `ST_Intersects`, `ST_Within` | Filter before `ST_Intersection` |
| `{output_table}` | `curated.geo_roads_in_boundary` | Clipped result |
| `{target_crs}` | `EPSG:3857` | Planar ops for length/area |
| Min area / length | `clipped_length_m > 1` | Drop slivers |

## Input Table Pattern

```text
staging.stg_<entity>
```

**`staging.stg_roads`**

| road_id | road_name | road_class | geom |
|---------|-----------|------------|------|
| R-100 | Main St | arterial | LINESTRING(...) |

**`staging.stg_parcels`**

| parcel_id | owner_name | geom |
|-----------|------------|------|
| P-001 | Smith | POLYGON(...) |

**`staging.stg_boundary`**

| boundary_name | geom |
|---------------|------|
| Study Area | POLYGON(...) |

## Output Table Pattern

```text
curated.geo_<entity>_in_<clip>
curated.geo_<entity>   -- clipped parcels
```

Example: **`curated.geo_roads_in_boundary`**

| road_id | road_name | road_class | clipped_length_m | geom |
|---------|-----------|------------|------------------|------|
| R-100 | Main St | arterial | 1250.3 | LINESTRING(...) |

Example: **`curated.geo_parcels`** (clipped polygons)

| parcel_id | owner_name | clipped_area | geom |
|-----------|------------|--------------|------|
| P-001 | Smith | 4200.1 | POLYGON(...) |

## Validation Checks

```sql
-- Clipped features should not extend outside boundary
SELECT COUNT(*) AS leaks
FROM curated.geo_roads_in_boundary r
CROSS JOIN staging.stg_boundary b
WHERE NOT ST_Within(
  ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
  ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
);
```

```sql
-- No empty geometries after clip
SELECT COUNT(*) AS empty_geom
FROM curated.geo_roads_in_boundary
WHERE geom IS NULL OR ST_IsEmpty(geom);
```

```sql
-- Length reconciliation (clipped <= original)
SELECT
  r.road_id,
  ST_Length(ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')) AS original_m,
  c.clipped_length_m
FROM staging.stg_roads r
JOIN curated.geo_roads_in_boundary c ON r.road_id = c.road_id
WHERE c.clipped_length_m > ST_Length(ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')) + 0.01;
```

```sql
-- Invalid geometry after intersection
SELECT COUNT(*) AS invalid
FROM curated.geo_roads_in_boundary
WHERE NOT ST_IsValid(geom);
```

```sql
-- Row count: clipped roads <= total roads
SELECT
  (SELECT COUNT(*) FROM staging.stg_roads) AS source_roads,
  (SELECT COUNT(*) FROM curated.geo_roads_in_boundary) AS clipped_roads;
```

## Common Variations

### Drop topology slivers below threshold

```sql
WHERE clipped_length_m > 1.0
```

```sql
WHERE clipped_area > 10.0
```

### Repair after intersection

```sql
ST_MakeValid(ST_Intersection(a.geom, b.geom)) AS geom
```

### Multi-boundary: clip to each zone separately

```sql
SELECT
  r.road_id,
  b.boundary_name,
  ST_Intersection(r.geom, b.geom) AS geom
FROM staging.stg_roads r
JOIN staging.stg_boundary b ON ST_Intersects(r.geom, b.geom);
```

### Compute intersection area only (no new geom column)

```sql
ST_Area(ST_Intersection(p.geom, z.geom)) AS overlap_area
```

### Clip using envelope pre-filter

```sql
WHERE ST_Intersects(ST_Envelope(r.geom), ST_Envelope(b.geom))
  AND ST_Intersects(r.geom, b.geom)
```

## Performance Notes

- Filter with `ST_Intersects` before calling `ST_Intersection` — avoids work on disjoint pairs.
- Single-row `staging.stg_boundary` + `CROSS JOIN` is efficient for one study area.
- `ST_Intersection` is more expensive than filter-only clips — use filter when full geometry trim is not required.
- Project once in a CTE; reuse transformed `geom` for intersection, length, and area.
- Drop slivers early to shrink downstream tables.

## Known Limitations

- `ST_Intersection` can return `GEOMETRYCOLLECTION` or lower-dimension results (points, lines from polygon overlap).
- Clipping lines may split one road into multiple parts — row count can exceed source if not dissolved by `road_id`.
- Floating-point boundaries cause micro-slivers — apply length/area thresholds.
- Invalid input geometry produces invalid intersections — repair in `staging` first.
- Partially overlapping parcels split across boundary require intersection, not `ST_Within` filter.
- CRS must match (or be transformed) for correct clip results.

## Related Pages

- [Spatial join](spatial_join.md)
- [Build curated spatial layer](build_curated_spatial_layer.md)
- [Export-ready spatial layer](export_ready_spatial_layer.md)
- [Spatial join preview](../05_spatial_eda/spatial_join_preview.md)

Official reference: [ST_Intersection](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_intersection) · [ST_Intersects](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_intersects) · [ST_Within](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_within)
