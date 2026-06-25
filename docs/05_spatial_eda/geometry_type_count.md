# Geometry Type Count

Count features by geometry type (`POINT`, `LINESTRING`, `POLYGON`, etc.) to confirm layer homogeneity before `staging` rules and spatial joins.

## Purpose

Summarize how many rows exist per `ST_GeometryType` so you can detect mixed collections, unexpected multiparts, or ingest mistakes early in the **source → raw** validation step.

## When to Use

- Immediately after loading `raw.raw_parcels`, `raw.raw_roads`, or `raw.raw_boundary`
- Before applying polygon-only or line-only logic in `staging`
- When a vendor file claims one geometry type but delivers another
- Regression check after re-ingest or driver upgrade

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

Single table — geometry type distribution:

```sql
SELECT
  ST_GeometryType(geom) AS geom_type,
  COUNT(*) AS feature_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM raw.raw_parcels
WHERE geom IS NOT NULL
GROUP BY 1
ORDER BY feature_count DESC;
```

Compare types across related layers:

```sql
SELECT 'parcels' AS layer, ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM raw.raw_parcels
WHERE geom IS NOT NULL
GROUP BY 1
UNION ALL
SELECT 'roads', ST_GeometryType(geom), COUNT(*)
FROM raw.raw_roads
WHERE geom IS NOT NULL
GROUP BY 1
UNION ALL
SELECT 'boundary', ST_GeometryType(geom), COUNT(*)
FROM raw.raw_boundary
WHERE geom IS NOT NULL
GROUP BY 1
ORDER BY layer, n DESC;
```

Flag rows that are not the expected type (example: parcels should be polygons):

```sql
SELECT
  parcel_id,
  ST_GeometryType(geom) AS geom_type
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND ST_GeometryType(geom) NOT IN ('POLYGON', 'MULTIPOLYGON')
LIMIT 50;
```

## Notebook Usage

```python
# After ingest into raw schema
display(con.sql("""
  SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
  FROM raw.raw_parcels
  WHERE geom IS NOT NULL
  GROUP BY 1
  ORDER BY n DESC
""").df())

# Multi-layer report
layers = ["raw_parcels", "raw_roads", "raw_boundary"]
for table in layers:
    print(f"--- {table} ---")
    display(con.sql(f"""
      SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
      FROM raw.{table}
      WHERE geom IS NOT NULL
      GROUP BY 1
    """).df())
```

Practice with online GeoJSON (load once, then profile):

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_boundary AS
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.sql("""
  SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
  FROM raw.raw_boundary
  GROUP BY 1
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_parcels` | Target spatial table |
| `geom` | `geom` | Primary geometry column |
| Expected types | `'POLYGON'`, `'MULTIPOLYGON'` | Layer-specific allowlist |
| ID column | `parcel_id`, `road_id` | For outlier listing |

## Expected Output

| geom_type | feature_count | pct_of_total |
|-----------|---------------|--------------|
| POLYGON | 12450 | 99.8 |
| MULTIPOLYGON | 25 | 0.2 |

- **Parcels / boundary:** typically `POLYGON` or `MULTIPOLYGON`
- **Roads:** typically `LINESTRING` or `MULTILINESTRING`
- **Points of interest:** `POINT` or `MULTIPOINT`

One row per distinct geometry type; percentages should sum to ~100% among non-null geometries.

## Interpretation Guidance

- **Single dominant type** — expected for well-formed GIS layers; safe to proceed to validity and CRS checks.
- **Mixed types in one table** — common in GeoJSON FeatureCollections; split or filter in `staging` if downstream tools need homogeneous geometry.
- **`GEOMETRYCOLLECTION`** — often a data-quality issue for parcels; inspect source or explode in `staging`.
- **Type differs from metadata** — compare to [layer inspection](../03_spatial_ingestion/layer_inspection.md) `ST_Read_Meta` report; re-ingest with correct layer name.
- **NULL geometries excluded** — run [null geometry check](null_geometry_check.md) if counts do not match source feature count.

## Common Variations

### Include empty geometries in the count

```sql
SELECT
  CASE
    WHEN geom IS NULL THEN 'NULL'
    WHEN ST_IsEmpty(geom) THEN 'EMPTY'
    ELSE ST_GeometryType(geom)
  END AS geom_bucket,
  COUNT(*) AS n
FROM raw.raw_parcels
GROUP BY 1;
```

### Geometry type by category attribute

```sql
SELECT
  zoning_code,
  ST_GeometryType(geom) AS geom_type,
  COUNT(*) AS n
FROM raw.raw_parcels
GROUP BY 1, 2
ORDER BY 1, n DESC;
```

### Staging table after `ST_MakeValid`

```sql
SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM staging.stg_parcels
GROUP BY 1;
```

Compare raw vs staging to confirm repairs did not change types unexpectedly.

## Known Limitations

- `ST_GeometryType` returns uppercase OGC names (`POLYGON`, not `Polygon`).
- Curved or exotic subtypes may appear as generic types depending on DuckDB/GDAL version.
- Geometry collections report as `GEOMETRYCOLLECTION` — use `ST_Dump` in `staging` to inspect constituents (not covered here).
- Very large tables: aggregate query is full scan — acceptable for EDA; cache results in a notebook cell output.

## Related Pages

- [Null geometry check](null_geometry_check.md)
- [Invalid geometry check](invalid_geometry_check.md)
- [Layer inspection](../03_spatial_ingestion/layer_inspection.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [ST_GeometryType](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_geometrytype)
