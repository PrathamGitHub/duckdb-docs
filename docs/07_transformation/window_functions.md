# Window Functions

Compute rank, lag, lead, and running totals over `staging.stg_*` or `curated.fct_*` without collapsing row grain.

## Purpose

Add sequence, prior-period, and within-group metrics while keeping one row per order, customer, or feature — essential for cohort analysis and row-level enrichment before fact or mart builds.

## When to Use

- Customer order sequence (`customer_order_sequence`) on `curated.fct_orders`
- Year-over-year population change on `staging.stg_population`
- Deduplication with `ROW_NUMBER()` before `curated.dim_customers`
- Top-N per group without a separate aggregation step
- Running sales totals by month within region

## SQL Template

Enrich orders with window metrics:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  order_id,
  customer_id,
  region,
  order_date,
  amount,
  order_status,
  ROW_NUMBER() OVER (
    PARTITION BY customer_id ORDER BY order_date, order_id
  ) AS customer_order_sequence,
  LAG(amount) OVER (
    PARTITION BY customer_id ORDER BY order_date
  ) AS prior_order_amount,
  SUM(amount) OVER (
    PARTITION BY customer_id
    ORDER BY order_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS customer_running_total,
  RANK() OVER (
    PARTITION BY region ORDER BY amount DESC
  ) AS amount_rank_in_region
FROM (
  SELECT o.*, c.region
  FROM staging.stg_orders o
  INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id
  WHERE o.order_status NOT IN ('cancelled', 'void')
) base;
```

Filter with `QUALIFY` (keep top 3 orders per customer by amount):

```sql
CREATE OR REPLACE TABLE staging.stg_orders_top3 AS
SELECT
  order_id,
  customer_id,
  order_date,
  amount
FROM staging.stg_orders
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY customer_id ORDER BY amount DESC
) <= 3;
```

Year-over-year on staging population:

```sql
CREATE OR REPLACE TABLE staging.stg_population_yoy AS
SELECT
  country_name,
  year,
  population,
  LAG(population) OVER (
    PARTITION BY country_name ORDER BY year
  ) AS prior_year_population,
  population - LAG(population) OVER (
    PARTITION BY country_name ORDER BY year
  ) AS yoy_change
FROM staging.stg_population;
```

## Notebook Usage

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 100.0, 'shipped'),
  ('ORD-002', 'C-100', DATE '2024-03-01', 150.0, 'shipped'),
  ('ORD-003', 'C-101', DATE '2024-02-10', 75.0, 'shipped')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS customer_order_sequence,
  LAG(amount) OVER (PARTITION BY customer_id ORDER BY order_date) AS prior_order_amount
FROM staging.stg_orders;
""")

con.sql("""
  SELECT order_id, customer_id, amount, customer_order_sequence, prior_order_amount
  FROM curated.fct_orders
  ORDER BY customer_id, order_date
""").df()
```

