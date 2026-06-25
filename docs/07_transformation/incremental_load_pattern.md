# Incremental Load Pattern

Append or merge new `staging.stg_*` rows into `curated.fct_*`, `curated.dim_*`, or `curated.mart_*` without full table rebuilds.

## Purpose

Process only changed or new records on each notebook run — reducing runtime for growing order feeds, daily snapshots, and repeated mart refreshes.

## When to Use

- Daily or hourly appends to `staging.stg_orders` from [ingestion](../02_ingestion/csv.md)
- Rebuilding `curated.fct_orders` from a watermark (`order_date`, `ingest_ts`)
- Merging upserts into `curated.dim_customers` when attributes change
- Refreshing `curated.mart_monthly_sales` for recent months only

## SQL Template

### Append-only fact load (watermark on `order_date`)

```sql
CREATE SCHEMA IF NOT EXISTS curated;

-- Track high-water mark (table or notebook variable)
CREATE TABLE IF NOT EXISTS curated.etl_watermarks (
  pipeline_name VARCHAR PRIMARY KEY,
  watermark_value TIMESTAMP,
  updated_at TIMESTAMP
);

-- Initialize watermark if missing
INSERT INTO curated.etl_watermarks BY NAME
SELECT 'fct_orders', TIMESTAMP '1900-01-01', CURRENT_TIMESTAMP
WHERE NOT EXISTS (
  SELECT 1 FROM curated.etl_watermarks WHERE pipeline_name = 'fct_orders'
);

-- Incremental insert: new orders since last run
INSERT INTO curated.fct_orders BY NAME
SELECT
  o.order_id,
  o.order_date,
  o.amount,
  d.customer_sk,
  o.customer_id,
  d.customer_name,
  d.region,
  o.order_status,
  CURRENT_TIMESTAMP AS fact_loaded_at
FROM staging.stg_orders o
INNER JOIN curated.dim_customers d ON o.customer_id = d.customer_id
CROSS JOIN (
  SELECT watermark_value AS last_watermark
  FROM curated.etl_watermarks
  WHERE pipeline_name = 'fct_orders'
) w
WHERE o.order_status NOT IN ('cancelled', 'void')
  AND o.order_date > w.last_watermark
  AND o.order_id NOT IN (SELECT order_id FROM curated.fct_orders);

-- Advance watermark
UPDATE curated.etl_watermarks
SET
  watermark_value = (SELECT MAX(order_date) FROM curated.fct_orders),
  updated_at = CURRENT_TIMESTAMP
WHERE pipeline_name = 'fct_orders';
```

### Merge / upsert dimension (delete + insert by key)

```sql
CREATE OR REPLACE TABLE curated.dim_customers AS
SELECT * FROM curated.dim_customers
WHERE customer_id NOT IN (
  SELECT customer_id FROM staging.stg_customers WHERE customer_id IS NOT NULL
)
UNION ALL
SELECT
  MD5(customer_id::VARCHAR) AS customer_sk,
  customer_id,
  TRIM(customer_name) AS customer_name,
  customer_segment,
  region,
  is_active,
  updated_at,
  CURRENT_TIMESTAMP AS dim_loaded_at
FROM (
  SELECT * FROM staging.stg_customers
  WHERE customer_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) = 1
) latest;
```

### Incremental mart refresh (recent months)

```sql
DELETE FROM curated.mart_monthly_sales
WHERE sales_month >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '2 months';

INSERT INTO curated.mart_monthly_sales BY NAME
SELECT
  DATE_TRUNC('month', order_date) AS sales_month,
  region,
  customer_segment,
  COUNT(*) AS order_count,
  SUM(amount) AS total_sales
FROM curated.fct_orders
WHERE order_status = 'shipped'
  AND order_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '2 months'
GROUP BY 1, 2, 3;
```

### Idempotent staging slice by `ingest_batch_id`

```sql
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM raw.raw_orders_csv
WHERE ingest_batch_id = '${batch_id}';
```

