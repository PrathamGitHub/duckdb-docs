# Row Count Reconciliation

Compare record counts across pipeline layers to confirm ingest, filters, and joins did not drop or duplicate rows unexpectedly.

## Purpose

Produce a side-by-side count report for `raw`, `staging`, and `curated` tables so you can sign off on volume before export or delivery.

## When to Use

- After promoting `raw.raw_orders` → `staging.stg_orders`
- After building `curated.fct_orders` from `staging.stg_orders` + `curated.dim_customers`
- After spatial staging on parcels — compare `raw` ingest to `curated.geo_parcels`
- Before publishing to `output` — final volume gate

## SQL Template

Cross-layer reconciliation with pass/fail flag:

```sql
WITH counts AS (
  SELECT 'raw.raw_orders' AS table_name, COUNT(*) AS row_count
  FROM raw.raw_orders
  UNION ALL
  SELECT 'staging.stg_orders', COUNT(*)
  FROM staging.stg_orders
  UNION ALL
  SELECT 'curated.fct_orders', COUNT(*)
  FROM curated.fct_orders
),
expected AS (
  SELECT
    (SELECT row_count FROM counts WHERE table_name = 'raw.raw_orders') AS raw_n,
    (SELECT row_count FROM counts WHERE table_name = 'staging.stg_orders') AS stg_n,
    (SELECT row_count FROM counts WHERE table_name = 'curated.fct_orders') AS fct_n
)
SELECT
  c.table_name,
  c.row_count,
  CASE
    WHEN c.table_name = 'staging.stg_orders'
      AND c.row_count > e.raw_n THEN 'FAIL: staging exceeds raw'
    WHEN c.table_name = 'curated.fct_orders'
      AND c.row_count > e.stg_n THEN 'FAIL: fact exceeds staging'
    ELSE 'OK'
  END AS status
FROM counts c
CROSS JOIN expected e
ORDER BY c.table_name;
```

Source vs raw (when source file row count is known):

```sql
SELECT
  'source_manifest' AS layer,
  10000 AS row_count,
  'expected from vendor' AS note
UNION ALL
SELECT 'raw.raw_orders', COUNT(*), 'actual'
FROM raw.raw_orders;
```

Filtered staging — document intentional drops:

```sql
SELECT
  (SELECT COUNT(*) FROM raw.raw_orders) AS raw_n,
  (SELECT COUNT(*) FROM staging.stg_orders) AS stg_n,
  (SELECT COUNT(*) FROM raw.raw_orders) - (SELECT COUNT(*) FROM staging.stg_orders) AS dropped_rows,
  ROUND(
    100.0 * (
      (SELECT COUNT(*) FROM raw.raw_orders) - (SELECT COUNT(*) FROM staging.stg_orders)
    ) / NULLIF((SELECT COUNT(*) FROM raw.raw_orders), 0),
    2
  ) AS drop_pct;
```

## Notebook Usage

```python
counts = con.sql("""
  SELECT 'raw.raw_orders' AS table_name, COUNT(*) AS row_count
  FROM raw.raw_orders
  UNION ALL
  SELECT 'staging.stg_orders', COUNT(*) FROM staging.stg_orders
  UNION ALL
  SELECT 'curated.fct_orders', COUNT(*) FROM curated.fct_orders
  ORDER BY 1
""").df()
counts

# Optional: fail notebook cell if staging exceeds raw without documented reason
raw_n = counts.loc[counts.table_name == 'raw.raw_orders', 'row_count'].iloc[0]
stg_n = counts.loc[counts.table_name == 'staging.stg_orders', 'row_count'].iloc[0]
assert stg_n <= raw_n, f"staging ({stg_n}) exceeds raw ({raw_n})"
```

Spatial layer example:

```python
con.sql("""
  SELECT 'raw.raw_parcels' AS layer, COUNT(*) AS n FROM raw.raw_parcels
  UNION ALL SELECT 'curated.geo_parcels', COUNT(*) FROM curated.geo_parcels
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_orders` | Post-ingest volume |
| `{stg_table}` | `staging.stg_orders` | After cleaning filters |
| `{curated_table}` | `curated.fct_orders` | Final model grain |
| Expected source count | `10000` | Vendor manifest or `wc -l` minus header |
| Tolerance | `0` rows or `0.5%` | Document allowed drop rate |

## Expected Output

| table_name | row_count | status |
|------------|-----------|--------|
| curated.fct_orders | 9840 | OK |
| raw.raw_orders | 10000 | OK |
| staging.stg_orders | 9950 | OK |

**Summary drop report:**

| raw_n | stg_n | dropped_rows | drop_pct |
|-------|-------|--------------|----------|
| 10000 | 9950 | 50 | 0.50 |

This is a **summary check** — it always returns rows. Interpret the metrics, not row count alone.

## Pass/Fail Interpretation

| Result | Meaning |
|--------|---------|
| `raw` ≈ source manifest | Ingest complete |
| `stg` ≤ `raw` with documented filters | Expected cleaning loss |
| `stg` > `raw` | **Fail** — join explosion or double materialization |
| `fct` ≤ `stg` (inner join to dimension) | Expected when orphan orders excluded |
| `fct` > `stg` | **Fail** — duplicate keys or bad join grain |
| `geo_parcels` < `raw_parcels` | OK if clip/boundary filter documented |

## Common Variations

### Count by ingest batch or file

```sql
SELECT source_file, COUNT(*) AS row_count
FROM raw.raw_orders
GROUP BY source_file
ORDER BY row_count DESC;
```

### Distinct key vs row count

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS distinct_orders
FROM staging.stg_orders;
```

### Reconciliation with status filter documented

```sql
SELECT
  (SELECT COUNT(*) FROM staging.stg_orders WHERE order_status != 'cancelled') AS stg_active,
  (SELECT COUNT(*) FROM curated.fct_orders) AS fct_n;
```

### Incremental watermark check

```sql
SELECT
  pipeline_name,
  watermark_value,
  (SELECT MAX(order_date) FROM curated.fct_orders) AS fact_max_date
FROM curated.etl_watermarks
WHERE pipeline_name = 'fct_orders';
```

## How to Document Results

Record in your validation notebook or delivery README:

```text
Check: VAL-001 Row count reconciliation
Run: 2025-06-25T14:30:00Z
Tables: raw.raw_orders, staging.stg_orders, curated.fct_orders
Result: PASS
Notes: 50 rows dropped in staging (cancelled orders); fct matches stg active count.
```

Store the count DataFrame to `data/output/validation/row_count_reconciliation.parquet` or append a row to [validation summary table](validation_summary_table.md).

## Related Pages

- [Primary key uniqueness](primary_key_uniqueness.md)
- [Aggregate reconciliation](aggregate_reconciliation.md)
- [Row counts (EDA)](../04_eda/row_counts.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB aggregate functions](https://duckdb.org/docs/current/sql/functions/aggregates.html)
