# Joins

Combine `staging.stg_*` tables on explicit keys while preserving declared grain.

## Purpose

Attach customer attributes to orders, link facts to dimensions, or merge spatial layers — with join type and cardinality documented for downstream `curated` models.

## When to Use

- Enriching `staging.stg_orders` with `staging.stg_customers` before `curated.fct_orders`
- Anti-joins to find orders without matching customers (data quality)
- Preparing join keys for [build fact table](build_fact_table.md) and [build dimension table](build_dimension_table.md)
- Spatial attribute joins (point-in-polygon) after geometry is cleaned in `staging`

## SQL Template

Inner join — keep orders with known customers:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_name,
  c.customer_segment,
  c.region,
  o.order_date,
  o.amount,
  o.order_status
FROM staging.stg_orders o
INNER JOIN staging.stg_customers c
  ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('cancelled', 'void');
```

Left join — retain all orders, flag missing customers:

```sql
CREATE OR REPLACE TABLE staging.stg_orders_with_customer AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_name,
  c.customer_segment,
  c.region,
  o.order_date,
  o.amount,
  o.order_status,
  c.customer_id IS NULL AS is_orphan_customer
FROM staging.stg_orders o
LEFT JOIN staging.stg_customers c
  ON o.customer_id = c.customer_id;
```

Anti-join — orders with no customer match:

```sql
SELECT o.order_id, o.customer_id, o.order_date, o.amount
FROM staging.stg_orders o
LEFT JOIN staging.stg_customers c
  ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
```

Multi-table join with deduplicated dimension:

```sql
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_name,
  r.region_name,
  o.order_date,
  o.amount
FROM staging.stg_orders o
INNER JOIN (
  SELECT customer_id, customer_name, region
  FROM staging.stg_customers
  QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) = 1
) c ON o.customer_id = c.customer_id
LEFT JOIN staging.stg_regions r
  ON c.region = r.region_code;
```

## Notebook Usage

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM (VALUES
  ('C-100', 'Acme Corp', 'enterprise', 'west'),
  ('C-101', 'Beta LLC', 'smb', 'east')
) AS t(customer_id, customer_name, customer_segment, region);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 150.0, 'shipped'),
  ('ORD-002', 'C-101', DATE '2024-01-20', 50.0, 'pending'),
  ('ORD-003', 'C-999', DATE '2024-01-22', 25.0, 'shipped')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT o.order_id, o.customer_id, c.customer_name, o.order_date, o.amount
FROM staging.stg_orders o
INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id;
""")

# Orphan check
con.sql("""
  SELECT o.order_id, o.customer_id
  FROM staging.stg_orders o
  LEFT JOIN staging.stg_customers c ON o.customer_id = c.customer_id
  WHERE c.customer_id IS NULL
""").df()
```

Real-world join practice — population by country metadata:

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
WHERE TRY_CAST(year AS INTEGER) = 2020;
""")

con.execute("""
CREATE OR REPLACE TABLE raw.raw_country_codes AS
SELECT * FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/country-codes/master/data/country-codes.csv'
);
""")

con.sql("""
  SELECT p.country_name, p.population, cc.'ISO3166-1-Alpha-3' AS iso3
  FROM staging.stg_population p
  LEFT JOIN raw.raw_country_codes cc
    ON LOWER(p.country_name) = LOWER(cc.'CLDR display name')
  ORDER BY p.population DESC
  LIMIT 10
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{left_table}` | `staging.stg_orders` | Driving table (preserve its grain) |
| `{right_table}` | `staging.stg_customers` | Lookup / dimension table |
| `{join_key}` | `customer_id` | Single or composite keys |
| `{join_type}` | `INNER` / `LEFT` / `FULL` | Document cardinality impact |
| `{output_table}` | `curated.fct_orders` | Materialized join result |
| Extra predicates | `o.order_date >= DATE '2024-01-01'` | Filter before or after join |

## Input Table Pattern

```text
staging.stg_<entity>
```

Left (fact-like): **`staging.stg_orders`**

| order_id | customer_id | order_date | amount |
|----------|-------------|------------|--------|
| ORD-001 | C-100 | 2024-01-15 | 150.0 |
| ORD-003 | C-999 | 2024-01-22 | 25.0 |

Right (dimension-like): **`staging.stg_customers`**

| customer_id | customer_name | region |
|-------------|---------------|--------|
| C-100 | Acme Corp | west |
| C-101 | Beta LLC | east |

## Output Table Pattern

```text
staging.stg_<entity>_<qualifier>   -- join enrichment in staging
curated.fct_<entity>               -- stg_* + dim attributes at fact grain
```

Example: **`curated.fct_orders`** — one row per order (inner join drops ORD-003)

| order_id | customer_id | customer_name | order_date | amount |
|----------|-------------|---------------|------------|--------|
| ORD-001 | C-100 | Acme Corp | 2024-01-15 | 150.0 |
| ORD-002 | C-101 | Beta LLC | 2024-01-20 | 50.0 |

## Validation Checks

```sql
-- Row count vs join type expectation
SELECT
  (SELECT COUNT(*) FROM staging.stg_orders) AS orders_total,
  (SELECT COUNT(*) FROM curated.fct_orders) AS fct_rows;