## Notebook Usage

```python
PIPELINE = "fct_orders"

con.execute("""
CREATE TABLE IF NOT EXISTS curated.etl_watermarks (
  pipeline_name VARCHAR PRIMARY KEY,
  watermark_value TIMESTAMP,
  updated_at TIMESTAMP
);
""")

# Read last watermark
last_wm = con.sql(f"""
  SELECT COALESCE(
    (SELECT watermark_value FROM curated.etl_watermarks
     WHERE pipeline_name = '{PIPELINE}'),
    TIMESTAMP '1900-01-01'
  ) AS wm
""").fetchone()[0]

print(f"Last watermark: {last_wm}")

# Simulate new staging batch
con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT * FROM (VALUES
  ('ORD-010', 'C-100', TIMESTAMP '2024-06-01', 80.0, 'shipped'),
  ('ORD-011', 'C-101', TIMESTAMP '2024-06-02', 120.0, 'shipped')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute(f"""
INSERT INTO curated.fct_orders BY NAME
SELECT
  o.order_id, o.order_date, o.amount, d.customer_sk,
  o.customer_id, d.customer_name, d.region, o.order_status,
  CURRENT_TIMESTAMP AS fact_loaded_at
FROM staging.stg_orders o
INNER JOIN curated.dim_customers d ON o.customer_id = d.customer_id
WHERE o.order_date > TIMESTAMP '{last_wm}'
  AND o.order_id NOT IN (SELECT order_id FROM curated.fct_orders);
""")

con.execute(f"""
  INSERT INTO curated.etl_watermarks BY NAME
  SELECT '{PIPELINE}', MAX(order_date), CURRENT_TIMESTAMP
  FROM curated.fct_orders
  ON CONFLICT (pipeline_name) DO UPDATE SET
    watermark_value = EXCLUDED.watermark_value,
    updated_at = EXCLUDED.updated_at;
""")
```

Online ingest + incremental watermark:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *, CURRENT_TIMESTAMP AS ingest_ts
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")

con.execute("""
CREATE TABLE IF NOT EXISTS curated.etl_watermarks (
  pipeline_name VARCHAR PRIMARY KEY,
  watermark_value TIMESTAMP,
  updated_at TIMESTAMP
);
""")

