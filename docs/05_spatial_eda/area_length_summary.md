# Area / Length Summary

Summarize polygon area and line length distributions to validate units, spot extreme features, and support zoning or network screening before `curated` models.

## Purpose

Compute `ST_Area` for polygons (`raw.raw_parcels`, `raw.raw_boundary`) and `ST_Length` for lines (`raw.raw_roads`) with basic statistics so you can confirm measures are in expected units after CRS review.

## When to Use

- After [CRS check](crs_check.md) — area/length units follow the CRS (degrees² vs meters)
- After [invalid geometry check](invalid_geometry_check.md) — invalid polygons may return NULL area
- When parcel sizes or road lengths look wrong in preview maps
- Baseline before aggregating to `curated` rollups (acreage by zone, road miles by class)

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

### Polygon area summary (parcels)

```sql
SELECT
  COUNT(*) AS polygon_count,
  MIN(ST_Area(geom)) AS min_area,
  MAX(ST_Area(geom)) AS max_area,
  AVG(ST_Area(geom)) AS avg_area,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ST_Area(geom)) AS median_area,
  SUM(ST_Area(geom)) AS total_area
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom)
  AND ST_GeometryType(geom) IN ('POLYGON', 'MULTIPOLYGON');
```

### Line length summary (roads)

```sql
SELECT
  COUNT(*) AS line_count,
  MIN(ST_Length(geom)) AS min_length,
  MAX(ST_Length(geom)) AS max_length,
  AVG(ST_Length(geom)) AS avg_length,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ST_Length(geom)) AS median_length,
  SUM(ST_Length(geom)) AS total_length
FROM raw.raw_roads
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom)
  AND ST_GeometryType(geom) IN ('LINESTRING', 'MULTILINESTRING');
```

### Area by category

```sql
SELECT
  zoning_code,
  COUNT(*) AS n,
  AVG(ST_Area(geom)) AS avg_area,
  SUM(ST_Area(geom)) AS total_area
FROM raw.raw_parcels
WHERE geom IS NOT NULL
GROUP BY zoning_code
ORDER BY total_area DESC;
```

### Top outliers (largest parcels)

```sql
SELECT
  parcel_id,
  ST_Area(geom) AS area,
  ST_GeometryType(geom) AS geom_type
FROM raw.raw_parcels
WHERE geom IS NOT NULL
ORDER BY ST_Area(geom) DESC
LIMIT 25;
```

### Measure in a projected CRS (meters)

```sql
SELECT
  AVG(ST_Area(ST_Transform(geom, 'EPSG:3857'))) AS avg_area_m2,
  SUM(ST_Length(ST_Transform(geom, 'EPSG:3857'))) AS total_length_m
FROM raw.raw_parcels
WHERE geom IS NOT NULL;
```

Use separate queries per geometry type when mixing tables; example above is parcels-only.

## Notebook Usage

```python
area_stats = con.sql("""
  SELECT
    MIN(ST_Area(geom)) AS min_area,
    AVG(ST_Area(geom)) AS avg_area,
    MAX(ST_Area(geom)) AS max_area,
    SUM(ST_Area(geom)) AS total_area
  FROM raw.raw_parcels
  WHERE geom IS NOT NULL
""").df()
area_stats
```

```python
length_stats = con.sql("""
  SELECT
    MIN(ST_Length(geom)) AS min_length,
    AVG(ST_Length(geom)) AS avg_length,
    MAX(ST_Length(geom)) AS max_length,
    SUM(ST_Length(geom)) AS total_length
  FROM raw.raw_roads
  WHERE geom IS NOT NULL
""").df()
length_stats
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
  SELECT ST_Area(geom) AS area FROM raw.raw_boundary LIMIT 5
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_parcels` | Polygon vs line table |
| `geom` | `geom` | Geometry column |
| Category column | `zoning_code`, `road_class` | Grouped summaries |
| Target CRS | `'EPSG:3857'` | Meter-based measures |
| Unit conversion | `/ 4046.86` | m² → acres (after projected area) |

## Expected Output

**Parcels:**

| polygon_count | min_area | max_area | avg_area | median_area | total_area |
|---------------|----------|----------|----------|-------------|------------|
| 12450 | 42.3 | 985000.1 | 3201.5 | 2100.0 | 39858675.0 |

**Roads:**

| line_count | min_length | max_length | avg_length | median_length | total_length |
|------------|------------|------------|------------|---------------|--------------|
| 8420 | 1.2 | 18432.0 | 412.8 | 280.5 | 3475764.0 |

Units depend on CRS: **square meters / meters** for projected CRS; **degrees² / degrees** for geographic (misleading for reporting — reproject first).

## Interpretation Guidance

- **Reproject before reporting acreage or miles** — use a local projected CRS or `EPSG:3857` for rough web maps; geographic `ST_Area` is not acreage.
- **Max area far above median** — campuses, airports, or bad geometry; cross-check [invalid geometry check](invalid_geometry_check.md) and outlier IDs.
- **Zero or NULL area** — empty or invalid polygons; see [null geometry check](null_geometry_check.md).
- **Total length vs known network** — order-of-magnitude sanity vs vendor docs; large gaps suggest clipped ingest.
- **Sum of parcel areas &gt; boundary area** — overlaps, duplicate parcels, or different CRS between layers.

## Common Variations

### Acres from projected area

```sql
SELECT
  parcel_id,
  ST_Area(ST_Transform(geom, 'EPSG:2227')) / 4046.8564224 AS area_acres
FROM raw.raw_parcels
WHERE geom IS NOT NULL
LIMIT 10;
```

Replace `EPSG:2227` with your local state plane code from [CRS check](crs_check.md).

### Length by road class

```sql
SELECT
  road_class,
  COUNT(*) AS n,
  SUM(ST_Length(ST_Transform(geom, 'EPSG:3857'))) / 1609.344 AS length_miles
FROM raw.raw_roads
WHERE geom IS NOT NULL
GROUP BY road_class
ORDER BY length_miles DESC;
```

### Boundary area (single polygon)

```sql
SELECT ST_Area(ST_Transform(geom, 'EPSG:3857')) / 1e6 AS area_km2
FROM raw.raw_boundary
WHERE geom IS NOT NULL;
```

### Staging with precomputed measures

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT
  parcel_id,
  zoning_code,
  ST_Transform(geom, 'EPSG:2227') AS geom,
  ST_Area(ST_Transform(geom, 'EPSG:2227')) AS area_m2
FROM raw.raw_parcels
WHERE geom IS NOT NULL AND ST_IsValid(geom);
```

## Known Limitations

- `ST_Area` / `ST_Length` on geographic CRS use planar math on degrees — not geodesic; reproject for reporting.
- Invalid geometries may yield NULL — repair in `staging` first.
- Multipolygon area is total of parts; holes are subtracted when geometry is valid.
- Very large tables: aggregate queries scan all geometries — cache results in validation notebooks.
- 3D geometries (Z values) — behavior depends on extension version; treat as 2D for EDA unless documented otherwise.

## Related Pages

- [CRS check](crs_check.md)
- [Invalid geometry check](invalid_geometry_check.md)
- [Numeric summary](../04_eda/numeric_summary.md)

Official reference: [ST_Area](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_area) · [ST_Length](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_length)
