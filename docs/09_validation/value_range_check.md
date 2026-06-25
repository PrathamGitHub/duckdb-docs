# Value Range Check

Assert numeric and comparable columns fall within allowed minimum and maximum bounds.

## Purpose

Return rows with out-of-range values (negative amounts, impossible percentages, bad coordinates). **Zero rows means pass.**

## When to Use

- On `staging.stg_orders` — `amount > 0`, reasonable `quantity`
- On `curated.fct_orders` — revenue metrics within business caps
- On `curated.dim_customers` — `loyalty_points >= 0`
- On `curated.geo_parcels` — acreage or assessed value within expected bounds

## SQL Template

Numeric min/max on orders:

```sql
SELECT
  order_id,
  customer_id,
  amount,
  order_date
FROM staging.stg_orders
WHERE amount IS NOT NULL
  AND (amount < 0 OR amount > 100000)
ORDER BY amount DESC
LIMIT 100;
```

Multiple columns with violation reason:

```sql
SELECT
  order_id,
  amount,
  quantity,
  CASE
    WHEN amount < 0 THEN 'amount below minimum'
    WHEN amount > 100000 THEN 'amount above maximum'
    WHEN quantity < 1 THEN 'quantity below minimum'
    WHEN quantity > 1000 THEN 'quantity above maximum'
  END AS violation_reason
FROM staging.stg_orders
WHERE amount < 0 OR amount > 100000
   OR quantity < 1 OR quantity > 1000;
```

Latitude/longitude sanity on spatial attributes:

```sql
SELECT
  parcel_id,
  centroid_lat,
  centroid_lon
FROM curated.geo_parcels
WHERE centroid_lat IS NOT NULL
  AND (
    centroid_lat < -90 OR centroid_lat > 90
    OR centroid_lon < -180 OR centroid_lon > 180
  );
```

## Notebook Usage

```python
out_of_range = con.sql("""
  SELECT order_id, amount
  FROM staging.stg_orders
  WHERE amount IS NOT NULL
    AND (amount < 0 OR amount > 100000)
  ORDER BY amount DESC
  LIMIT 50
""").df()

assert out_of_range.empty, f"Out-of-range amounts: {len(out_of_range)} rows"
out_of_range
```

Parameterized check in notebook:

```python
MIN_AMOUNT = 0
MAX_AMOUNT = 100_000

con.sql(f"""
  SELECT COUNT(*) AS violations
  FROM staging.stg_orders
  WHERE amount IS NOT NULL
    AND (amount < {MIN_AMOUNT} OR amount > {MAX_AMOUNT})
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Table under test |
| Column | `amount`, `quantity`, `assessed_value` | Numeric or comparable |
| `{min_value}` | `0` | Lower bound (inclusive) |
| `{max_value}` | `100000` | Upper bound (inclusive) |
| `NULL` handling | `IS NOT NULL` filter | Nulls handled separately |

## Expected Output

**On fail:**

| order_id | amount | violation_reason |
|----------|--------|------------------|
| ORD-7712 | -15.00 | amount below minimum |
| ORD-8820 | 250000.00 | amount above maximum |

**On pass:** zero rows.

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero rows | **Pass** — all non-null values in range |
| Negative `amount` | **Fail** — data entry or sign convention error |
| Extreme high values | **Fail** — unit mismatch (cents vs dollars) or outlier |
| NULL values | Not evaluated — use [required field null check](required_field_null_check.md) if column is required |

## Common Variations

### Config-driven bounds table

```sql
CREATE OR REPLACE TABLE staging.validation_bounds AS
SELECT * FROM (VALUES
  ('staging.stg_orders', 'amount', 0.0, 100000.0),
  ('staging.stg_orders', 'quantity', 1.0, 1000.0)
) AS t(table_name, column_name, min_value, max_value);

-- Example: amount check driven by config (simplified)
SELECT o.order_id, o.amount, b.min_value, b.max_value
FROM staging.stg_orders o
CROSS JOIN staging.validation_bounds b
WHERE b.table_name = 'staging.stg_orders'
  AND b.column_name = 'amount'
  AND o.amount IS NOT NULL
  AND (o.amount < b.min_value OR o.amount > b.max_value);
```

### Percentage column (0–100)

```sql
SELECT customer_id, discount_pct
FROM curated.dim_customers
WHERE discount_pct IS NOT NULL
  AND (discount_pct < 0 OR discount_pct > 100);
```

### Fact table shipped revenue only

```sql
SELECT order_id, amount
FROM curated.fct_orders
WHERE order_status = 'shipped'
  AND (amount <= 0 OR amount > 50000);
```

### Scalar for summary table

```sql
SELECT
  'value_range_check' AS check_name,
  'staging.stg_orders.amount' AS field,
  COUNT(*) AS violating_rows
FROM staging.stg_orders
WHERE amount IS NOT NULL
  AND (amount < 0 OR amount > 100000);
```

## How to Document Results

```text
Check: VAL-005 Value range check
Field: staging.stg_orders.amount
Bounds: [0, 100000]
Result: FAIL — 1 row (ORD-7712, amount = -15.00)
Action: Absolute value fix applied in staging; re-run PASS
```

Record bound definitions in project config or `staging.validation_bounds`. Append to [validation summary table](validation_summary_table.md).

## Related Pages

- [Category domain check](category_domain_check.md)
- [Date range validation](date_range_validation.md)
- [Outlier scan (EDA)](../04_eda/outlier_scan.md)
- [Numeric summary (EDA)](../04_eda/numeric_summary.md)

Official reference: [DuckDB comparison operators](https://duckdb.org/docs/current/sql/expressions/comparison_operators.html)
