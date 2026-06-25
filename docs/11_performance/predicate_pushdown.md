# Predicate Pushdown

Apply filters as early as possible so DuckDB reads less data from Parquet, CSV, and remote files.

## Purpose

Show how filter pushdown and row-group pruning reduce I/O in notebook pipelines, especially when querying Parquet and partitioned datasets before joins and aggregates.

## Why it matters

A filter on `ship_date` or `region` that runs **after** a full table scan forces DuckDB to read every row and column first. When predicates are pushed into the scan operator, DuckDB can skip row groups, files, or partitions whose min/max statistics prove they cannot match.

For repeated analytics on large files, **filtering early** often matters more than micro-optimizing SQL style downstream.

## Recommended pattern

1. Put selective `WHERE` clauses on the same query that reads the file — not in an outer wrapper on a `SELECT *` subquery.
2. Filter on native column types (`DATE`, `INTEGER`) — avoid wrapping columns in functions when possible.
3. Combine partition keys in `WHERE` when reading hive-partitioned Parquet.
4. Verify pushdown with `EXPLAIN` — look for filters inside `PARQUET_SCAN` or `READ_CSV` operators.
5. In spatial workflows, apply bounding-box filters before expensive `ST_Intersects` geometry tests (see [spatial performance](spatial_performance.md)).

```text
read file WITH filter  →  clean  →  join  →  aggregate
        ↑ pushdown happens here
```

## Anti-pattern

```sql
-- Reads all columns and rows, then filters
SELECT *
FROM (
  SELECT * FROM read_parquet('data/staging/stg_lineitem.parquet')
) sub
WHERE ship_date >= DATE '1996-01-01';

-- Function on column blocks row-group pruning
SELECT *
FROM read_parquet('data/staging/stg_lineitem.parquet')
WHERE YEAR(ship_date) = 1996;

-- OR-of-many-values may scan more than IN-list (check EXPLAIN for your version)
SELECT *
FROM read_parquet('data/staging/stg_lineitem.parquet')
WHERE region = 'A' OR region = 'B' OR region = 'C';  -- prefer IN (...)
```

## SQL example

Filter at read time on online Parquet:

```sql
INSTALL httpfs;
LOAD httpfs;

-- Filter pushed into Parquet scan
SELECT
  l_orderkey,
  l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
  AND l_shipdate < DATE '1997-01-01'
  AND l_extendedprice > 5000;
```

Verify pushdown with `EXPLAIN`:

```sql
EXPLAIN
SELECT l_orderkey, l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
  AND l_extendedprice > 5000;
```

Look for `Filters:` inside the `PARQUET_SCAN` operator. A separate `FILTER` node above an unfiltered scan means pushdown did not apply.

Measure actual rows read with `EXPLAIN ANALYZE`:

```sql
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(l_extendedprice)
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01';
```

Filter before join (staging layer):

```sql
CREATE OR REPLACE TABLE staging.stg_lineitem_1996 AS
SELECT l_orderkey, l_extendedprice, l_shipdate
FROM read_parquet('data/staging/stg_lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
  AND l_shipdate < DATE '1997-01-01';

SELECT COUNT(*) AS order_lines, SUM(l_extendedprice) AS revenue
FROM staging.stg_lineitem_1996;
```

## Notebook usage

```python
con.execute("INSTALL httpfs; LOAD httpfs;")

# Filter early at ingest to staging (raw → staging with predicate)
con.execute("""
CREATE OR REPLACE TABLE staging.stg_population_recent AS
SELECT
  country_name,
  CAST(year AS INTEGER) AS year,
  CAST(value AS DOUBLE) AS population
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
)
WHERE TRY_CAST(year AS INTEGER) >= 2000
  AND value IS NOT NULL;
""")

# Confirm selective read
plan = con.sql("""
EXPLAIN
SELECT country_name, population
FROM staging.stg_population_recent
WHERE year = 2020
""").df()
plan
```

## Common variations

### Partition pruning on hive layout

```sql
SELECT *
FROM read_parquet('data/staging/events/**', hive_partitioning = true)
WHERE event_year = 2024 AND event_month = 6;
```

### Pushdown-friendly `IN` list

```sql
SELECT l_orderkey, l_extendedprice
FROM read_parquet('data/staging/stg_lineitem.parquet')
WHERE l_orderkey IN (1, 2, 3, 4, 5);
```

### Filter on remote CSV (limited pushdown vs Parquet)

```sql
SELECT country_name, year, value
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
)
WHERE year = '2020';
```

CSV pushdown is more limited than Parquet — prefer staging Parquet for repeated filtered queries.

### Dynamic filters from subqueries

DuckDB can push runtime-generated filters into multi-file Parquet lists (e.g., `WHERE date = (SELECT MAX(d) FROM dim_dates)`). Use `EXPLAIN ANALYZE` to confirm; static `EXPLAIN` may not show runtime filters.

## Practical notes

- **Selectivity wins:** Pushdown helps most when the filter removes a large fraction of rows.
- **Type stability:** Cast once in `staging`, then filter on typed columns — cleaner plans than repeated `TRY_CAST` in every query.
- **Join order:** DuckDB's optimizer may push join predicates back to scans; still write filters on base tables explicitly for readability.
- **Compare plans:** Run `EXPLAIN` before and after a rewrite when tuning a slow notebook cell.
- **Spatial:** Envelope and `spatial_filter_box` filters are the spatial equivalent of predicate pushdown — apply them before heavy predicates.

## Known limitations

- Filters that wrap columns (`YEAR(col)`, `UPPER(col)`) may prevent row-group pruning even if expression pushdown is supported.
- Complex `OR` conditions may scan more data than equivalent `IN` lists — verify with `EXPLAIN ANALYZE`.
- CSV and JSON readers have weaker pushdown than Parquet.
- Runtime-generated filters may not appear in plain `EXPLAIN` output — use `EXPLAIN ANALYZE`.
- Partition pruning depends on consistent hive directory naming and partition column types.

## Related Pages

- [Parquet best practices](parquet_best_practices.md)
- [Column selection](column_selection.md)
- [EXPLAIN and EXPLAIN ANALYZE](explain_analyze.md)
- [Spatial performance](spatial_performance.md)

Official reference: [DuckDB EXPLAIN](https://duckdb.org/docs/current/guides/meta/explain.html)