Online population dataset:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE TRY_CAST(year AS INTEGER) >= 2000;
""")

con.sql("""
  SELECT country_name, year, population,
    population - LAG(population) OVER (
      PARTITION BY country_name ORDER BY year
    ) AS yoy_change
  FROM staging.stg_population
  WHERE country_name = 'United States'
  ORDER BY year DESC
  LIMIT 10
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{source_table}` | `staging.stg_orders` | Input at desired grain |
| `{output_table}` | `curated.fct_orders` | Row-level output with window columns |
| `PARTITION BY` | `customer_id` | Group boundaries |
| `ORDER BY` | `order_date`, `order_id` | Deterministic tie-breaking |
| Frame clause | `ROWS BETWEEN ...` | Running totals vs full partition |
| `QUALIFY` predicate | `ROW_NUMBER() ... <= 3` | Post-window filter |

## Input Table Pattern

```text
staging.stg_<entity>
```

Example: **`staging.stg_orders`**

| order_id | customer_id | order_date | amount | order_status |
|----------|-------------|------------|--------|--------------|
| ORD-001 | C-100 | 2024-01-15 | 100.0 | shipped |
| ORD-002 | C-100 | 2024-03-01 | 150.0 | shipped |
| ORD-003 | C-101 | 2024-02-10 | 75.0 | shipped |

## Output Table Pattern

```text
staging.stg_<entity>_<qualifier>
curated.fct_<entity>
```

Example: **`curated.fct_orders`** — same grain as input, plus window columns

| order_id | customer_id | order_date | amount | customer_order_sequence | prior_order_amount |
|----------|-------------|------------|--------|-------------------------|-------------------|
| ORD-001 | C-100 | 2024-01-15 | 100.0 | 1 | NULL |
| ORD-002 | C-100 | 2024-03-01 | 150.0 | 2 | 100.0 |
| ORD-003 | C-101 | 2024-02-10 | 75.0 | 1 | NULL |

## Validation Checks

```sql
-- Grain preserved: same row count as filtered source
SELECT
  (SELECT COUNT(*) FROM staging.stg_orders
   WHERE order_status NOT IN ('cancelled', 'void')) AS source_rows,
  (SELECT COUNT(*) FROM curated.fct_orders) AS fct_rows;
```

```sql
-- First sequence number per partition should be 1
SELECT customer_id, MIN(customer_order_sequence) AS min_seq
FROM curated.fct_orders
GROUP BY 1
HAVING MIN(customer_order_sequence) != 1;
```

```sql
-- Duplicate order_id after window (should be zero)
SELECT order_id, COUNT(*) AS n
FROM curated.fct_orders
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Running total monotonicity per customer
SELECT *
FROM curated.fct_orders
WHERE customer_running_total < COALESCE(prior_order_amount, 0);
```

## Common Variations

### `NTILE` for quartiles

```sql
NTILE(4) OVER (PARTITION BY region ORDER BY amount) AS amount_quartile
```

### `LEAD` for next order date

```sql
LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date
```

### Moving average (3-row window)

```sql
AVG(amount) OVER (
  PARTITION BY customer_id
  ORDER BY order_date
  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
) AS moving_avg_3
```

### `DENSE_RANK` vs `RANK` for ties

```sql
DENSE_RANK() OVER (PARTITION BY region ORDER BY amount DESC) AS dense_rank_in_region
```

### Dedup to dimension (`stg_*` → `dim_*`)

```sql
CREATE OR REPLACE TABLE curated.dim_customers AS
SELECT customer_id, customer_name, region
FROM staging.stg_customers
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY customer_id ORDER BY updated_at DESC
) = 1;
```

## Performance Notes

- Window functions scan partitions — smaller partitions (e.g., `customer_id`) are cheaper than one global partition.
- Always include a tie-breaker in `ORDER BY` (`order_id`) for deterministic `ROW_NUMBER()`.
- `QUALIFY` filters after window evaluation — combine with narrow `WHERE` on the source when possible.
- Multiple windows over the same partition can share work; DuckDB optimizes where possible.
- For heavy top-N per group at scale, compare `QUALIFY` vs pre-aggregation approaches with `EXPLAIN`.

## Known Limitations

- Window frames and `ORDER BY` must match business time ordering — late-arriving data can reshuffle sequences on full refresh.
- `LAG`/`LEAD` return NULL at partition boundaries — handle with `COALESCE` if needed.
- `RANK` skips numbers after ties; `DENSE_RANK` does not — pick intentionally for reporting.
- Global windows without `PARTITION BY` process the entire table — avoid on large datasets without filters.

## Related Pages

- [CTE pipeline](cte_pipeline.md)
- [Deduplication](../06_cleaning/deduplication.md)
- [Build fact table](build_fact_table.md)
- [Aggregations](aggregations.md)

Official reference: [Window functions](https://duckdb.org/docs/current/sql/window_functions.html)