-- INNER: fct_rows <= orders_total; LEFT: fct_rows = orders_total
```

```sql
-- Duplicate key explosion check on right table
SELECT customer_id, COUNT(*) AS n
FROM staging.stg_customers
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Orphan foreign keys
SELECT o.customer_id, COUNT(*) AS orphan_orders
FROM staging.stg_orders o
LEFT JOIN staging.stg_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
GROUP BY 1;
```

```sql
-- Reconcile sum of amounts before/after inner join
SELECT
  (SELECT SUM(amount) FROM staging.stg_orders o
   INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id) AS joined_sum,
  (SELECT SUM(amount) FROM curated.fct_orders) AS fct_sum;
```

## Common Variations

### `USING` for same-named keys

```sql
SELECT o.order_id, o.order_date, c.customer_name
FROM staging.stg_orders o
INNER JOIN staging.stg_customers c USING (customer_id);
```

### Composite join keys

```sql
ON o.customer_id = c.customer_id AND o.order_date >= c.effective_from
```

### `ASOF` join (temporal nearest match)

```sql
SELECT o.order_id, o.order_date, p.price
FROM staging.stg_orders o
ASOF JOIN staging.stg_prices p
  ON o.product_id = p.product_id AND o.order_date >= p.valid_from;
```

### Cross join for calendar spine

```sql
SELECT c.customer_id, d.calendar_date
FROM staging.stg_customers c
CROSS JOIN staging.stg_calendar d
WHERE d.calendar_date BETWEEN DATE '2024-01-01' AND DATE '2024-12-31';
```

### Spatial join

```sql
SELECT s.stop_id, z.zone_code
FROM staging.stg_bus_stops s
INNER JOIN staging.stg_zoning z
  ON ST_Within(s.geom, z.geom);
```

## Performance Notes

- Pre-filter both tables before joining — smaller hash tables build faster.
- Deduplicate the right table (`QUALIFY ROW_NUMBER() ... = 1`) before join to prevent row explosion.
- Join on typed, trimmed keys — avoid `TRIM()` on both sides in the join condition if you can clean in `staging` first.
- For repeated joins, build `curated.dim_*` once and reuse.
- `EXPLAIN` large joins; DuckDB uses hash joins by default for equi-joins.

## Known Limitations

- Inner joins silently drop unmatched rows — run orphan checks when business rules require retention.
- Many-to-many joins without bridge tables inflate row counts — validate grain after every join.
- Fuzzy text joins (`LIKE`, `SOUNDEX`) are slow and ambiguous — prefer conformed keys in `staging`.
- Spatial joins without spatial indexes can be expensive on large layers — filter by bbox first.

## Related Pages

- [CTE pipeline](cte_pipeline.md)
- [Build dimension table](build_dimension_table.md)
- [Build fact table](build_fact_table.md)
- [Deduplication](../06_cleaning/deduplication.md)

Official reference: [Joins](https://duckdb.org/docs/current/sql/query_syntax/from.html#joins)
