# Parquet Ingestion

Ingest Apache Parquet files into the `raw` layer. Parquet is the preferred columnar format for analytics: typed columns, compression, and fast scans in DuckDB.

## Purpose

Read single or multiple Parquet files (local, `data/raw/`, or remote) and register them as `raw_<dataset_name>` views or tables for staging and spatial workflows (including GeoParquet via the `spatial` extension).

## When to Use

- Source data is already Parquet (data lake exports, ETL outputs, GeoParquet)
- You need faster scans and smaller files than CSV
- Downstream steps require stable types without `TRY_CAST` noise
- Federating files from `data/raw/` after an external download step

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Format | Standard Parquet; GeoParquet may need `spatial` + `ST_Read` for geometry semantics |
| Schema | Embedded in file footer — verify it matches expectations |
| Layer | Parquet path is **source**; DuckDB object in schema `raw` |
| Naming | e.g. `raw.raw_events_parquet`, `raw.raw_boundaries_geoparquet` |
| Paths | List of files, glob, or single path — all valid |

## Basic DuckDB SQL

Explore without persisting:

```sql
SELECT *
FROM read_parquet('data/raw/events.parquet')
LIMIT 20;
```

Real-world online sample (DuckDB demo Parquet):

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT *
FROM read_parquet(
  'https://blobs.duckdb.org/data/lineitem.parquet'
)
LIMIT 10;
```

Projection pushdown — only read needed columns:

```sql
SELECT l_orderkey, l_extendedprice
FROM read_parquet('data/raw/lineitem.parquet')
WHERE l_orderkey < 1000;
```

## Create Raw View Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_events_parquet AS
SELECT *
FROM read_parquet('data/raw/events/*.parquet');
```

Remote practice view:

```sql
CREATE OR REPLACE VIEW raw.raw_lineitem_parquet AS
SELECT *
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
```

## Create Raw Table Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_customers_parquet AS
SELECT *
FROM read_parquet('data/raw/customers.parquet');
```

Snapshot online data for repeatable notebooks:

```sql
CREATE OR REPLACE TABLE raw.raw_lineitem_parquet AS
SELECT *
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
```

## Notebook Usage Example

```python
PARQUET_URL = "https://blobs.duckdb.org/data/lineitem.parquet"

con.execute("INSTALL httpfs; LOAD httpfs;")

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_lineitem_parquet AS
SELECT * FROM read_parquet('{PARQUET_URL}');
""")

summary = con.sql("""
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT l_orderkey) AS distinct_orders,
  SUM(l_extendedprice) AS total_extended_price
FROM raw.raw_lineitem_parquet
""").df()

summary
```

## Common Variations

### Multiple explicit files

```sql
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT *
FROM read_parquet([
  'data/raw/events_2024_01.parquet',
  'data/raw/events_2024_02.parquet'
]);
```

### Glob pattern

```sql
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT *, filename AS source_file
FROM read_parquet('data/raw/events/**/*.parquet', filename = true);
```

### Hive-partitioned layout

See [partitioned Parquet](partitioned_parquet.md):

```sql
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT *
FROM read_parquet('data/raw/events/**', hive_partitioning = true);
```

### GeoParquet (spatial)

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_boundaries_geoparquet AS
SELECT *
FROM ST_Read('data/raw/boundaries.parquet');
```

### Union file list from Python

```python
files = [p.as_posix() for p in RAW_DIR.glob("*.parquet")]
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT * FROM read_parquet({files!r});
""")
```

## Validation Checks After Ingestion

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_lineitem_parquet;

-- Schema
DESCRIBE raw.raw_lineitem_parquet;

-- Key uniqueness (adjust columns)
SELECT l_orderkey, l_linenumber, COUNT(*) AS n
FROM raw.raw_lineitem_parquet
GROUP BY 1, 2
HAVING COUNT(*) > 1;

-- Null check on critical fields
SELECT
  COUNT(*) AS total,
  COUNT(l_orderkey) AS non_null_orderkey
FROM raw.raw_lineitem_parquet;

-- Min/max for sanity
SELECT
  MIN(l_extendedprice) AS min_price,
  MAX(l_extendedprice) AS max_price
FROM raw.raw_lineitem_parquet;
```

For GeoParquet:

```sql
SELECT
  COUNT(*) AS n,
  COUNT(geom) AS with_geom,
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM raw.raw_boundaries_geoparquet;
```

## Performance Notes

- Parquet is columnar — `SELECT` few columns for much faster scans than `SELECT *` on wide files.
- DuckDB reads Parquet **in parallel** across row groups when possible.
- **Views** over Parquet avoid duplication; **tables** copy data into the DuckDB file — trade disk for speed and isolation.
- Remote Parquet over HTTP benefits from `httpfs`; for repeated runs, copy to `data/raw/` once.
- Prefer one row group size appropriate to your query patterns when you control export upstream.

## Known Limitations

- Schema evolution across files (new/dropped columns) can break globs — validate `DESCRIBE` per batch.
- GeoParquet may need `ST_Read` rather than plain `read_parquet` to materialize geometry correctly.
- Encrypted Parquet is not supported out of the box.
- Very small files in huge globs add metadata overhead — consider consolidating in `source` when possible.
- `raw` tables duplicate storage inside `work.duckdb` — monitor file size for multi-GB ingests.

## Related Pages

- [Partitioned Parquet](partitioned_parquet.md)
- [Folders and globs](folders_and_globs.md)
- [Remote files (HTTP / S3)](remote_files_http_s3.md)
- [Extensions](../01_setup/extensions.md) — `spatial` for GeoParquet

Official reference: [DuckDB Parquet](https://duckdb.org/docs/current/data/parquet/overview.html)
