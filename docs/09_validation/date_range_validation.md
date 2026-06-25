# Date Range Validation

Assert date and timestamp columns fall within an allowed business window.

## Purpose

Return rows with future dates, pre-epoch sentinels, or values outside project scope. **Zero rows means pass.** (Use [date range check (EDA)](../04_eda/date_range_check.md) for exploratory min/max summaries.)

## When to Use

- On `staging.stg_orders` — `order_date` between project start and today
- On `curated.fct_orders` — no orders before customer `created_at`
- Before partitioning `curated` by month — confirm no stray centuries
- Incremental loads — new batch dates within expected window

## SQL Template

Future dates:

```sql
SELECT
  order_id,
  order_date,
  amount
FROM staging.stg_orders
WHERE order_date IS NOT NULL
  AND CAST(order_date AS DATE) > CURRENT_DATE
ORDER BY order_date DESC
LIMIT 100;
```

Fixed business window:

```sql
SELECT
  order_id,
  order_date
FROM staging.stg_orders
WHERE order_date IS NOT NULL
  AND (
    CAST(order_date AS DATE) < DATE '2020-01-01'
    OR CAST(order_date AS DATE) > DATE '2099-12-31'
  );
```

Order before customer existed:

```sql
SELECT
  o.order_id,
  o.order_date,
  c.customer_id,
  c.created_at
FROM staging.stg_orders o
INNER JOIN curated.dim_customers c ON o.customer_id = c.customer_id
WHERE CAST(o.order_date AS DATE) < CAST(c.created_at AS DATE);
```

Ship date after order date:

```sql
SELECT
  order_id,
  order_date,
  ship_date
FROM staging.stg_orders
WHERE ship_date IS NOT NULL
  AND order_date IS NOT NULL
  AND CAST(ship_date AS DATE) < CAST(order_date AS DATE);
```

## Notebook Usage

```python
future_orders = con.sql("""
  SELECT order_id, order_date, amount
  FROM staging.stg_orders
  WHERE order_date IS NOT NULL
    AND CAST(order_date AS DATE) > CURRENT_DATE
  LIMIT 50
""").df()

assert future_orders.empty, f"Future-dated orders: {len(future_orders)}"
future_orders
```

Configurable bounds in notebook:

```python
MIN_DATE = "2020-01-01"
MAX_DATE = "2099-12-31"

con.sql(f"""
  SELECT order_id, order_date
  FROM staging.stg_orders
  WHERE order_date IS NOT NULL
    AND (
      CAST(order_date AS DATE) < DATE '{MIN_DATE}'
      OR CAST(order_date AS DATE) > DATE '{MAX_DATE}'
    )
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Typed `DATE` preferred in staging |
| Date column | `order_date`, `ship_date`, `created_at` | Cast if still `VARCHAR` in `raw` |
| `{min_date}` | `DATE '2020-01-01'` | Project lower bound |
| `{max_date}` | `CURRENT_DATE` or `DATE '2099-12-31'` | Upper bound |
| Cross-table rule | order vs customer `created_at` | Logical date ordering |

## Expected Output

**On fail:**

| order_id | order_date | amount |
|----------|------------|--------|
| ORD-9001 | 2026-01-15 | 120.00 |
| ORD-9002 | 1999-12-31 | 45.00 |

**On pass:** zero rows.

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero rows | **Pass** — dates within allowed window |
| Future `order_date` | **Fail** — timezone, clock, or placeholder data |
| Pre-epoch dates | **Fail** — wrong century or sentinel not filtered |
| `ship_date` < `order_date` | **Fail** — logical inconsistency |
| NULL dates | Excluded — validate separately if required |

## Common Variations

### Unparseable date strings still in staging

```sql
SELECT order_id, order_date AS raw_value
FROM staging.stg_orders
WHERE order_date IS NOT NULL
  AND TRY_CAST(order_date AS DATE) IS NULL;
```

### Fact table scoped to shipped orders

```sql
SELECT order_id, order_date
FROM curated.fct_orders
WHERE order_status = 'shipped'
  AND CAST(order_date AS DATE) > CURRENT_DATE;
```

### Fiscal year bounds

```sql
SELECT order_id, order_date
FROM curated.fct_orders
WHERE order_date IS NOT NULL
  AND CAST(order_date AS DATE) < DATE '2019-07-01';  -- FY2020 start
```

### Scalar for summary table

```sql
SELECT
  'date_range_validation' AS check_name,
  'staging.stg_orders.order_date' AS field,
  COUNT(*) AS violating_rows
FROM staging.stg_orders
WHERE order_date IS NOT NULL
  AND (
    CAST(order_date AS DATE) < DATE '2020-01-01'
    OR CAST(order_date AS DATE) > CURRENT_DATE
  );
```

## How to Document Results

```text
Check: VAL-007 Date range validation
Field: staging.stg_orders.order_date
Window: 2020-01-01 .. CURRENT_DATE
Result: FAIL — 1 future-dated row (ORD-9001)
Action: Excluded test row; re-run PASS
```

Note whether bounds are inclusive and which timezone applies (`UTC` in staging recommended). Log in [validation summary table](validation_summary_table.md).

## Related Pages

- [Value range check](value_range_check.md)
- [Date range check (EDA)](../04_eda/date_range_check.md)
- [Date parsing (cleaning)](../06_cleaning/date_parsing.md)
- [Incremental load pattern](../07_transformation/incremental_load_pattern.md)

Official reference: [DuckDB date functions](https://duckdb.org/docs/current/sql/functions/date.html)
