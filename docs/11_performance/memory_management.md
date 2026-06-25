# Memory Management

Configure DuckDB memory and spill settings so local notebooks and CI pipelines finish reliably on large files.

## Purpose

Help mixed audiences — analysts, data engineers, GIS users — set `memory_limit`, `threads`, and `temp_directory` and choose when to materialize tables vs use views to avoid out-of-memory failures.

## Why it matters

DuckDB is an in-process analytics engine. A single wide `SELECT *` join across two large tables can exceed available RAM. Without limits, the OS may kill your kernel; with proper settings, DuckDB spills to disk and completes — slower, but successfully.

Spatial overlays and unfiltered spatial joins are common memory hotspots in this repository's workflows.

## Recommended pattern

1. Set `memory_limit` to a fraction of available RAM (e.g., 50–75% on a dedicated laptop).
2. Point `temp_directory` at fast local SSD space for spill files.
3. Set `threads` to physical cores for CPU-bound work; lower when memory is tight.
4. Materialize selective `staging` tables after filter + column prune — not full Cartesian intermediates.
5. Use Parquet staging files so re-runs do not re-parse CSV (see [parquet best practices](parquet_best_practices.md)).
6. Profile heavy cells with `EXPLAIN ANALYZE` (see [explain analyze](explain_analyze.md)).

```python
con.execute("SET memory_limit = '4GB';")
con.execute("SET threads = 4;")
con.execute("SET temp_directory = '/tmp/duckdb_spill';")
```

## Anti-pattern

```sql
-- Cross join two large spatial layers with no pre-filter
SELECT *
FROM staging.stg_parcels p
CROSS JOIN staging.stg_roads r;

-- Materialize every intermediate as a wide table inside work.duckdb
CREATE TABLE staging.stg_huge AS SELECT * FROM raw.raw_wide_csv;
CREATE TABLE staging.stg_huger AS SELECT * FROM staging.stg_huge, staging.stg_other;

-- Unlimited memory on a 8 GB laptop running spatial joins
-- (no SET memory_limit; no temp_directory)
```

## SQL example

Session settings before a large ingest:

```sql
SET memory_limit = '6GB';
SET threads = 8;
SET temp_directory = 'data/.duckdb_temp';

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_lineitem_csv AS
SELECT *
FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv');
```

Materialize a **narrow, filtered** staging table instead of keeping everything in memory:

```sql
CREATE OR REPLACE TABLE staging.stg_lineitem AS
SELECT
  l_orderkey,
  CAST(l_shipdate AS DATE) AS ship_date,
  l_extendedprice AS extended_price
FROM raw.raw_lineitem_csv
WHERE l_shipdate >= DATE '1995-01-01';
```

View for exploration (no extra copy inside `.duckdb`):

```sql
CREATE OR REPLACE VIEW staging.vw_lineitem_recent AS
SELECT l_orderkey, ship_date, extended_price
FROM staging.stg_lineitem
WHERE ship_date >= DATE '1996-01-01';
```

Check current settings:

```sql
SELECT name, value
FROM duckdb_settings()
WHERE name IN ('memory_limit', 'threads', 'temp_directory');
```

## Notebook usage

```python
from pathlib import Path

TEMP_DIR = ROOT / "data" / ".duckdb_temp"
TEMP_DIR.mkdir(parents=True, exist_ok=True)

con.execute("SET memory_limit = '4GB';")
con.execute(f"SET temp_directory = '{TEMP_DIR.as_posix()}';")
con.execute("SET threads = 4;")

con.execute("INSTALL httpfs; LOAD httpfs;")

# Large read with early filter + column prune
con.execute("""
CREATE OR REPLACE TABLE staging.stg_lineitem AS
SELECT
  l_orderkey,
  CAST(l_shipdate AS DATE) AS ship_date,
  l_extendedprice AS extended_price
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01';
""")

# Lightweight repeated access via view
con.execute("""
CREATE OR REPLACE VIEW staging.vw_lineitem_1996 AS
SELECT * FROM staging.stg_lineitem WHERE ship_date < DATE '1997-01-01';
""")

con.sql("SELECT COUNT(*), SUM(extended_price) FROM staging.vw_lineitem_1996").df()
```

## Common variations

### In-memory sandbox with explicit cap

```python
con = duckdb.connect()
con.execute("SET memory_limit = '2GB';")
```

### Read-only attach for large shared database

```python
con = duckdb.connect(str(DB_PATH), read_only=True)
con.execute("SET memory_limit = '8GB';")
```

### Export to Parquet to free in-DB space

```sql
COPY staging.stg_lineitem TO 'data/staging/stg_lineitem.parquet' (FORMAT PARQUET);
DROP TABLE staging.stg_lineitem;

CREATE VIEW staging.stg_lineitem AS
SELECT * FROM read_parquet('data/staging/stg_lineitem.parquet');
```

### Spatial: reduce vertices before heavy ops

```sql
CREATE TABLE staging.stg_boundary_simple AS
SELECT region_name, ST_SimplifyPreserveTopology(geom, 100) AS geom
FROM staging.stg_boundary;
```

### Monitor with `EXPLAIN ANALYZE`

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM staging.stg_lineitem l
JOIN staging.stg_orders o ON l.l_orderkey = o.order_id;
```

## Practical notes

- **Materialize vs view:** Materialize when downstream cells read the same filtered subset many times; use views when the query is cheap or the source is already Parquet on disk.
- **Disk spill:** `temp_directory` must have free space — often 2–3× the size of the largest intermediate for worst-case joins.
- **CI runners:** Set conservative `memory_limit` and `threads` in GitHub Actions (often 2–4 GB, 2 threads).
- **Kernel restarts:** Re-apply settings in the notebook setup cell after every restart.
- **File-backed DB growth:** `raw` and `staging` tables inside `work.duckdb` grow the file — export to `data/staging/*.parquet` and `DROP` when appropriate.

## Known limitations

- Spilling to disk is slower than in-memory execution — prefer filter + column prune first.
- `memory_limit` does not cap Python DataFrame memory from `.df()` — large result sets still load into pandas.
- Spatial joins without pre-filtering can spill heavily or fail even with disk spill.
- Network-mounted `temp_directory` (some corporate drives) can make spill painfully slow.
- Settings are per-connection — multiple `duckdb.connect()` handles need separate configuration.

## Related Pages

- [Large file patterns](large_file_patterns.md)
- [Column selection](column_selection.md)
- [Spatial performance](spatial_performance.md)
- [Notebook setup cell](../01_setup/notebook_setup_cell.md)

Official reference: [DuckDB configuration](https://duckdb.org/docs/current/configuration/overview.html)
