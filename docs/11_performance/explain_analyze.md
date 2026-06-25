# EXPLAIN and EXPLAIN ANALYZE

Inspect and measure query plans before rewriting slow notebook cells.

## Purpose

Teach when to use `EXPLAIN` (plan only) vs `EXPLAIN ANALYZE` (plan + execution metrics) to verify predicate pushdown, column pruning, join order, and operator cost in DuckDB pipelines.

## Why it matters

Slow queries are often slow for invisible reasons: full-file CSV scans, missing filter pushdown, wide `SELECT *`, or a join that multiplies rows. `EXPLAIN` shows what DuckDB **plans** to do; `EXPLAIN ANALYZE` shows what actually happened — row counts per operator and cumulative time.

Use both when tuning `staging` builds, spatial joins, and repeated Parquet reads.

## Recommended pattern

1. Run `EXPLAIN` on a new heavy query before productionizing it in a notebook.
2. Confirm filters appear **inside** scan operators (`PARQUET_SCAN`, `READ_CSV`, `TABLE_SCAN`).
3. Run `EXPLAIN ANALYZE` on the final query to compare estimated vs actual cardinality (`EC` vs actual rows).
4. Rewrite one thing at a time — add a filter, narrow columns, materialize staging — and re-run `EXPLAIN ANALYZE`.
5. Compare before/after plans when converting CSV → Parquet or adding bounding-box filters.

## Anti-pattern

- Guessing at performance without reading the plan.
- Running `EXPLAIN ANALYZE` on `CREATE TABLE AS` for a 50 GB ingest during interactive exploration — it executes the full query.
- Optimizing sort order before confirming the scan is selective.
- Assuming runtime-generated join filters appear in plain `EXPLAIN` — they may only show in `EXPLAIN ANALYZE`.

## SQL example

### EXPLAIN — logical and physical plan (no execution)

```sql
INSTALL httpfs;
LOAD httpfs;

EXPLAIN
SELECT
  l_orderkey,
  l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
  AND l_extendedprice > 5000;
```

What to look for:

- `PARQUET_SCAN` with `Filters:` containing your `WHERE` predicates
- Only requested columns listed in the scan
- No redundant `FILTER` operator above an already-filtered scan

### EXPLAIN ANALYZE — plan plus runtime metrics

```sql
EXPLAIN ANALYZE
SELECT
  DATE_TRUNC('month', l_shipdate) AS ship_month,
  COUNT(*) AS line_count,
  SUM(l_extendedprice) AS revenue
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
GROUP BY 1
ORDER BY 1;
```

Interpretation tips:

- **EC** (estimated cardinality) vs actual row count — large gaps suggest stale statistics or hard-to-estimate filters.
- **Cumulative time** per operator — identify the expensive node (often `HASH_JOIN` or unfiltered scan).
- Parallel execution: total query time may be **less** than the sum of operator times.

### Compare bad vs good pattern

Unfiltered scan (anti-pattern):

```sql
EXPLAIN ANALYZE
SELECT l_orderkey, l_extendedprice
FROM (
  SELECT * FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
) sub
WHERE l_shipdate >= DATE '1996-01-01';
```

Filtered scan (recommended):

```sql
EXPLAIN ANALYZE
SELECT l_orderkey, l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01';
```

### EXPLAIN on spatial pre-filter

```sql
INSTALL spatial;
LOAD spatial;

EXPLAIN
SELECT region_name
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
WHERE ST_Intersects(
  geom,
  ST_MakeEnvelope(-122.52, 37.70, -122.35, 37.84)
);
```

## Notebook usage

```python
con.execute("INSTALL httpfs; LOAD httpfs;")

def show_plan(sql: str, analyze: bool = False) -> None:
    prefix = "EXPLAIN ANALYZE" if analyze else "EXPLAIN"
    display(con.sql(f"{prefix}\n{sql}").df())

# Plan only — safe for exploratory tuning
show_plan("""
SELECT l_orderkey, l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
""")

# Executes the query — use LIMIT or smaller filters while iterating
show_plan("""
SELECT COUNT(*), SUM(l_extendedprice)
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01'
""", analyze=True)
```

Profile a staging build:

```python
con.sql("""
EXPLAIN ANALYZE
CREATE OR REPLACE TABLE staging.stg_lineitem AS
SELECT
  l_orderkey,
  CAST(l_shipdate AS DATE) AS ship_date,
  l_extendedprice AS extended_price
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1996-01-01';
""").df()
```

## Common variations

### `EXPLAIN` formats

```sql
-- Default textual plan
EXPLAIN SELECT * FROM staging.stg_lineitem LIMIT 10;

-- JSON plan for programmatic parsing
PRAGMA explain_output = 'json';
EXPLAIN SELECT * FROM staging.stg_lineitem LIMIT 10;
```

### Join plan inspection

```sql
EXPLAIN ANALYZE
SELECT o.order_id, c.region, o.amount
FROM staging.stg_orders o
JOIN staging.stg_customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= DATE '2024-01-01';
```

### Verify CSV vs Parquet pushdown side by side

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv');

EXPLAIN ANALYZE
SELECT COUNT(*) FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
```

### Partition pruning check

```sql
EXPLAIN
SELECT *
FROM read_parquet('data/staging/events/**', hive_partitioning = true)
WHERE event_year = 2024;
```

## Practical notes

- **Start with `EXPLAIN`** when the query is expensive — it does not run the query.
- **Use `EXPLAIN ANALYZE` on representative filters** — not always full production scale while iterating.
- **Save plans** in notebook outputs when documenting a performance fix for your team.
- **Filter + column list first** — cheapest wins before rewriting joins.
- **Spatial:** compare plans with and without envelope pre-filter to confirm the optimizer reduces candidate pairs.

## Known limitations

- `EXPLAIN ANALYZE` executes the query — mutations and large scans have real cost.
- Runtime-generated filters (dynamic join pushdown) may not appear in static `EXPLAIN`.
- Estimated cardinalities can be wrong on complex spatial predicates — trust actual counts from `EXPLAIN ANALYZE`.
- Plan output format changes across DuckDB versions — re-baseline after upgrades.
- `EXPLAIN` on remote HTTP files still triggers metadata reads; cache effects can skew repeated `EXPLAIN ANALYZE` timings.

## Related Pages

- [Predicate pushdown](predicate_pushdown.md)
- [Column selection](column_selection.md)
- [Parquet best practices](parquet_best_practices.md)
- [Spatial performance](spatial_performance.md)

Official reference: [EXPLAIN](https://duckdb.org/docs/current/guides/meta/explain.html) · [EXPLAIN ANALYZE](https://duckdb.org/docs/current/guides/meta/explain_analyze.html)
