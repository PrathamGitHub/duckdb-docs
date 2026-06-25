# Pivot / Unpivot

Reshape wide ↔ long tables in `staging` or `curated` for analysis-ready marts and exports.

## Purpose

Convert month columns to rows (unpivot / melt) or spread category values into columns (pivot) so BI tools, notebooks, and SQL aggregations can work at a consistent grain.

## When to Use

- Vendor delivers wide spreadsheets (Jan, Feb, Mar columns) you need as `sales_month` + `amount` rows
- Building `curated.mart_monthly_sales` in wide format for Excel consumers
- Normalizing attribute columns before [aggregations](aggregations.md)
- Reshaping survey or indicator columns into tidy long format

## SQL Template

### Unpivot — wide monthly columns to long rows

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE staging.stg_sales_wide AS
SELECT * FROM (VALUES
  ('west', 1200.0, 1350.0, 1100.0),
  ('east', 900.0, 950.0, 1000.0)
) AS t(region, jan_sales, feb_sales, mar_sales);

CREATE OR REPLACE TABLE curated.mart_monthly_sales AS
UNPIVOT staging.stg_sales_wide
ON jan_sales, feb_sales, mar_sales
INTO
  NAME sales_month
  VALUE total_sales;
```

Manual `UNION ALL` unpivot (portable, explicit month mapping):

```sql
CREATE OR REPLACE TABLE curated.mart_monthly_sales AS
SELECT region, DATE '2024-01-01' AS sales_month, jan_sales AS total_sales
FROM staging.stg_sales_wide
UNION ALL
SELECT region, DATE '2024-02-01', feb_sales FROM staging.stg_sales_wide
UNION ALL
SELECT region, DATE '2024-03-01', mar_sales FROM staging.stg_sales_wide;
```

### Pivot — long rows to wide columns

```sql
CREATE OR REPLACE TABLE curated.mart_sales_pivot AS
PIVOT (
  SELECT region, DATE_TRUNC('month', order_date) AS sales_month, amount
  FROM curated.fct_orders
  WHERE order_status = 'shipped'
)
ON sales_month
USING SUM(amount) AS total_sales
GROUP BY region;
```

`CASE` pivot without `PIVOT` syntax:

```sql
CREATE OR REPLACE TABLE curated.mart_sales_pivot AS
SELECT
  region,
  SUM(amount) FILTER (WHERE DATE_TRUNC('month', order_date) = DATE '2024-01-01') AS jan_2024,
  SUM(amount) FILTER (WHERE DATE_TRUNC('month', order_date) = DATE '2024-02-01') AS feb_2024,
  SUM(amount) FILTER (WHERE DATE_TRUNC('month', order_date) = DATE '2024-03-01') AS mar_2024
FROM curated.fct_orders
WHERE order_status = 'shipped'
GROUP BY region;
```

## Notebook Usage

Build long-format mart from orders, then pivot wide:

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM (VALUES
  ('C-100', 'west'), ('C-101', 'east')
) AS t(customer_id, region);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 120.0, 'shipped'),
  ('ORD-002', 'C-100', DATE '2024-02-10', 130.0, 'shipped'),
  ('ORD-003', 'C-101', DATE '2024-01-20', 90.0, 'shipped')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT o.order_id, o.customer_id, c.region, o.order_date, o.amount, o.order_status
FROM staging.stg_orders o
INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id;
""")

con.execute("""
CREATE OR REPLACE TABLE curated.mart_monthly_sales AS
SELECT
  DATE_TRUNC('month', order_date) AS sales_month,
  region,
  SUM(amount) AS total_sales
FROM curated.fct_orders
WHERE order_status = 'shipped'
GROUP BY 1, 2;
""")

con.sql("""
  PIVOT (
    SELECT region, sales_month, total_sales FROM curated.mart_monthly_sales
  )
  ON sales_month
  USING SUM(total_sales)
  GROUP BY region
""").df()
```

