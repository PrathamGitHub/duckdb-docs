# Aggregations

Roll up `staging.stg_*` metrics to a declared reporting grain in `curated` marts.

## Purpose

Summarize orders, sales, or spatial features to the grain analysts need — monthly totals, per-customer counts, regional sums — without losing the ability to trace back to staging row counts.

## When to Use

- Building `curated.mart_monthly_sales` from `curated.fct_orders`
- Reducing event-level `staging.stg_orders` to customer or region summaries
- Pre-aggregating before export to dashboards or Parquet in `output`
- Spatial summaries (count parcels per zone, sum area by land use)

## SQL Template

Monthly sales mart from fact orders:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.mart_monthly_sales AS
SELECT
  DATE_TRUNC('month', order_date) AS sales_month,
  region,
  customer_segment,
  COUNT(*) AS order_count,
  COUNT(DISTINCT customer_id) AS customer_count,
  SUM(amount) AS total_sales,
  AVG(amount) AS avg_order_value,
  MIN(order_date) AS first_order_date_in_month,
  MAX(order_date) AS last_order_date_in_month
FROM curated.fct_orders
WHERE order_status = 'shipped'
GROUP BY
  DATE_TRUNC('month', order_date),
  region,
  customer_segment;
```

Aggregate directly from staging (skip fact table when prototyping):

```sql
CREATE OR REPLACE TABLE curated.mart_monthly_sales AS
SELECT
  DATE_TRUNC('month', o.order_date) AS sales_month,
  c.region,
  COUNT(*) AS order_count,
  SUM(o.amount) AS total_sales
FROM staging.stg_orders o
INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'shipped'
GROUP BY 1, 2;
```

`GROUP BY ALL` shorthand:

```sql
SELECT
  DATE_TRUNC('month', order_date) AS sales_month,
  region,
  SUM(amount) AS total_sales
FROM curated.fct_orders
GROUP BY ALL;
```

Filtered aggregates:

```sql
SELECT
  region,
  COUNT(*) AS total_orders,
  COUNT(*) FILTER (WHERE amount >= 100) AS high_value_orders,
  SUM(amount) FILTER (WHERE order_status = 'shipped') AS shipped_revenue
FROM curated.fct_orders
GROUP BY region;
```

## Notebook Usage

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM (VALUES
  ('C-100', 'Acme Corp', 'enterprise', 'west'),
  ('C-101', 'Beta LLC', 'smb', 'east')
) AS t(customer_id, customer_name, customer_segment, region);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 150.0, 'shipped'),
  ('ORD-002', 'C-100', DATE '2024-02-01', 75.0, 'shipped'),
  ('ORD-003', 'C-101', DATE '2024-01-20', 50.0, 'shipped')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT o.*, c.region, c.customer_segment
FROM staging.stg_orders o
INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id;
""")

con.execute("""
CREATE OR REPLACE TABLE curated.mart_monthly_sales AS
SELECT
  DATE_TRUNC('month', order_date) AS sales_month,
  region,
  SUM(amount) AS total_sales,
  COUNT(*) AS order_count
FROM curated.fct_orders
WHERE order_status = 'shipped'
GROUP BY 1, 2;
""")

con.sql("SELECT * FROM curated.mart_monthly_sales ORDER BY sales_month, region").df()
```

Online dataset — population by year:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.mart_population_by_year AS
SELECT
  TRY_CAST(year AS INTEGER) AS year,
  COUNT(DISTINCT country_name) AS country_count,
  SUM(TRY_CAST(value AS DOUBLE)) AS world_population
