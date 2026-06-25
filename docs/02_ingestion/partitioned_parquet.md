# Partitioned Parquet

Ingest Hive-style partitioned Parquet datasets where directory names encode columns such as `year=2024/month=06/`. DuckDB can expose partition keys as regular columns during read.

## Purpose

Load data lake layouts into `raw` without manually unioning each partition folder, preserving partition columns for filtering in `staging` and `curated`.

## When to Use

- `source` delivers Parquet under `key=value/` directory paths
- You filter heavily by date or region and want partition pruning
- Practicing lakehouse-style layouts before warehouse export
- Combining curated `output` Parquet partitions back into DuckDB

Use simple [folders and globs](folders_and_globs.md) when paths do not encode partition columns.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Layout | Hive-style: `.../year=2024/month=06/part-000.parquet` |
| Format | Parquet files inside partition directories |
| Consistency | Data files share schema; partition dirs may vary in cardinality |
| Flag | `hive_partitioning = true` on `read_parquet` |
| Naming | `raw_<topic>_parquet` — e.g. `raw.raw_events_parquet` |

Example on-disk layout under `data/raw/`:

```text
data/raw/events/
  year=2023/month=12/data.parquet
  year=2024/month=01/data.parquet
  year=2024/month=02/data.parquet
```

## Basic DuckDB SQL

```sql
SELECT year, month, COUNT(*) AS n
FROM read_parquet('data/raw/events/**', hive_partitioning = true)
GROUP BY year, month
ORDER BY year, month;
```

Filter with partition pruning:

```sql
SELECT *
FROM read_parquet('data/raw/events/**', hive_partitioning = true)
WHERE year = 2024 AND month >= 6
LIMIT 100;
```

Practice with a public partitioned dataset (adjust URL to your mirror):

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT *
FROM read_parquet(
  's3://duckdb-blobs/data/hive_partitioning/**',
  hive_partitioning = true
)
LIMIT 10;
```

## Create Raw View Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_events_parquet AS
SELECT *
FROM read_parquet('data/raw/events/**', hive_partitioning = true);
```

## Create Raw Table Pattern

```sql
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT *
FROM read_parquet('data/raw/events/**', hive_partitioning = true);
```

Snapshot specific partitions only:

```sql
CREATE OR REPLACE TABLE raw.raw_events_2024_parquet AS
SELECT *
FROM read_parquet('data/raw/events/year=2024/**', hive_partitioning = true);
```

## Notebook Usage Example

Create a small local partitioned dataset for practice, then ingest:

```python
import duckdb

# Use a fresh in-memory connection to write sample partitions
writer = duckdb.connect()
writer.execute("""
COPY (SELECT 1 AS id, 'a' AS category, DATE '2024-01-15' AS event_date)
TO 'data/raw/events/year=2024/month=01'
(FORMAT PARQUET, PARTITION_BY (year, month), OVERWRITE_OR_IGNORE);
""")
writer.execute("""
COPY (SELECT 2 AS id, 'b' AS category, DATE '2024-02-10' AS event_date)
TO 'data/raw/events/year=2024/month=02'
(FORMAT PARQUET, PARTITION_BY (year, month), OVERWRITE_OR_IGNORE);
""")
writer.close()

events_glob = (RAW_DIR / "events" / "**").as_posix()
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT * FROM read_parquet('{events_glob}', hive_partitioning = true);
""")

con.sql("""
SELECT year, month, COUNT(*) AS n
FROM raw.raw_events_parquet
GROUP BY year, month
ORDER BY year, month
""").df()
```

## Common Variations

### `union_by_name` when columns differ slightly across partitions

```sql
SELECT *
FROM read_parquet(
  'data/raw/events/**',
  hive_partitioning = true,
  union_by_name = true
);
```

### Partition columns as VARCHAR vs INT

Cast in `staging` if directory values arrive as strings:

```sql
CREATE OR REPLACE TABLE staging.stg_events AS
SELECT
  CAST(year AS INTEGER) AS year,
  CAST(month AS INTEGER) AS month,
  id,
  category,
  event_date
FROM raw.raw_events_parquet;
```

### Read only selected data columns + partitions

```sql
SELECT year, month, id, amount
FROM read_parquet('data/raw/events/**', hive_partitioning = true);
```

### Export curated results as partitioned Parquet (`output` layer)

```sql
COPY (
  SELECT * FROM curated.cur_events_by_month
) TO 'data/output/events'
(FORMAT PARQUET, PARTITION_BY (year, month), OVERWRITE_OR_IGNORE);
```

### GeoParquet partitions

Same hive flag; use `ST_Read` when geometry columns need spatial types:

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_parcels_geoparquet AS
SELECT *
FROM ST_Read('data/raw/parcels/**', hive_partitioning = true);
```

## Validation Checks After Ingestion

```sql
-- Partition coverage
SELECT year, month, COUNT(*) AS row_count
FROM raw.raw_events_parquet
GROUP BY year, month
ORDER BY year, month;

-- Unexpected null partition keys
SELECT COUNT(*) AS missing_year
FROM raw.raw_events_parquet
WHERE year IS NULL;

-- Compare to directory listing (manual spot check)
SELECT DISTINCT year, month FROM raw.raw_events_parquet;

-- Row totals
SELECT COUNT(*) AS total FROM raw.raw_events_parquet;

-- Duplicate business keys across partitions
SELECT id, COUNT(*) AS n
FROM raw.raw_events_parquet
GROUP BY id
HAVING COUNT(*) > 1;
```

## Performance Notes

- **Partition pruning** applies when filters use partition columns — query `WHERE year = 2024` skips other years.
- Prefer partition columns that match common filters (date, region) — not high-cardinality IDs.
- Many small Parquet files per partition hurt performance — target reasonable file sizes upstream (128MB–1GB is a common range).
- Materializing all partitions into one `raw` table loses pruning on the DuckDB copy — keep a **view** over files for very large lakes; use **tables** for manageable practice sets.
- `hive_partitioning = true` has overhead on tiny demos — negligible at real scale.

## Known Limitations

- Only directory `key=value` hive layouts are inferred — other conventions need manual path parsing in `staging`.
- Partition column types follow directory strings — cast explicitly.
- Hidden or non-standard path segments may not parse as expected — validate distinct partition values.
- Deleting partition folders on disk does not update materialized `raw` tables — re-ingest after `source` changes.
- Mixed file formats under the same tree are not supported in one read.

## Related Pages

- [Parquet ingestion](parquet.md)
- [Folders and globs](folders_and_globs.md)
- [Remote files (HTTP / S3)](remote_files_http_s3.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB hive partitioning](https://duckdb.org/docs/current/data/parquet/overview.html)
