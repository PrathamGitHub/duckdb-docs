# Required Field Null Check

Fail when columns that must be populated contain `NULL` or empty strings.

## Purpose

List rows where required fields are missing so you can quarantine or fix them before `curated` models and exports. **Zero rows means pass.**

## When to Use

- After cleaning `staging.stg_orders` — `order_id`, `customer_id`, `order_date`, `amount` required
- Before `curated.fct_orders` build — no null foreign keys
- On `curated.dim_customers` — `customer_id`, `customer_name` required
- On `curated.geo_parcels` — `parcel_id` and `geom` required for spatial delivery

## SQL Template

Single required column:

```sql
SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  order_status
FROM staging.stg_orders
WHERE order_id IS NULL;
```

Multiple required columns (any violation):

```sql
SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  CASE
    WHEN order_id IS NULL THEN 'order_id'
    WHEN customer_id IS NULL THEN 'customer_id'
    WHEN order_date IS NULL THEN 'order_date'
    WHEN amount IS NULL THEN 'amount'
  END AS first_null_field
FROM staging.stg_orders
WHERE order_id IS NULL
   OR customer_id IS NULL
   OR order_date IS NULL
   OR amount IS NULL
LIMIT 100;
```

Treat empty string as null for text fields:

```sql
SELECT *
FROM curated.dim_customers
WHERE customer_id IS NULL
   OR NULLIF(TRIM(customer_name), '') IS NULL;
```

Spatial required geometry:

```sql
SELECT
  parcel_id,
  owner_name
FROM curated.geo_parcels
WHERE parcel_id IS NULL
   OR geom IS NULL
   OR ST_IsEmpty(geom);
```

## Notebook Usage

```python
violations = con.sql("""
  SELECT *
  FROM staging.stg_orders
  WHERE order_id IS NULL
     OR customer_id IS NULL
     OR order_date IS NULL
     OR amount IS NULL
  LIMIT 100
""").df()

assert violations.empty, f"Required field nulls: {len(violations)} rows (capped at 100)"
violations
```

Per-column null summary (diagnostic, not pass/fail gate):

```python
con.sql("""
  SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
    COUNT(*) FILTER (WHERE order_date IS NULL) AS null_order_date,
    COUNT(*) FILTER (WHERE amount IS NULL) AS null_amount,
    COUNT(*) AS total_rows
  FROM staging.stg_orders
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Layer under test |
| Required columns | `order_id`, `customer_id`, `geom` | Project-specific list |
| Empty-string rule | `NULLIF(TRIM(col), '')` | Text fields |
| `LIMIT` | `100` | Cap listing in notebooks |

## Expected Output

**On fail:**

| order_id | customer_id | order_date | amount | first_null_field |
|----------|-------------|------------|--------|------------------|
| NULL | C-1001 | 2024-03-01 | 49.99 | order_id |
| ORD-2200 | NULL | 2024-03-02 | 12.00 | customer_id |

**On pass:** zero rows.

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero rows | **Pass** — all required fields populated |
| Non-zero rows | **Fail** — each row is a record to fix or exclude |
| High null rate on one column | Source or cast issue — fix in `staging` before re-run |

Conditional requiredness (e.g. `ship_date` required when `order_status = 'shipped'`) uses a filtered `WHERE` clause — document the rule in your validation log.

## Common Variations

### Conditional required field

```sql
SELECT order_id, order_status, ship_date
FROM staging.stg_orders
WHERE order_status = 'shipped'
  AND ship_date IS NULL;
```

### Required fields after safe cast

```sql
SELECT *
FROM staging.stg_orders
WHERE TRY_CAST(amount AS DOUBLE) IS NULL
  AND amount IS NOT NULL;  -- cast failure, not source null
```

### Scalar summary for validation suite

```sql
SELECT
  'required_field_null_check' AS check_name,
  'staging.stg_orders' AS table_name,
  COUNT(*) AS violating_rows
FROM staging.stg_orders
WHERE order_id IS NULL
   OR customer_id IS NULL
   OR order_date IS NULL
   OR amount IS NULL;
```

`violating_rows = 0` → pass.

### Fact table foreign keys

```sql
SELECT *
FROM curated.fct_orders
WHERE customer_id IS NULL
   OR order_date IS NULL
   OR amount IS NULL;
```

## How to Document Results

```text
Check: VAL-003 Required field null check
Table: staging.stg_orders
Required: order_id, customer_id, order_date, amount
Result: FAIL — 3 rows (see violations_sample.parquet)
Action: Filter null customer_id in staging; re-ingest raw batch 2024-03-02
```

Save violating rows to `data/output/validation/required_null_violations.parquet` when failing. Register in [validation summary table](validation_summary_table.md).

## Related Pages

- [Primary key uniqueness](primary_key_uniqueness.md)
- [Referential integrity](referential_integrity.md)
- [Null profile (EDA)](../04_eda/null_profile.md)
- [Missing values (cleaning)](../06_cleaning/missing_values.md)

Official reference: [DuckDB NULL handling](https://duckdb.org/docs/current/sql/expressions/is_null.html)
