# Referential Integrity

Detect orphan foreign keys in fact or staging tables that do not exist in the parent dimension.

## Purpose

List rows where a foreign key has no matching parent record. **Zero rows means pass** for mandatory relationships.

## When to Use

- Before or after building `curated.fct_orders` from `staging.stg_orders` + `curated.dim_customers`
- When `staging.stg_orders.customer_id` must exist in `staging.stg_customers`
- After incremental loads — new orders should not reference missing customers
- Optional: spatial FK-style checks (e.g. `parcel_id` in attributes vs `curated.geo_parcels`)

## SQL Template

Orphan foreign keys (anti-join):

```sql
SELECT
  o.order_id,
  o.customer_id,
  o.order_date,
  o.amount
FROM staging.stg_orders o
LEFT JOIN curated.dim_customers d
  ON o.customer_id = d.customer_id
WHERE d.customer_id IS NULL
  AND o.customer_id IS NOT NULL
ORDER BY o.order_id
LIMIT 100;
```

Fact table post-build audit:

```sql
SELECT
  f.order_id,
  f.customer_id
FROM curated.fct_orders f
LEFT JOIN curated.dim_customers d
  ON f.customer_id = d.customer_id
WHERE d.customer_id IS NULL;
```

Count-only scalar (for summary table):

```sql
SELECT COUNT(*) AS orphan_rows
FROM staging.stg_orders o
LEFT JOIN curated.dim_customers d ON o.customer_id = d.customer_id
WHERE d.customer_id IS NULL
  AND o.customer_id IS NOT NULL;
```

## Notebook Usage

```python
orphans = con.sql("""
  SELECT o.order_id, o.customer_id, o.order_date
  FROM staging.stg_orders o
  LEFT JOIN curated.dim_customers d ON o.customer_id = d.customer_id
  WHERE d.customer_id IS NULL
    AND o.customer_id IS NOT NULL
  LIMIT 100
""").df()

assert orphans.empty, f"Orphan customer_id rows: {len(orphans)}"
orphans
```

Build dimension before fact, then validate:

```python
# After curated.dim_customers and curated.fct_orders exist
con.sql("""
  SELECT COUNT(*) AS orphan_fact_rows
  FROM curated.fct_orders f
  LEFT JOIN curated.dim_customers d ON f.customer_id = d.customer_id
  WHERE d.customer_id IS NULL
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{child_table}` | `staging.stg_orders` | Holds foreign key |
| `{parent_table}` | `curated.dim_customers` | Reference table |
| `{fk_column}` | `customer_id` | Join column (same name both sides) |
| Relationship | mandatory vs optional | Optional FKs may allow orphans |
| `LIMIT` | `100` | Cap notebook listing |

## Expected Output

**On fail:**

| order_id | customer_id | order_date | amount |
|----------|-------------|------------|--------|
| ORD-3301 | C-9999 | 2024-05-10 | 88.50 |
| ORD-3308 | C-9999 | 2024-05-11 | 12.00 |

**On pass:** zero rows.

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| Zero orphan rows | **Pass** — all FKs resolve |
| Non-zero orphans | **Fail** — fix dimension, filter child rows, or document as known exceptions |
| Orphans with `NULL` FK | Out of scope — use [required field null check](required_field_null_check.md) |
| Inner join fact build dropped orphans | Orphan check on staging should run **before** fact build; fact check confirms build logic |

## Common Variations

### Staging-to-staging integrity

```sql
SELECT o.order_id, o.customer_id
FROM staging.stg_orders o
LEFT JOIN staging.stg_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
  AND o.customer_id IS NOT NULL;
```

### Composite foreign key

```sql
SELECT o.order_id, o.region_code, o.store_id
FROM staging.stg_orders o
LEFT JOIN curated.dim_stores s
  ON o.region_code = s.region_code
 AND o.store_id = s.store_id
WHERE s.store_id IS NULL;
```

### Optional relationship (report only, do not fail)

```sql
SELECT o.order_id, o.promo_code
FROM staging.stg_orders o
LEFT JOIN curated.dim_promotions p ON o.promo_code = p.promo_code
WHERE o.promo_code IS NOT NULL
  AND p.promo_code IS NULL;
```

### Referential integrity summary row

```sql
SELECT
  'referential_integrity' AS check_name,
  'staging.stg_orders → curated.dim_customers' AS relationship,
  COUNT(*) AS orphan_rows
FROM staging.stg_orders o
LEFT JOIN curated.dim_customers d ON o.customer_id = d.customer_id
WHERE d.customer_id IS NULL
  AND o.customer_id IS NOT NULL;
```

## How to Document Results

```text
Check: VAL-004 Referential integrity
Child: staging.stg_orders (customer_id)
Parent: curated.dim_customers (customer_id)
Result: FAIL — 2 orphan rows (C-9999)
Resolution: Added C-9999 to dim_customers from CRM export; re-ran PASS
```

Log orphan `customer_id` values and whether you extended the dimension or excluded orders. Add to [validation summary table](validation_summary_table.md).

## Related Pages

- [Primary key uniqueness](primary_key_uniqueness.md)
- [Required field null check](required_field_null_check.md)
- [Build fact table](../07_transformation/build_fact_table.md)
- [Build dimension table](../07_transformation/build_dimension_table.md)

Official reference: [DuckDB JOIN syntax](https://duckdb.org/docs/current/sql/query_syntax/from.html#joins)