FROM raw.raw_population_csv
WHERE TRY_CAST(value AS DOUBLE) IS NOT NULL
GROUP BY 1
ORDER BY 1;
""")
con.sql("SELECT * FROM curated.mart_population_by_year WHERE year >= 2010").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{source_table}` | `curated.fct_orders` | Event or staging input |
| `{output_table}` | `curated.mart_monthly_sales` | Aggregated mart |
| Grouping columns | `sales_month`, `region` | Define mart grain |
| Measure columns | `amount`, `order_id` | Inside `SUM`, `COUNT`, `AVG` |
| Filter | `order_status = 'shipped'` | Apply before `GROUP BY` |
| Time truncation | `DATE_TRUNC('month', order_date)` | Align to reporting calendar |

## Input Table Pattern

```text
staging.stg_<entity>     -- event grain
curated.fct_<entity>     -- preferred fact input
```

Example: **`curated.fct_orders`** — one row per order

| order_id | customer_id | region | order_date | amount | order_status |
|----------|-------------|--------|------------|--------|--------------|
| ORD-001 | C-100 | west | 2024-01-15 | 150.0 | shipped |
| ORD-002 | C-100 | west | 2024-02-01 | 75.0 | shipped |
| ORD-003 | C-101 | east | 2024-01-20 | 50.0 | shipped |

## Output Table Pattern

```text
curated.mart_<grain>_<topic>
```

Example: **`curated.mart_monthly_sales`** — one row per month × region

| sales_month | region | order_count | total_sales |
|-------------|--------|-------------|-------------|
| 2024-01-01 | west | 1 | 150.0 |
| 2024-01-01 | east | 1 | 50.0 |
| 2024-02-01 | west | 1 | 75.0 |

## Validation Checks

```sql
-- Revenue reconciliation: mart total vs fact total
SELECT
  (SELECT SUM(amount) FROM curated.fct_orders WHERE order_status = 'shipped') AS fact_revenue,
  (SELECT SUM(total_sales) FROM curated.mart_monthly_sales) AS mart_revenue;
```

```sql
-- Order count reconciliation
SELECT
  (SELECT COUNT(*) FROM curated.fct_orders WHERE order_status = 'shipped') AS fact_orders,
  (SELECT SUM(order_count) FROM curated.mart_monthly_sales) AS mart_orders;
```

```sql
-- Unexpected duplicate groups
SELECT sales_month, region, COUNT(*) AS n
FROM curated.mart_monthly_sales
GROUP BY 1, 2
HAVING COUNT(*) > 1;
```

```sql
-- Null group keys
SELECT COUNT(*) AS null_region_rows
FROM curated.mart_monthly_sales
WHERE region IS NULL;
```

## Common Variations

### `GROUPING SETS` for subtotals

```sql
SELECT
  DATE_TRUNC('month', order_date) AS sales_month,
  region,
  SUM(amount) AS total_sales,
  GROUPING(sales_month) AS g_month,
  GROUPING(region) AS g_region
FROM curated.fct_orders
GROUP BY GROUPING SETS (
  (sales_month, region),
  (sales_month),
  ()
);
```

### `ROLLUP` / `CUBE`

```sql
SELECT region, customer_segment, SUM(amount) AS total_sales
FROM curated.fct_orders
GROUP BY ROLLUP (region, customer_segment);
```

### Percent of total with window

```sql
SELECT
  region,
  SUM(amount) AS region_sales,
  SUM(amount) / SUM(SUM(amount)) OVER () AS pct_of_total
FROM curated.fct_orders
GROUP BY region;
```

### Spatial aggregation

```sql
CREATE OR REPLACE TABLE curated.mart_parcels_by_zone AS
SELECT
  zone_code,
  COUNT(*) AS parcel_count,
  SUM(ST_Area(geom)) AS total_area
FROM staging.stg_parcels
GROUP BY zone_code;
```

### Histogram buckets

```sql
SELECT
  WIDTH_BUCKET(amount, 0, 500, 10) AS amount_bucket,
  COUNT(*) AS order_count
FROM curated.fct_orders
GROUP BY 1;
```

## Performance Notes

- Filter rows before `GROUP BY` — `WHERE order_status = 'shipped'` reduces aggregation input.
- Pre-build `curated.fct_orders` once; aggregate marts many times from the fact table.
- `COUNT(DISTINCT customer_id)` is more expensive than `COUNT(*)` — use only when needed.
- For very large facts, consider partitioning exports by `sales_month` rather than one giant mart.
- `GROUP BY ALL` is convenient but explicit column lists are clearer in version-controlled templates.

## Known Limitations

- Averages of averages are wrong — recompute `AVG` from source amounts, not from pre-averaged marts.
- `COUNT(*)` includes null measure rows; use `COUNT(order_id)` or `COUNT(amount)` when excluding nulls.
- Month boundaries depend on `DATE_TRUNC` timezone — document timezone assumptions in the notebook.
- Semi-additive measures (balances, inventory) need different patterns than additive sales amounts.

## Related Pages

- [Build fact table](build_fact_table.md)
- [Window functions](window_functions.md)
- [Pivot / unpivot](pivot_unpivot.md)
- [Aggregate reconciliation](../04_eda/numeric_summary.md)

Official reference: [Aggregate functions](https://duckdb.org/docs/current/sql/functions/aggregates.html)