Unpivot online wide-style data with `UNION ALL`:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")
# Already long format — pivot to wide for practice
con.sql("""
  PIVOT (
    SELECT country_name, year, value
    FROM raw.raw_population_csv
    WHERE country_name IN ('United States', 'Canada')
      AND TRY_CAST(year AS INTEGER) BETWEEN 2018 AND 2020
  )
  ON year
  USING SUM(TRY_CAST(value AS DOUBLE))
  GROUP BY country_name
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{wide_table}` | `staging.stg_sales_wide` | Columns to unpivot |
| `{long_table}` | `curated.mart_monthly_sales` | name/value pair output |
| Unpivot columns | `jan_sales, feb_sales, mar_sales` | Wide measure columns |
| Pivot key | `sales_month` | Column spread into headers |
| Aggregate | `SUM(amount)` | Required in `PIVOT` |
| Group columns | `region` | Grain preserved in pivot |

## Input Table Pattern

**Wide (staging):** `staging.stg_sales_wide`

| region | jan_sales | feb_sales | mar_sales |
|--------|-----------|-----------|-----------|
| west | 1200.0 | 1350.0 | 1100.0 |
| east | 900.0 | 950.0 | 1000.0 |

**Long (curated):** `curated.mart_monthly_sales`

| sales_month | region | total_sales |
|-------------|--------|-------------|
| 2024-01-01 | west | 1200.0 |
| 2024-02-01 | west | 1350.0 |

## Output Table Pattern

```text
curated.mart_<topic>          -- long tidy format (preferred for analytics)
curated.mart_<topic>_pivot    -- wide format (Excel / legacy tools)
staging.stg_<entity>_unpivot  -- intermediate long staging
```

**Pivoted output example:**

| region | 2024-01-01 | 2024-02-01 | 2024-03-01 |
|--------|------------|------------|------------|
| west | 1200.0 | 1350.0 | 1100.0 |
| east | 900.0 | 950.0 | 1000.0 |

## Validation Checks

```sql
-- Unpivot: sum of values equals sum of wide columns
SELECT
  (SELECT jan_sales + feb_sales + mar_sales FROM staging.stg_sales_wide
   WHERE region = 'west') AS wide_total,
  (SELECT SUM(total_sales) FROM curated.mart_monthly_sales WHERE region = 'west') AS long_total;
```

```sql
-- Pivot round-trip row count
SELECT region, COUNT(*) AS n
FROM curated.mart_monthly_sales
GROUP BY 1;
```

```sql
-- No null pivot keys
SELECT COUNT(*) AS null_month_rows
FROM curated.mart_monthly_sales
WHERE sales_month IS NULL;
```

```sql
-- Reconcile pivoted total to fact revenue
SELECT
  (SELECT SUM(amount) FROM curated.fct_orders WHERE order_status = 'shipped') AS fact_total,
  (SELECT SUM(total_sales) FROM curated.mart_monthly_sales) AS mart_total;
```

## Common Variations

### `UNPIVOT` with column name cleanup

```sql
UNPIVOT staging.stg_sales_wide
ON COLUMNS(c -> c LIKE '%_sales')
INTO NAME sales_month VALUE total_sales;
```

### Stack multiple entities

```sql
SELECT 'orders' AS source, sales_month, region, total_sales
FROM curated.mart_monthly_sales
UNION ALL
SELECT 'returns', return_month, region, return_amount
FROM curated.mart_monthly_returns;
```

### Unpivot JSON keys (nested wide data)

```sql
SELECT
  order_id,
  UNNEST(json_keys(metrics_json)) AS metric_name,
  json_extract(metrics_json, '$.' || metric_name) AS metric_value
FROM staging.stg_orders_json;
```

### Spatial attribute pivot

```sql
PIVOT (
  SELECT zone_code, land_use, SUM(ST_Area(geom)) AS area
  FROM staging.stg_parcels
  GROUP BY 1, 2
)
ON land_use
USING SUM(area)
GROUP BY zone_code;
```

## Performance Notes

- Prefer long format in `curated` for downstream SQL — pivot only at export time when consumers require wide layouts.
- `FILTER` aggregates (`SUM(x) FILTER (WHERE ...)`) often outperform dynamic pivot for a fixed set of columns.
- `PIVOT` with high-cardinality `ON` columns creates many output columns — watch width limits in Excel.
- Unpivot early when wide sources have hundreds of indicator columns — reduces projection width for later steps.

## Known Limitations

- `PIVOT` column names derive from pivot key values — special characters in months or categories may need quoting.
- `UNPIVOT` requires explicit column lists unless using `COLUMNS()` expressions.
- Unknown future months in wide feeds need dynamic SQL or repeated template updates.
- Pivoting already-aggregated data prevents drill-down to order grain — keep `curated.fct_orders` as the detail source.

## Related Pages

- [Aggregations](aggregations.md)
- [Build fact table](build_fact_table.md)
- [Excel ingestion](../02_ingestion/excel.md)

Official reference: [PIVOT](https://duckdb.org/docs/current/sql/statements/pivot.html) · [UNPIVOT](https://duckdb.org/docs/current/sql/statements/unpivot.html)
