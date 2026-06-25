# GeoParquet Ingestion

Ingest GeoParquet files into the `raw` layer. GeoParquet stores geometry in Parquet with geospatial metadata — ideal for fast columnar scans and layered analytics pipelines.

## Purpose

Load road networks, parcels, buildings, and other vector layers in a analytics-friendly format with typed columns and compression, then promote through `staging` → `curated` → `output`.

## When to Use

- `source` is already GeoParquet (data lake, Overture, internal ETL)
- You need fast filters and aggregations on large spatial datasets
- You want stable types without Shapefile DBF limitations

Use `ST_Read` when you need proper `GEOMETRY` types. Use `read_parquet` for schema exploration or when geometry is stored as WKB columns you will parse in `staging`.

## Required DuckDB Extension

```sql
INSTALL spatial;
LOAD spatial;
```

For remote Parquet / GeoParquet:

```sql
INSTALL httpfs;
LOAD httpfs;
```

Plain `read_parquet` works without `spatial` but may not decode geometry into `GEOMETRY`.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Format | Parquet with GeoParquet metadata (`geo` key in schema metadata) |
| Geometry column | Often `geometry` or `geom` as WKB/BLOB in file — `ST_Read` maps to `GEOMETRY` |
| CRS | Embedded in GeoParquet metadata — verify with `ST_Read_Meta` |
| Naming | e.g. `raw.raw_roads_geoparquet` |
| Path | Single file, glob, or remote URL |

## Basic DuckDB SQL

Explore with the Parquet reader (required example path):

```sql
SELECT *
FROM read_parquet('data/raw/roads.geoparquet')
LIMIT 20;
```

Geometry-aware read with spatial extension:

```sql
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read('data/raw/roads.geoparquet')
LIMIT 20;
```

Real-world online sample (GeoParquet example from the [OGC GeoParquet repository](https://github.com/opengeospatial/geoparquet)):

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT *
FROM read_parquet(
  'https://raw.githubusercontent.com/opengeospatial/geoparquet/main/examples/example.parquet'
)
LIMIT 10;
```

For remote GeoParquet, `read_parquet` over `httpfs` is often more reliable than `ST_Read`. Use `ST_Read` for local files when you want GDAL-normalized column names.

## Create Raw Spatial Table Pattern

**Recommended** — geometry as `GEOMETRY`:

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_roads_geoparquet AS
SELECT *
FROM ST_Read('data/raw/roads.geoparquet');
```

**Alternative** — snapshot via `read_parquet` when you will handle WKB in `staging`:

```sql
CREATE OR REPLACE TABLE raw.raw_roads_geoparquet AS
SELECT *
FROM read_parquet('data/raw/roads.geoparquet');
```

If geometry is WKB in the Parquet column, promote in `staging`:

```sql
CREATE OR REPLACE TABLE staging.stg_roads AS
SELECT
  *,
  ST_GeomFromWKB(geometry) AS geom
FROM raw.raw_roads_geoparquet;
```

Adjust `geometry` to match `DESCRIBE` output.

## Geometry Column Notes

- `read_parquet` returns the on-disk column type (often `BLOB` / WKB) — not always native `GEOMETRY`.
- `ST_Read` is the default path for spatial ingest in this repository.
- Rename to `geom` in `staging` for consistency with other spatial tables.
- Check type after ingest:

```sql
SELECT typeof(geom) AS geom_type
FROM raw.raw_roads_geoparquet
LIMIT 1;
```

## CRS Notes

- GeoParquet metadata should declare EPSG code — confirm before spatial joins:

```sql
SELECT
  layers[1].geometry_fields[1].crs.auth_name AS auth,
  layers[1].geometry_fields[1].crs.auth_code AS code
FROM ST_Read_Meta('data/raw/roads.geoparquet');
```

- Mixed-CRS folders are a data quality issue — one CRS per `raw` table when possible.
- Reproject in `staging`: `ST_Transform(geom, 'EPSG:4326')`.

## Common Variations

### Multiple GeoParquet files

```sql
CREATE OR REPLACE TABLE raw.raw_roads_geoparquet AS
SELECT *, filename AS source_file
FROM read_parquet('data/raw/roads/**/*.geoparquet', filename := true);
```

Use `ST_Read` per file if `read_parquet` glob does not decode geometry.

### Hive-partitioned layout

```sql
CREATE OR REPLACE TABLE raw.raw_roads_geoparquet AS
SELECT *
FROM read_parquet('data/raw/roads/**', hive_partitioning := true);
```

### Column pruning (performance)

```sql
SELECT road_id, road_class
FROM read_parquet('data/raw/roads.geoparquet');
```

Add geometry only when needed:

```sql
SELECT road_id, geom
FROM ST_Read('data/raw/roads.geoparquet');
```

### Remote Overture / cloud GeoParquet

```sql
-- Example pattern — adjust release path and credentials
INSTALL httpfs;
LOAD httpfs;
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read('s3://overturemaps-us-west-2/release/2024-11-13.0/theme=transportation/type=segment/*')
LIMIT 100;
```

Mirror small extracts to `data/raw/` for offline practice.

### Notebook usage

```python
GEOPARQUET_PATH = (RAW_DIR / "roads.geoparquet").as_posix()

con.execute("INSTALL spatial; LOAD spatial;")

# Quick schema peek
con.sql(f"DESCRIBE SELECT * FROM read_parquet('{GEOPARQUET_PATH}')").df()

# Spatial raw table
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_roads_geoparquet AS
SELECT * FROM ST_Read('{GEOPARQUET_PATH}');
""")
```

## Validation Checks After Ingestion

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_roads_geoparquet;

-- Schema
DESCRIBE raw.raw_roads_geoparquet;

-- Geometry present (ST_Read path)
SELECT
  COUNT(*) AS total,
  COUNT(geom) AS with_geom
FROM raw.raw_roads_geoparquet;

-- Geometry types
SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM raw.raw_roads_geoparquet
GROUP BY 1;

-- Validity
SELECT
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM raw.raw_roads_geoparquet;

-- Extent
SELECT ST_Extent(geom) AS bbox FROM raw.raw_roads_geoparquet;
```

For `read_parquet`-only ingest, validate WKB converts:

```sql
SELECT COUNT(*) AS converted
FROM raw.raw_roads_geoparquet
WHERE ST_GeomFromWKB(geometry) IS NOT NULL;
```

## Known Limitations

- `read_parquet` alone may not produce `GEOMETRY` — spatial predicates need `ST_Read` or `ST_GeomFromWKB` in `staging`.
- GDAL-backed `ST_Read` on GeoParquet is not always as fast as native Parquet column pruning — profile wide tables.
- Schema evolution across partitioned folders can break globs — validate per partition.
- Very new GeoParquet versions may require updated DuckDB / spatial extension builds.
- Remote multi-file datasets need stable URLs and often S3 configuration.

## Related Pages

- [Spatial extension setup](spatial_extension_setup.md)
- [Layer inspection](layer_inspection.md)
- [Parquet ingestion](../02_ingestion/parquet.md)
- [Partitioned Parquet](../02_ingestion/partitioned_parquet.md)

Official reference: [GeoParquet](https://geoparquet.org/) · [ST_Read](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