con.execute("""
CREATE TABLE IF NOT EXISTS staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population,
  ingest_ts
FROM raw.raw_population_csv
WHERE FALSE;

INSERT INTO staging.stg_population BY NAME
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population,
  ingest_ts
FROM raw.raw_population_csv
WHERE ingest_ts > COALESCE(
  (SELECT watermark_value FROM curated.etl_watermarks
   WHERE pipeline_name = 'stg_population'),
  TIMESTAMP '1900-01-01'
);
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{pipeline_name}` | `fct_orders` | Watermark registry key |
| `{watermark_column}` | `order_date`, `ingest_ts` | Monotonic cursor |
| `{target_table}` | `curated.fct_orders` | Incremental destination |
| `{source_table}` | `staging.stg_orders` | New/changed rows |
| `{grain_key}` | `order_id` | Idempotency dedupe |
| Lookback window | `INTERVAL '2 months'` | Mart correction window |
| `{batch_id}` | `20240615T120000` | Optional batch filter |

## Input Table Pattern

**New staging batch:** `staging.stg_orders`

| order_id | customer_id | order_date | amount | order_status |
|----------|-------------|------------|--------|--------------|
| ORD-010 | C-100 | 2024-06-01 | 80.0 | shipped |
| ORD-011 | C-101 | 2024-06-02 | 120.0 | shipped |

**Watermark table:** `curated.etl_watermarks`

| pipeline_name | watermark_value | updated_at |
|---------------|-----------------|------------|
| fct_orders | 2024-05-31 23:59:59 | 2024-06-01 … |

## Output Table Pattern

```text
curated.fct_<entity>     -- append or merge
curated.dim_<entity>     -- merge by natural key
curated.mart_<grain>     -- delete+insert window
curated.etl_watermarks   -- pipeline state
```

Appended rows in **`curated.fct_orders`** — existing rows preserved, new keys added.

## Validation Checks

```sql
-- No duplicate keys after incremental run
SELECT order_id, COUNT(*) AS n
FROM curated.fct_orders
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Watermark advanced
SELECT pipeline_name, watermark_value, updated_at
FROM curated.etl_watermarks
WHERE pipeline_name = 'fct_orders';
```

```sql
-- Rows inserted this run (by load timestamp)
SELECT COUNT(*) AS rows_loaded_today
FROM curated.fct_orders
WHERE CAST(fact_loaded_at AS DATE) = CURRENT_DATE;
```

```sql
-- Staging rows missed by watermark filter
SELECT COUNT(*) AS missed
FROM staging.stg_orders s
LEFT JOIN curated.fct_orders f ON s.order_id = f.order_id
WHERE f.order_id IS NULL
  AND s.order_status NOT IN ('cancelled', 'void');
```

```sql
-- Mart reconciliation after partial refresh
SELECT
  (SELECT SUM(amount) FROM curated.fct_orders WHERE order_status = 'shipped') AS fact_total,
  (SELECT SUM(total_sales) FROM curated.mart_monthly_sales) AS mart_total;
```

## Common Variations

### Full replace for small tables

```sql
CREATE OR REPLACE TABLE curated.dim_customers AS ...
```

Use when row counts stay small — simpler than merge logic.

### `INSERT OR IGNORE` idempotency

```sql
INSERT OR IGNORE INTO curated.fct_orders BY NAME
SELECT ... FROM staging.stg_orders o WHERE ...;
```

### Partition overwrite by month

```sql
DELETE FROM curated.fct_orders
WHERE DATE_TRUNC('month', order_date) = DATE '2024-06-01';

INSERT INTO curated.fct_orders BY NAME
SELECT ... WHERE DATE_TRUNC('month', order_date) = DATE '2024-06-01';
```

### Change data capture with hash compare

```sql
SELECT s.*
FROM staging.stg_customers s
LEFT JOIN curated.dim_customers d ON s.customer_id = d.customer_id
WHERE d.customer_id IS NULL
   OR MD5(CONCAT(s.customer_name, s.region)) != MD5(CONCAT(d.customer_name, d.region));
```

### Notebook parameter cell

```python
BATCH_ID = "20240615T120000"
WATERMARK_LOOKBACK_DAYS = 7
```

## Performance Notes

- Append-only inserts are fastest — prefer watermark on indexed-ish columns (`order_date`) with selective `WHERE`.
- `NOT IN (SELECT order_id FROM ...)` is clear but can be slow at scale — use `ANTI JOIN` or `INSERT OR IGNORE` alternatives.
- Mart partial deletes should target narrow month windows, not full table scans.
- Run [build dimension table](build_dimension_table.md) incrementally before facts when new customers appear in the batch.
- Batch multiple incremental pipelines in one notebook session to share the same connection and watermark read.

## Known Limitations

- Watermarks fail on late-arriving rows older than `watermark_value` — use lookback windows or periodic full reconciliations.
- DuckDB `MERGE` support evolves — delete+insert or `CREATE OR REPLACE` unions are portable fallbacks.
- `etl_watermarks` is not concurrent-safe across parallel writers — one notebook runner per pipeline.
- Dimension merges without history tracking lose prior attribute values (Type 1 semantics).
- Incremental marts can drift from facts if dimension attribution changes retroactively — schedule periodic full mart rebuilds.

## Related Pages

- [Build fact table](build_fact_table.md)
- [Build dimension table](build_dimension_table.md)
- [Aggregations](aggregations.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [INSERT](https://duckdb.org/docs/current/sql/statements/insert.html) · [UPDATE](https://duckdb.org/docs/current/sql/statements/update.html)
