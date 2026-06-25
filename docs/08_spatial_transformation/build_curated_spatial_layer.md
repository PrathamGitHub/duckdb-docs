# Build Curated Spatial Layer

Publish analysis-ready spatial tables from cleaned `staging` layers with standard schema, derived measures, and documented grain.

## Purpose

Transform `staging.stg_parcels`, `staging.stg_roads`, and `staging.stg_boundary` into durable `curated` models — `geo_parcels`, `geo_roads_in_boundary` — that downstream notebooks, dashboards, and exports can trust.

## When to Use

- After [spatial geometry cleaning](../06_cleaning/spatial_geometry_cleaning.md) and spatial EDA pass
- When combining spatial transforms (join, clip, buffer, nearest) into one conformed layer
- Before [export-ready spatial layer](export_ready_spatial_layer.md) validation and `COPY` to `output`
- When you need repeatable business logic separated from ingest and cleaning

This is the `staging → curated` step in the spatial workflow.

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

End-to-end curated parcels — clip, enrich, measure:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.geo_parcels AS
WITH clipped AS (
  SELECT
    p.parcel_id,
    p.owner_name,
    p.zoning_code,
    b.boundary_name,
    ST_Intersection(
      ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(b.geom, 'EPSG:4326', 'EPSG:3857')
    ) AS geom_planar
  FROM staging.stg_parcels p
  JOIN staging.stg_boundary b
    ON ST_Intersects(p.geom, b.geom)
  WHERE p.geom IS NOT NULL
    AND NOT ST_IsEmpty(p.geom)
),
measured AS (
  SELECT
    parcel_id,
    owner_name,
    zoning_code,
    boundary_name,
    ST_Transform(geom_planar, 'EPSG:3857', 'EPSG:4326') AS geom,
    ST_Area(geom_planar) AS area_sqm,
    ST_Perimeter(geom_planar) AS perimeter_m
  FROM clipped
  WHERE geom_planar IS NOT NULL
    AND NOT ST_IsEmpty(geom_planar)
)
SELECT
  parcel_id,
  owner_name,
  zoning_code,
  boundary_name,
  area_sqm,
  perimeter_m,
  geom
FROM measured
WHERE area_sqm > 1.0;
```

Curated roads in boundary with length:

```sql
CREATE OR REPLACE TABLE curated.geo_roads_in_boundary AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  b.boundary_name,
  ST_Length(
    ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
  ) AS road_length_m,
  r.geom
FROM staging.stg_roads r
JOIN staging.stg_boundary b
  ON ST_Intersects(r.geom, b.geom)
WHERE r.geom IS NOT NULL
  AND NOT ST_IsEmpty(r.geom);
```

Curated parcels with nearest road attributes:

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
WITH nearest AS (
  SELECT
    p.parcel_id,
    r.road_id AS nearest_road_id,
    r.road_name AS nearest_road_name,
    ST_Distance(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')
    ) AS nearest_road_distance_m
  FROM staging.stg_parcels p
  JOIN staging.stg_roads r
    ON ST_DWithin(
      ST_Transform(ST_Centroid(p.geom), 'EPSG:4326', 'EPSG:3857'),
      ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857'),
      500.0
    )
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.parcel_id
    ORDER BY nearest_road_distance_m
  ) = 1
)
SELECT
  p.parcel_id,
  p.owner_name,
  p.zoning_code,
  n.nearest_road_id,
  n.nearest_road_name,
  n.nearest_road_distance_m,
  ST_Area(ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857')) AS area_sqm,
  p.geom
FROM staging.stg_parcels p
LEFT JOIN nearest n ON p.parcel_id = n.parcel_id
WHERE p.geom IS NOT NULL;
```

Standard curated column contract — add lineage fields last:

```sql
SELECT
  parcel_id,
  owner_name,
  zoning_code,
  boundary_name,
  area_sqm,
  perimeter_m,
  nearest_road_distance_m,
  geom,
  CURRENT_TIMESTAMP AS curated_at
FROM measured;  -- final CTE from clip / nearest pipeline above
```

## Notebook Usage

```python
con.execute("INSTALL spatial; LOAD spatial;")

# 1. Load practice boundary
con.execute("""
CREATE OR REPLACE TABLE staging.stg_boundary AS
SELECT
  "properties.NAME" AS boundary_name,
  ST_MakeValid(geom) AS geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

# 2. Build curated parcels (assumes staging.stg_parcels exists)
con.execute("""
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  p.parcel_id,
  p.owner_name,
  p.zoning_code,
  b.boundary_name,
  ST_Area(ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857')) AS area_sqm,
  ST_Length(ST_Transform(p.geom, 'EPSG:4326', 'EPSG:3857')) AS perimeter_m,
  p.geom
FROM staging.stg_parcels p
JOIN staging.stg_boundary b ON ST_Within(p.geom, b.geom)
WHERE p.geom IS NOT NULL;
""")

# 3. Build curated roads in boundary
con.execute("""
CREATE OR REPLACE TABLE curated.geo_roads_in_boundary AS
SELECT
  r.road_id,
  r.road_name,
  r.road_class,
  ST_Length(ST_Transform(r.geom, 'EPSG:4326', 'EPSG:3857')) AS road_length_m,
  r.geom
FROM staging.stg_roads r
JOIN staging.stg_boundary b ON ST_Intersects(r.geom, b.geom)
WHERE r.geom IS NOT NULL;
""")

# QA summary
con.sql("""
  SELECT 'geo_parcels' AS layer, COUNT(*) AS n FROM curated.geo_parcels
  UNION ALL
  SELECT 'geo_roads_in_boundary', COUNT(*) FROM curated.geo_roads_in_boundary
""").df()
```

