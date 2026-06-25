# Category Domain Check

Assert categorical column values belong to an allowed set of codes or labels.

## Purpose

Return rows with invalid enum-like values (bad `order_status`, unknown `region_code`, invalid land-use codes). **Zero rows means pass.**

## When to Use

- On `staging.stg_orders` — `order_status` in (`pending`, `shipped`, `cancelled`, `returned`)
- On `curated.dim_customers` — `customer_tier` in (`bronze`, `silver`, `gold`)
- After decoding GDB domain fields into `staging.stg_parcels`
- Before export when downstream tools expect fixed code lists

## SQL Template

Inline allowed values:

```sql
SELECT
  order_id,
  order_status
FROM staging.stg_orders
WHERE order_status IS NOT NULL
  AND order_status NOT IN ('pending', 'shipped', 'cancelled', 'returned')
ORDER BY order_status, order_id
LIMIT 100;
```

Case-insensitive match:

```sql
SELECT
  order_id,
  order_status
FROM staging.stg_orders
WHERE order_status IS NOT NULL
  AND UPPER(TRIM(order_status)) NOT IN (
    'PENDING', 'SHIPPED', 'CANCELLED', 'RETURNED'
  );
```

Reference lookup table:

```sql
SELECT
  o.order_id,
  o.region_code
FROM staging.stg_orders o
LEFT JOIN curated.dim_regions r ON o.region_code = r.region_code
WHERE o.region_code IS NOT NULL
  AND r.region_code IS NULL;
```

Land-use domain on parcels:

```sql
SELECT
  parcel_id,
  land_use_code
FROM curated.geo_parcels
WHERE land_use_code IS NOT NULL
  AND land_use_code NOT IN ('RES', 'COM', 'IND', 'AGR', 'PUB', 'UNK');
```

## Notebook Usage

```python
invalid_status = con.sql("""
  SELECT order_id, order_status
  FROM staging.stg_orders
  WHERE order_status IS NOT NULL
    AND order_status NOT IN ('pending', 'shipped', 'cancelled', 'returned')
  LIMIT 50
""").df()

assert invalid_status.empty, f"Invalid order_status values: {len(invalid_status)}"
invalid_status
```

Discover unexpected values (diagnostic before locking domain):

```python
con.sql("""
  SELECT order_status, COUNT(*) AS n
  FROM staging.stg_orders
  GROUP BY 1
  ORDER BY n DESC
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Table under test |
| Column | `order_status`, `land_use_code` | Categorical field |
| Allowed values | `IN ('pending', 'shipped', ...)` | Inline or lookup table |
| Case rule | `UPPER(TRIM(col))` | Normalize before compare |
| `NULL` | Excluded from check | Use [required field null check](required_field_null_check.md) if disallowed |

## Expected Output

**On fail:**

| order_id | order_status |
|----------|--------------|
| ORD-4410 | SHIPED |
| ORD-5522 | unknown |

**On pass:** zero rows.

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero rows | **Pass** — all values in allowed domain |
| Typos (`SHIPED`) | **Fail** — fix in `staging` text cleaning |
| New legitimate code | **Fail** until domain list updated — version your allowed set |
| `NULL` when optional | OK if excluded from `WHERE` |

## Common Variations

### Allowed values from seed table

```sql
CREATE OR REPLACE TABLE staging.ref_order_status AS
SELECT * FROM (VALUES
  ('pending'), ('shipped'), ('cancelled'), ('returned')
) AS t(order_status);

SELECT o.order_id, o.order_status
FROM staging.stg_orders o
LEFT JOIN staging.ref_order_status r ON o.order_status = r.order_status
WHERE o.order_status IS NOT NULL
  AND r.order_status IS NULL;
```

### Multi-column domain (status + reason)

```sql
SELECT order_id, order_status, cancel_reason
FROM staging.stg_orders
WHERE order_status = 'cancelled'
  AND cancel_reason NOT IN ('customer_request', 'fraud', 'out_of_stock', 'other');
```

### Customer tier on dimension

```sql
SELECT customer_id, customer_tier
FROM curated.dim_customers
WHERE customer_tier IS NOT NULL
  AND customer_tier NOT IN ('bronze', 'silver', 'gold');
```

### Scalar for summary table

```sql
SELECT
  'category_domain_check' AS check_name,
  'staging.stg_orders.order_status' AS field,
  COUNT(*) AS violating_rows
FROM staging.stg_orders
WHERE order_status IS NOT NULL
  AND order_status NOT IN ('pending', 'shipped', 'cancelled', 'returned');
```

## How to Document Results

```text
Check: VAL-006 Category domain check
Field: staging.stg_orders.order_status
Allowed: pending, shipped, cancelled, returned
Result: FAIL — 2 rows (typo SHIPED)
Action: TRIM + dictionary map in staging; re-run PASS
```

Maintain allowed-value lists in `staging.ref_*` tables or project YAML. Record domain version in [validation summary table](validation_summary_table.md).

## Related Pages

- [Value range check](value_range_check.md)
- [Required field null check](required_field_null_check.md)
- [Categorical frequency (EDA)](../04_eda/categorical_frequency.md)
- [Text cleaning](../06_cleaning/text_cleaning.md)

Official reference: [DuckDB IN operator](https://duckdb.org/docs/current/sql/expressions/in.html)
