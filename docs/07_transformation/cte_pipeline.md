# CTE Pipeline

Build readable multi-step transforms with chained Common Table Expressions (CTEs) in `staging` or `curated`.

## Purpose

Break complex logic into named, ordered steps so notebooks and SQL templates stay auditable. Each CTE is one transformation (filter, join, derive) before materializing the final table.

## When to Use

- A single `SELECT` would exceed ~30 lines or mix unrelated steps
- You need intermediate checkpoints for validation between steps
- Building `staging.stg_*` enrichments before `curated.dim_*` or `curated.fct_*`
- Teaching or documenting a pipeline — CTE names act as inline comments

## SQL Template

Enrich orders with customer attributes and order-level metrics:

```sql
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.fct_orders AS
WITH
  orders AS (
    SELECT
      order_id,
      customer_id,
      order_date,
      amount,
      order_status
    FROM staging.stg_orders
    WHERE order_status NOT IN ('cancelled', 'void')
  ),
  customers AS (
    SELECT
      customer_id,
      customer_name,
      customer_segment,
      region
    FROM staging.stg_customers
    WHERE is_active = TRUE
  ),
  joined AS (
    SELECT
      o.order_id,
      o.customer_id,
      c.customer_name,
      c.customer_segment,
      c.region,
      o.order_date,
      o.amount,
      o.order_status,
      DATE_TRUNC('month', o.order_date) AS order_month
    FROM orders o
    INNER JOIN customers c ON o.customer_id = c.customer_id
  ),
  with_metrics AS (
    SELECT
      *,
      amount >= 100 AS is_high_value_order,
      ROW_NUMBER() OVER (
        PARTITION BY customer_id ORDER BY order_date
      ) AS customer_order_sequence
    FROM joined
  )
SELECT
  order_id,
  customer_id,
  customer_name,
  customer_segment,
  region,
  order_date,
  order_month,
  amount,
  order_status,
  is_high_value_order,
  customer_order_sequence
FROM with_metrics;
```

Intermediate staging build (CTE stops before `curated`):

```sql
CREATE OR REPLACE TABLE staging.stg_orders_enriched AS
WITH base AS (
  SELECT * FROM staging.stg_orders WHERE amount > 0
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
  FROM base
)
SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  order_status
FROM ranked
WHERE rn <= 5;  -- latest five orders per customer
```

## Notebook Usage

Bootstrap sample staging tables, then run the CTE pipeline:

```python
# After notebook setup cell (see docs/01_setup/notebook_setup_cell.md)
con.execute("""
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM (VALUES
  ('C-100', 'Acme Corp', 'enterprise', 'west', TRUE),
  ('C-101', 'Beta LLC', 'smb', 'east', TRUE),
  ('C-102', 'Gamma Inc', 'smb', 'west', FALSE)
) AS t(customer_id, customer_name, customer_segment, region, is_active);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 150.0, 'shipped'),
  ('ORD-002', 'C-100', DATE '2024-02-01', 75.0, 'shipped'),
  ('ORD-003', 'C-101', DATE '2024-01-20', 50.0, 'pending'),
  ('ORD-004', 'C-102', DATE '2024-01-25', 200.0, 'cancelled')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute(open("templates/sql/transformation/cte_pipeline.sql").read())  # when template exists
# Or paste the CREATE OR REPLACE TABLE ... WITH ... SQL above
con.sql("SELECT * FROM curated.fct_orders ORDER BY order_date").df()
```

Optional: materialize each CTE for debugging:

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders_debug_joined AS
WITH orders AS (SELECT * FROM staging.stg_orders WHERE order_status != 'cancelled'),
     customers AS (SELECT * FROM staging.stg_customers WHERE is_active)
