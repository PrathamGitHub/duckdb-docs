# Primary Key Uniqueness

Assert that business or surrogate keys are unique at the declared grain for each pipeline table.

## Purpose

Return duplicate key groups so you can block promotion to `curated` when grain is violated. **Zero rows means pass.**

## When to Use

- After ingest on `raw.raw_orders` — confirm `order_id` is unique before staging
- Before publishing `curated.dim_customers` — one row per `customer_id`
- After deduplication in `staging.stg_orders`
- On `curated.geo_parcels` — one row per `parcel_id`

## SQL Template

Single-column business key:

```sql
SELECT
  order_id,
  COUNT(*) AS row_count
FROM staging.stg_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, order_id;
```

Composite key:

```sql
SELECT
  customer_id,
  effective_date,
  COUNT(*) AS row_count
FROM curated.dim_customers
GROUP BY customer_id, effective_date
HAVING COUNT(*) > 1
ORDER BY row_count DESC;
```

Spatial curated layer:

```sql
SELECT
  parcel_id,
  COUNT(*) AS row_count
FROM curated.geo_parcels
GROUP BY parcel_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC;
```

Exclude null keys from uniqueness test:

```sql
SELECT
  customer_id,
  COUNT(*) AS row_count
FROM raw.raw_orders
WHERE customer_id IS NOT NULL
GROUP BY customer_id
HAVING COUNT(*) > 1;
```

## Notebook Usage

```python
dupes = con.sql("""
  SELECT order_id, COUNT(*) AS n
  FROM staging.stg_orders
  GROUP BY 1
  HAVING COUNT(*) > 1
  ORDER BY n DESC
  LIMIT 50
""").df()

assert dupes.empty, f"Duplicate order_id values found: {len(dupes)} key groups"
dupes  # empty DataFrame on pass
```

Dimension check:

```python
con.sql("""
  SELECT customer_id, COUNT(*) AS n
  FROM curated.dim_customers
  GROUP BY 1
  HAVING COUNT(*) > 1
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Table under test |
| Key column(s) | `order_id`, `(customer_id, effective_date)` | Declared grain |
| `HAVING` threshold | `COUNT(*) > 1` | Duplicates only |
| Null handling | `WHERE key IS NOT NULL` | Optional scope |

## Expected Output

**On fail:**

| order_id | row_count |
|----------|-----------|
| ORD-0042 | 3 |
| ORD-1099 | 2 |

**On pass:** zero rows (empty result set).

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero rows | **Pass** — key is unique at tested grain |
| One or more rows | **Fail** — each row is a duplicate key group; `row_count` is total copies |
| Duplicates only on null key | Treat separately with [required field null check](required_field_null_check.md) |

## Common Variations

### Surrogate key after `ROW_NUMBER()` dedupe audit

```sql
SELECT surrogate_customer_id, COUNT(*) AS n
FROM curated.dim_customers
GROUP BY 1
HAVING COUNT(*) > 1;
```

### Soft-delete scope (active rows only)

```sql
SELECT customer_id, COUNT(*) AS n
FROM curated.dim_customers
WHERE is_active = TRUE
GROUP BY 1
HAVING COUNT(*) > 1;
```

### Full-row duplicate (all columns)

```sql
SELECT *
FROM (
  SELECT
    *,
    COUNT(*) OVER (
      PARTITION BY order_id, customer_id, order_date, amount, order_status
    ) AS dup_count
  FROM raw.raw_orders
) d
WHERE dup_count > 1
LIMIT 50;
```

### Quick pass/fail scalar for summary table

```sql
SELECT
  'primary_key_uniqueness' AS check_name,
  'staging.stg_orders' AS table_name,
  'order_id' AS key_columns,
  COUNT(*) AS duplicate_key_groups
FROM (
  SELECT order_id
  FROM staging.stg_orders
  GROUP BY 1
  HAVING COUNT(*) > 1
) dup;
```

`duplicate_key_groups = 0` → pass.

## How to Document Results

```text
Check: VAL-002 Primary key uniqueness
Table: staging.stg_orders
Key: order_id
Result: PASS (0 duplicate groups)
Run: 2025-06-25T14:32:00Z
```

On fail, attach a sample of violating keys (first 20 rows) and link to deduplication in `staging`. Append outcome to [validation summary table](validation_summary_table.md).

## Related Pages

- [Required field null check](required_field_null_check.md)
- [Referential integrity](referential_integrity.md)
- [Duplicate check (EDA)](../04_eda/duplicate_check.md)
- [Build dimension table](../07_transformation/build_dimension_table.md)

Official reference: [DuckDB GROUP BY / HAVING](https://duckdb.org/docs/current/sql/query_syntax/groupby.html)
