# Build Fact Table

Create `curated.fct_*` tables at event or transaction grain from `staging.stg_*` joined to `curated.dim_*`.

## Purpose

Materialize one row per business event (order, payment, observation) with foreign keys to dimensions and additive measures ready for [aggregations](aggregations.md) and [mart builds](aggregations.md).

## When to Use

- Promoting `staging.stg_orders` + `curated.dim_customers` → `curated.fct_orders`
- After [joins](joins.md) and [window functions](window_functions.md) enrichment
- Before `curated.mart_monthly_sales` and export to `output`
- Transaction-level spatial facts (permit issued, inspection event) with `geom` optional

## SQL Template

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  o.order_id,
  o.order_date,
  DATE_TRUNC('month', o.order_date) AS order_month,
  o.order_status,
  o.amount,
  o.quantity,
  d.customer_sk,
  o.customer_id,
  d.customer_name,
  d.customer_segment,
  d.region,
  CASE WHEN o.amount >= 100 THEN TRUE ELSE FALSE END AS is_high_value_order,
  CURRENT_TIMESTAMP AS fact_loaded_at
FROM staging.stg_orders o
INNER JOIN curated.dim_customers d
  ON o.customer_id = d.customer_id
WHERE o.order_status NOT IN ('cancelled', 'void')
  AND o.amount IS NOT NULL
  AND o.order_date IS NOT NULL;
```

Left join with unknown dimension member:

```sql
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  o.order_id,
  o.order_date,
  o.amount,
  COALESCE(d.customer_sk, MD5('UNKNOWN')) AS customer_sk,
  o.customer_id,
  COALESCE(d.customer_name, 'Unknown Customer') AS customer_name,
  d.region
FROM staging.stg_orders o
LEFT JOIN curated.dim_customers d
  ON o.customer_id = d.customer_id
WHERE o.order_status NOT IN ('cancelled', 'void');
```

Degenerate dimensions (attributes stay on fact when no separate dim):

```sql
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  order_id,
  order_date,
  amount,
  order_status,  -- degenerate — not worth a dim table
  customer_id
FROM staging.stg_orders
WHERE order_status NOT IN ('cancelled', 'void');
```

## Notebook Usage

```python
# Dimension first (see build_dimension_table.md)
con.execute("""
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM (VALUES
  ('C-100', 'Acme Corp', 'enterprise', 'west', TRUE, TIMESTAMP '2024-06-01'),
  ('C-101', 'Beta LLC', 'smb', 'east', TRUE, TIMESTAMP '2024-01-15')
) AS t(customer_id, customer_name, customer_segment, region, is_active, updated_at);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.dim_customers AS
SELECT
  MD5(customer_id::VARCHAR) AS customer_sk,
  customer_id, customer_name, customer_segment, region, is_active
FROM staging.stg_customers;
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 150.0, 2, 'shipped'),
  ('ORD-002', 'C-101', DATE '2024-02-01', 75.0, 1, 'shipped'),
  ('ORD-003', 'C-999', DATE '2024-02-05', 25.0, 1, 'shipped'),
  ('ORD-004', 'C-100', DATE '2024-01-20', 200.0, 1, 'cancelled')
) AS t(order_id, customer_id, order_date, amount, quantity, order_status);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  o.order_id,
  o.order_date,
  o.amount,
  o.quantity,
  d.customer_sk,
  o.customer_id,
  d.customer_name,
  d.region,
  o.order_status
FROM staging.stg_orders o
INNER JOIN curated.dim_customers d ON o.customer_id = d.customer_id
WHERE o.order_status NOT IN ('cancelled', 'void');
""")