```python
# Optional: simplify for web delivery while keeping full geom in curated
con.execute("""
CREATE OR REPLACE TABLE curated.geo_parcels_web AS
SELECT
  parcel_id,
  owner_name,
  area_sqm,
  ST_SimplifyPreserveTopology(geom, 0.0001) AS geom
FROM curated.geo_parcels;
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{stg_parcels}` | `staging.stg_parcels` | Cleaned parcel polygons |
| `{stg_roads}` | `staging.stg_roads` | Cleaned road lines |
| `{stg_boundary}` | `staging.stg_boundary` | Study-area polygon |
| `{output_parcels}` | `curated.geo_parcels` | Curated parcel model |
| `{output_roads}` | `curated.geo_roads_in_boundary` | Curated road subset |
| `{measure_crs}` | `EPSG:3857` | Planar CRS for area/length |
| `{min_area}` | `1.0` | Sliver filter (sq m) |
| `{curated_at}` | `CURRENT_TIMESTAMP` | Lineage column |

## Input Table Pattern

```text
staging.stg_<entity>
```

All inputs should have:

- Primary key (`parcel_id`, `road_id`)
- Single geometry column `geom`
- Valid, non-empty geometries
- Aligned CRS (or transform in SQL)

**`staging.stg_parcels`**

| parcel_id | owner_name | zoning_code | geom |
|-----------|------------|-------------|------|
| P-001 | Smith | R-1 | POLYGON(...) |

**`staging.stg_roads`**

| road_id | road_name | road_class | geom |
|---------|-----------|------------|------|
| R-100 | Main St | arterial | LINESTRING(...) |

**`staging.stg_boundary`**

| boundary_name | geom |
|---------------|------|
| Study Area | POLYGON(...) |

## Output Table Pattern

```text
curated.geo_<entity>[_<qualifier>]
```

**`curated.geo_parcels`** — one row per parcel in study area

| parcel_id | owner_name | zoning_code | boundary_name | area_sqm | perimeter_m | geom |
|-----------|------------|-------------|---------------|----------|-------------|------|
| P-001 | Smith | R-1 | Study Area | 4500.2 | 280.1 | POLYGON(...) |

**`curated.geo_roads_in_boundary`** — roads intersecting boundary

| road_id | road_name | road_class | road_length_m | geom |
|---------|-----------|------------|---------------|------|
| R-100 | Main St | arterial | 3200.5 | LINESTRING(...) |

Recommended metadata columns: `curated_at`, `source_layer`, `crs_name` (as attributes if needed).

## Validation Checks

```sql
-- Primary key uniqueness
SELECT parcel_id, COUNT(*) AS n
FROM curated.geo_parcels
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- All geometries valid and non-empty
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN geom IS NULL OR ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS bad_geom,
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM curated.geo_parcels;
```

```sql
-- Area reasonableness
SELECT
  MIN(area_sqm) AS min_area,
  APPROX_QUANTILE(area_sqm, 0.5) AS median_area,
  MAX(area_sqm) AS max_area
FROM curated.geo_parcels;
```

```sql
-- Staging vs curated row reconciliation
SELECT
  (SELECT COUNT(*) FROM staging.stg_parcels) AS stg_parcels,
  (SELECT COUNT(*) FROM curated.geo_parcels) AS geo_parcels;
```

```sql
-- Extent within boundary
SELECT ST_Extent(geom) AS parcels_extent FROM curated.geo_parcels;
SELECT ST_Extent(geom) AS boundary_extent FROM staging.stg_boundary;
```

```sql
-- Roads in boundary subset check
SELECT COUNT(*) AS roads_outside
FROM curated.geo_roads_in_boundary r
CROSS JOIN staging.stg_boundary b
WHERE NOT ST_Intersects(r.geom, b.geom);
```

## Common Variations

### Reproject curated output to WGS 84

```sql
ST_Transform(geom, 'EPSG:4326') AS geom
```

### Add derived acres from sq meters

```sql
area_sqm / 4046.86 AS area_acres
```

### Union staging steps into one notebook cell pipeline

```sql
WITH boundary AS (SELECT * FROM staging.stg_boundary),
     parcels AS (SELECT * FROM staging.stg_parcels),
     roads AS (SELECT * FROM staging.stg_roads),
     ...
SELECT ...;
```

### Version curated table with run id

```sql
CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT *, 'run_2026_06_25' AS pipeline_run_id FROM ...;
```

### Separate full-resolution and simplified tables

- `curated.geo_parcels` — analysis geometry
- `curated.geo_parcels_web` — simplified for GeoJSON export

## Performance Notes

- Build each curated table once; reuse across exports and reports.
- Chain transforms in CTEs for readability — DuckDB optimizes inline.
- Filter to boundary early to shrink join inputs.
- Compute `ST_Area` / `ST_Length` in projected CRS once; store as columns to avoid repeat calls.
- Materialize heavy overlays here rather than in every export notebook cell.

## Known Limitations

- Curated layer encodes business rules — document grain and filters for consumers.
- Combining clip + nearest + join in one table can blur single responsibility — split models when teams reuse parts independently.
- `ST_SimplifyPreserveTopology` in curated changes geometry — keep unsimplified table if legal area matters.
- Area in EPSG:3857 is approximate for large regions — use local state plane for cadastral work.
- Rebuilding curated without versioning overwrites prior results — use git for SQL logic, not table snapshots.

## Related Pages

- [Spatial join](spatial_join.md)
- [Clip / intersection](clip_intersection.md)
- [Nearest feature](nearest_feature.md)
- [Export-ready spatial layer](export_ready_spatial_layer.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [ST_Area](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_area) · [ST_Length](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_length) · [Spatial functions](https://duckdb.org/docs/current/core_extensions/spatial/functions.html)
