# Column Selection

Read and carry forward only the columns your pipeline needs.

## Purpose

Reduce I/O and memory by projecting required columns at each workflow layer instead of propagating wide `SELECT *` tables through `raw`, `staging`, and `curated`.

## Why it matters

Columnar formats like Parquet store data per column. Reading ten columns from a 200-column file can be an order of magnitude faster than `SELECT *`. The same applies inside DuckDB tables: narrower staging tables speed joins, sorts, and exports.

Analysts often need three attributes; engineers often ingest everything into `raw` for audit — **project down in `staging`**, not at export time only.

## Recommended pattern

1. `raw`: keep full `source` snapshot when audit requires it.
2. `staging`: `SELECT` only cleaned columns used downstream; drop PII and unused vendor fields early.
3. `curated` and `output`: project again for consumer contracts.
4. At file-read time, list columns explicitly in `read_parquet` when possible.
5. Pair column selection with early filters (see [predicate pushdown](predicate_pushdown.md)).

```text
raw (wide, auditable) → staging (lean columns) → curated (business columns) → output
```

## Anti-pattern

```sql
-- Carries 150 unused columns through the pipeline
CREATE TABLE staging.stg_orders AS
SELECT * FROM raw.raw_orders_csv;

-- Reads every column from Parquet to return two
SELECT order_id, amount
FROM (SELECT * FROM read_parquet('data/staging/wide_orders.parquet')) t;

-- Join explosion on wide rows
SELECT *
FROM staging.stg_orders o
JOIN staging.stg_customers c ON o.customer_id = c.customer_id;
```

## SQL example

Projection pushdown on online Parquet — only two columns touch disk:

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT
  l_orderkey,
  l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate >= DATE '1995-01-01';
```

Explicit column list at `read_parquet` (when supported for your file set):

```sql
SELECT l_orderkey, l_extendedprice, l_shipdate
FROM read_parquet(
  'data/staging/stg_lineitem.parquet',
  l_orderkey, l_extendedprice, l_shipdate
);
```

Narrow staging table from wide `raw`:

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_lineitem AS
SELECT
  l_orderkey,
  l_linenumber,
  CAST(l_shipdate AS DATE) AS ship_date,
  l_extendedprice AS extended_price,
  l_quantity AS quantity
FROM raw.raw_lineitem_csv
WHERE l_shipdate IS NOT NULL;
```

Curated export with final column set:

```sql
COPY (
  SELECT
    order_id,
    order_date,
    customer_id,
    amount
  FROM curated.cur_fact_orders
) TO 'data/output/fct_orders.parquet'
(FORMAT PARQUET);
```

## Notebook usage

```python
con.execute("INSTALL httpfs; LOAD httpfs;")

# Ingest wide raw snapshot once
con.execute("""
CREATE OR REPLACE TABLE raw.raw_lineitem_csv AS
SELECT * FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv');
""")

# Project to lean staging columns
con.execute("""
CREATE OR REPLACE TABLE staging.stg_lineitem AS
SELECT
  l_orderkey,
  CAST(l_shipdate AS DATE) AS ship_date,
  l_extendedprice AS extended_price
FROM raw.raw_lineitem_csv
WHERE l_shipdate IS NOT NULL;
""")

# Compare column footprint
con.sql("""
SELECT
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = 'raw' AND table_name = 'raw_lineitem_csv') AS raw_cols,
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = 'staging' AND table_name = 'stg_lineitem') AS staging_cols
""").df()
```

## Common variations

### Drop geometry until needed (tabular branch)

```sql
CREATE TABLE staging.stg_parcels_attrs AS
SELECT parcel_id, zoning_code, land_use
FROM raw.raw_parcels_shp;
-- geom retained in separate staging.stg_parcels_spatial if required
```

### Spatial: keep `geom` plus minimal attributes

```sql
CREATE TABLE staging.stg_boundary AS
SELECT
  properties.NAME AS region_name,
  geom
FROM raw.raw_ca_regions_geojson;
```

### Column selection in CTE pipeline

```sql
WITH filtered AS (
  SELECT l_orderkey, ship_date, extended_price
  FROM staging.stg_lineitem
  WHERE ship_date >= DATE '1996-01-01'
),
monthly AS (
  SELECT DATE_TRUNC('month', ship_date) AS ship_month, extended_price
  FROM filtered
)
SELECT ship_month, SUM(extended_price) AS revenue
FROM monthly
GROUP BY 1;
```

### `EXPLAIN` to confirm projection pushdown

```sql
EXPLAIN
SELECT l_orderkey, l_extendedprice
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
```

The plan should list only requested columns under `PARQUET_SCAN`.

## Practical notes

- **Name the contract:** Document required columns per `staging.stg_*` and `curated.cur_*` table in notebook headers.
- **PII:** Dropping sensitive columns in `staging` reduces accidental exposure in exports and logs.
- **Wide CSV:** Column selection at `read_csv` is harder than Parquet — another reason to convert to staging Parquet early.
- **Join keys:** Always retain join keys and filter columns even when trimming attributes.
- **Verify:** `DESCRIBE staging.stg_lineitem` after each refactor.

## Known limitations

- `SELECT *` in views over Parquet may still allow pushdown, but views over wide DuckDB tables materialize all columns on write.
- Schema evolution across Parquet files may add unexpected columns — validate with `DESCRIBE` per batch.
- Some GDAL spatial reads load all attribute columns — trim in `staging` after `ST_Read`.
- Dropping columns in SQL does not shrink existing `raw` tables inside `work.duckdb` — it only affects downstream tables.

## Related Pages

- [Parquet best practices](parquet_best_practices.md)
- [Predicate pushdown](predicate_pushdown.md)
- [Memory management](memory_management.md)
- [Column standardization](../06_cleaning/column_standardization.md)

Official reference: [DuckDB Parquet](https://duckdb.org/docs/current/data/parquet/overview.html)