con.sql("SELECT * FROM curated.fct_orders ORDER BY order_date").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{stg_fact_source}` | `staging.stg_orders` | Event-level staging |
| `{dim_table}` | `curated.dim_customers` | Conformed dimension |
| `{fct_table}` | `curated.fct_orders` | Output fact table |
| Grain key | `order_id` | One row per … |
| FK join | `o.customer_id = d.customer_id` | Natural key to dimension |
| Exclusions | `cancelled`, `void` | Business filters |
| Measures | `amount`, `quantity` | Additive numeric facts |

## Input Table Pattern

**Staging fact source:** `staging.stg_orders`

| order_id | customer_id | order_date | amount | quantity | order_status |
|----------|-------------|------------|--------|----------|--------------|
| ORD-001 | C-100 | 2024-01-15 | 150.0 | 2 | shipped |
| ORD-004 | C-100 | 2024-01-20 | 200.0 | 1 | cancelled |

**Dimension:** `curated.dim_customers`

| customer_sk | customer_id | customer_name | region |
|-------------|-------------|---------------|--------|
| … | C-100 | Acme Corp | west |
| … | C-101 | Beta LLC | east |

## Output Table Pattern

```text
curated.fct_<entity>
```

Example: **`curated.fct_orders`** — one row per shipped order

| order_id | order_date | amount | quantity | customer_sk | customer_id | customer_name | region | order_status |
|----------|------------|--------|----------|-------------|-------------|---------------|--------|--------------|
| ORD-001 | 2024-01-15 | 150.0 | 2 | … | C-100 | Acme Corp | west | shipped |
| ORD-002 | 2024-02-01 | 75.0 | 1 | … | C-101 | Beta LLC | east | shipped |

## Validation Checks

```sql
-- Grain: one row per order_id
SELECT order_id, COUNT(*) AS n
FROM curated.fct_orders
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Orphan keys (inner join should return zero)
SELECT o.order_id, o.customer_id
FROM staging.stg_orders o
LEFT JOIN curated.dim_customers d ON o.customer_id = d.customer_id
WHERE d.customer_id IS NULL
  AND o.order_status NOT IN ('cancelled', 'void');
```

```sql
-- Revenue reconciliation with staging
SELECT
  (SELECT SUM(amount) FROM staging.stg_orders
   WHERE order_status NOT IN ('cancelled', 'void')
     AND customer_id IN (SELECT customer_id FROM curated.dim_customers)) AS stg_expected,
  (SELECT SUM(amount) FROM curated.fct_orders) AS fct_total;
```

```sql
-- No null measures on required facts
SELECT COUNT(*) AS null_amount_rows
FROM curated.fct_orders
WHERE amount IS NULL;
```

```sql
-- Cancelled orders excluded
SELECT COUNT(*) AS cancelled_in_fact
FROM curated.fct_orders
WHERE order_status IN ('cancelled', 'void');
```

## Common Variations

### Factless fact (event flag only)

```sql
CREATE OR REPLACE TABLE curated.fct_customer_signups AS
SELECT
  customer_id,
  signup_date,
  customer_sk
FROM staging.stg_customers
WHERE signup_date IS NOT NULL;
```

### Snapshot fact (periodic inventory)

```sql
CREATE OR REPLACE TABLE curated.fct_inventory_daily AS
SELECT
  snapshot_date,
  product_id,
  quantity_on_hand
FROM staging.stg_inventory_snapshots;
```

### Spatial fact with geometry

```sql
CREATE OR REPLACE TABLE curated.fct_inspections AS
SELECT
  i.inspection_id,
  i.inspection_date,
  p.parcel_id,
  p.geom
FROM staging.stg_inspections i
INNER JOIN curated.dim_parcels p ON i.parcel_id = p.parcel_id;
```

### Include [window functions](window_functions.md) on build

```sql
ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS customer_order_sequence
```

## Performance Notes

- Build `curated.dim_*` before facts — dimension is smaller and reused.
- Filter staging (`order_status`, date range) before joining to dimension.
- Project only needed dimension columns — avoid wide dimension `SELECT *`.
- Full `CREATE OR REPLACE` is fine for moderate data; switch to [incremental load](incremental_load_pattern.md) for append-only events.
- Pre-aggregate to marts from facts, not from staging, for consistent metrics.

## Known Limitations

- Inner join drops facts with missing dimensions — choose `LEFT JOIN` + unknown member when orphans must be retained.
- Denormalizing dimension attributes onto facts (customer_name) is Type 1 — values do not auto-update on dimension reload unless fact is rebuilt.
- Semi-additive facts (balances) cannot be summed across time without careful logic.
- Cancelled/excluded rows need explicit reconciliation against staging counts.

## Related Pages

- [Build dimension table](build_dimension_table.md)
- [Joins](joins.md)
- [Aggregations](aggregations.md)
- [Incremental load pattern](incremental_load_pattern.md)

Official reference: [SELECT statement](https://duckdb.org/docs/current/sql/query_syntax/select.html)