SELECT o.*, c.customer_name
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id;
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{source_stg_table}` | `staging.stg_orders` | Primary input |
| `{lookup_stg_table}` | `staging.stg_customers` | Join or lookup input |
| `{output_table}` | `curated.fct_orders` | Final `CREATE TABLE AS` target |
| CTE names | `orders`, `joined`, `with_metrics` | Rename to match your domain |
| Filter predicates | `order_status NOT IN (...)` | Business exclusions per step |
| Output grain | one row per `order_id` | Document in notebook header |

## Input Table Pattern

```text
staging.stg_<entity>
```

Example inputs:

**`staging.stg_orders`** — one row per order

| order_id | customer_id | order_date | amount | order_status |
|----------|-------------|------------|--------|--------------|
| ORD-001 | C-100 | 2024-01-15 | 150.0 | shipped |
| ORD-004 | C-102 | 2024-01-25 | 200.0 | cancelled |

**`staging.stg_customers`** — one row per customer

| customer_id | customer_name | customer_segment | region | is_active |
|-------------|---------------|------------------|--------|-----------|
| C-100 | Acme Corp | enterprise | west | true |
| C-102 | Gamma Inc | smb | west | false |

## Output Table Pattern

```text
staging.stg_<entity>_<qualifier>   -- intermediate enrichments
curated.fct_<entity>                -- fact grain
curated.dim_<entity>              -- dimension grain
```

Example: **`curated.fct_orders`** — one row per shipped/pending order with customer attributes

| order_id | customer_id | customer_name | order_month | amount | is_high_value_order |
|----------|-------------|---------------|-------------|--------|---------------------|
| ORD-001 | C-100 | Acme Corp | 2024-01-01 | 150.0 | true |
| ORD-002 | C-100 | Acme Corp | 2024-02-01 | 75.0 | false |

## Validation Checks

```sql
-- Output row count vs filtered source
SELECT
  (SELECT COUNT(*) FROM staging.stg_orders
   WHERE order_status NOT IN ('cancelled', 'void')) AS expected_orders,
  (SELECT COUNT(*) FROM curated.fct_orders) AS fct_rows;
```

```sql
-- No orphan customer keys after inner join
SELECT o.customer_id, COUNT(*) AS n
FROM staging.stg_orders o
LEFT JOIN staging.stg_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
  AND o.order_status NOT IN ('cancelled', 'void')
GROUP BY 1;
```

```sql
-- Grain check: one row per order_id
SELECT order_id, COUNT(*) AS n
FROM curated.fct_orders
GROUP BY 1
HAVING COUNT(*) > 1;
```

## Common Variations

### CTE chain for dimension build (`stg_*` → `dim_*`)

```sql
CREATE OR REPLACE TABLE curated.dim_customers AS
WITH deduped AS (
  SELECT * FROM staging.stg_customers
  QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) = 1
),
enriched AS (
  SELECT
    customer_id,
    customer_name,
    customer_segment,
    region,
    is_active,
    MD5(customer_id::VARCHAR) AS customer_sk
  FROM deduped
)
SELECT * FROM enriched;
```

### Recursive CTE (hierarchy roll-up)

```sql
WITH RECURSIVE org_tree AS (
  SELECT employee_id, manager_id, employee_name, 1 AS depth
  FROM staging.stg_employees
  WHERE manager_id IS NULL
  UNION ALL
  SELECT e.employee_id, e.manager_id, e.employee_name, t.depth + 1
  FROM staging.stg_employees e
  INNER JOIN org_tree t ON e.manager_id = t.employee_id
)
SELECT * FROM org_tree;
```

### Persist audit CTE as staging table

```sql
CREATE OR REPLACE TABLE staging.stg_orders_excluded AS
SELECT * FROM staging.stg_orders WHERE order_status IN ('cancelled', 'void');
```

### Spatial CTE pipeline

```sql
WITH valid AS (
  SELECT parcel_id, ST_MakeValid(geom) AS geom
  FROM staging.stg_parcels
  WHERE geom IS NOT NULL
),
zoned AS (
  SELECT v.parcel_id, z.zone_code, v.geom
  FROM valid v
  INNER JOIN staging.stg_zoning z
    ON ST_Intersects(v.geom, z.geom)
)
SELECT * FROM zoned;
```

## Performance Notes

- DuckDB inlines CTEs into one plan — chained CTEs are usually not slower than nested subqueries.
- Materialize (`CREATE TABLE AS`) when the same CTE result is read many times or the chain is expensive (large spatial joins).
- Filter early in the first CTE to reduce rows passed downstream.
- Avoid `SELECT *` in production CTEs — project only needed columns to reduce memory.
- Use `EXPLAIN` on the final statement before running on full datasets.

## Known Limitations

- CTEs are not reusable across separate SQL files unless extracted to views or staging tables.
- Very deep CTE chains (10+ steps) are hard to debug — split into `staging.stg_*` checkpoints.
- `WITH RECURSIVE` depth limits depend on data; test on representative hierarchies.
- CTE names are not persisted — only the final `CREATE TABLE` output survives in the catalog.

## Related Pages

- [Joins](joins.md)
- [Window functions](window_functions.md)
- [Build fact table](build_fact_table.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [WITH clause (CTE)](https://duckdb.org/docs/current/sql/query_syntax/with.html)
