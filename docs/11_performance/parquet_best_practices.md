# Parquet Best Practices

Choose Parquet over CSV for repeated analytics, and write typed staging files that downstream notebooks can scan efficiently.

## Purpose

Document when and how to use Apache Parquet in the `source → raw → staging → curated → output` workflow so analysts, engineers, and GIS users get faster scans, smaller files, and stable types.

## Why it matters

CSV is easy to exchange but expensive to re-parse. Every notebook cell that re-reads a wide CSV repeats text parsing, type inference, and decompression work. Parquet stores typed columns with compression and row-group statistics, so DuckDB can skip data it does not need.

For pipelines you run more than once, converting `raw` CSV snapshots to `staging` Parquet is usually the highest-impact performance step after filtering and column selection.

## Recommended pattern

1. Ingest `source` CSV once into `raw` for auditability.
2. Clean and type in `staging`, then **materialize Parquet** under `data/staging/` or as a `staging.stg_*` table backed by Parquet.
3. Point repeated analytics, joins, and exports at Parquet — not the original CSV.
4. Project only the columns you need at read time.
5. Use ZSTD compression when you control export settings.

```text
source (CSV URL) → raw.raw_* (table) → staging.stg_* (Parquet file) → curated → output
```

## Anti-pattern

- Keeping a 5 GB CSV as the only copy and running `read_csv_auto` in every notebook cell.
- Writing `SELECT *` to Parquet when downstream models use five columns.
- Mixing schema versions across Parquet files in one glob without validation.
- Skipping `raw` and reading directly from `source` with no snapshot — fast but not auditable.

## SQL example

Ingest online CSV to `raw`, convert to staging Parquet, then query only needed columns:

```sql
INSTALL httpfs;
LOAD httpfs;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;

-- source → raw (one-time snapshot)
CREATE OR REPLACE TABLE raw.raw_lineitem_csv AS
SELECT *
FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv');

-- raw → staging Parquet (typed, compressed, reusable)
COPY (
  SELECT
    l_orderkey,
    l_linenumber,
    CAST(l_shipdate AS DATE) AS ship_date,
    l_extendedprice AS extended_price,
    l_quantity AS quantity
  FROM raw.raw_lineitem_csv
  WHERE l_shipdate IS NOT NULL
) TO 'data/staging/stg_lineitem.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

-- Repeated analytics: read staging Parquet, not CSV
SELECT
  DATE_TRUNC('month', ship_date) AS ship_month,
  SUM(extended_price) AS revenue
FROM read_parquet('data/staging/stg_lineitem.parquet')
WHERE ship_date >= DATE '1995-01-01'
GROUP BY 1
ORDER BY 1;
```

Compare read cost — Parquet with column pruning vs full CSV scan:

```sql
-- Fast: two columns from Parquet
SELECT l_orderkey, extended_price
FROM read_parquet('data/staging/stg_lineitem.parquet')
LIMIT 1000;

-- Slow: full CSV parse every time
SELECT l_orderkey, l_extendedprice
FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv')
LIMIT 1000;
```

## Notebook usage

```python
LINEITEM_CSV = "https://blobs.duckdb.org/data/lineitem.csv"
STAGING_PARQUET = STAGING_DIR / "stg_lineitem.parquet"

con.execute("INSTALL httpfs; LOAD httpfs;")

# source → raw (audit snapshot)
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_lineitem_csv AS
SELECT * FROM read_csv_auto('{LINEITEM_CSV}');
""")

# raw → staging Parquet (run once per ingest)
con.execute(f"""
COPY (
  SELECT
    l_orderkey,
    l_linenumber,
    CAST(l_shipdate AS DATE) AS ship_date,
    l_extendedprice AS extended_price
  FROM raw.raw_lineitem_csv
  WHERE l_shipdate IS NOT NULL
) TO '{STAGING_PARQUET.as_posix()}'
(FORMAT PARQUET, COMPRESSION ZSTD);
""")

# Repeated cells: query Parquet
con.sql("""
SELECT ship_month, SUM(extended_price) AS revenue
FROM (
  SELECT
    DATE_TRUNC('month', ship_date) AS ship_month,
    extended_price
  FROM read_parquet('data/staging/stg_lineitem.parquet')
  WHERE ship_date >= DATE '1995-01-01'
)
GROUP BY 1
ORDER BY 1
""").df()
```

## Common variations

### View over Parquet (no duplicate inside `.duckdb`)

```sql
CREATE OR REPLACE VIEW staging.stg_lineitem AS
SELECT * FROM read_parquet('data/staging/stg_lineitem.parquet');
```

### Remote Parquet as `source` (skip CSV entirely)

```sql
CREATE OR REPLACE VIEW raw.raw_lineitem_parquet AS
SELECT * FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
```

### Hive-partitioned staging layout

```sql
COPY (
  SELECT *, DATE_TRUNC('year', ship_date) AS ship_year
  FROM read_parquet('data/staging/stg_lineitem.parquet')
) TO 'data/staging/lineitem_partitioned'
(FORMAT PARQUET, PARTITION_BY (ship_year), COMPRESSION ZSTD);
```

### GeoParquet for spatial layers

```sql
INSTALL spatial;
LOAD spatial;

COPY (
  SELECT region_name, geom
  FROM curated.cur_ca_regions
) TO 'data/staging/stg_ca_regions.parquet'
(FORMAT PARQUET);
```

## Practical notes

- **First run cost:** CSV → Parquet conversion takes time once; amortize it across many downstream queries.
- **Row groups:** When you control export, aim for row groups of roughly 100k–1M rows — balances parallelism and metadata overhead.
- **File size vs query speed:** ZSTD compresses better than SNAPPY; both are fine for analytics.
- **Validation:** After conversion, reconcile row counts and key sums between `raw` and staging Parquet before building `curated`.
- **Workflow fit:** Keep CSV in `raw` for lineage; treat staging Parquet as the performance layer for transforms.

## Known limitations

- Parquet in `data/staging/` is a second copy on disk — monitor storage when `raw` tables also live inside `work.duckdb`.
- Schema changes in upstream CSV require re-running the conversion; old Parquet files will not auto-update.
- GeoParquet may need `ST_Read` rather than plain `read_parquet` for full geometry semantics.
- Very small Parquet files in large folder trees add open-file overhead — consolidate when possible.
- Encrypted Parquet is not supported out of the box.

## Related Pages

- [Parquet ingestion](../02_ingestion/parquet.md)
- [Column selection](column_selection.md)
- [Predicate pushdown](predicate_pushdown.md)
- [Large file patterns](large_file_patterns.md)

Official reference: [DuckDB Parquet](https://duckdb.org/docs/current/data/parquet/overview.html)
