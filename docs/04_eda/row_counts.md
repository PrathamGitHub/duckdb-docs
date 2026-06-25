# Row Counts

Measure table volume and optional breakdowns by partition, status, or ingest source.

## Purpose

Establish baseline record counts for reconciliation, incremental loads, and validation gates between workflow layers.

## When to Use

- After `raw` ingest — compare to source file metadata or vendor manifest
- Before and after `staging` — row count should not drop unexpectedly without documented filters
- Reconciliation: `raw.raw_orders` vs `staging.stg_orders` vs curated facts
- Group counts by `order_status`, `country`, or `source_file` for skew detection

## SQL Template

Total row count:

```sql
SELECT COUNT(*) AS row_count
FROM raw.raw_orders;
```

Non-null count on a key column:

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(order_id) AS rows_with_order_id,
  COUNT(*) - COUNT(order_id) AS rows_missing_order_id
FROM raw.raw_orders;
```

Count by category:

```sql
SELECT
  order_status,
  COUNT(*) AS row_count
FROM staging.stg_orders
GROUP BY order_status
ORDER BY row_count DESC;
```

Cross-layer reconciliation:

```sql
SELECT 'raw' AS layer, COUNT(*) AS n FROM raw.raw_orders
UNION ALL
SELECT 'staging', COUNT(*) FROM staging.stg_orders;
```

## Notebook Usage

```python
# Single metric
n = con.sql("SELECT COUNT(*) AS n FROM raw.raw_orders").df()
n

# Layer comparison as a small report
layers = {
    "raw.raw_orders": "raw.raw_orders",
    "staging.stg_orders": "staging.stg_orders",
    "raw.raw_customers": "raw.raw_customers",
}
counts = con.sql("""
  SELECT 'raw_orders' AS table_name, COUNT(*) AS n FROM raw.raw_orders
  UNION ALL SELECT 'stg_orders', COUNT(*) FROM staging.stg_orders
  UNION ALL SELECT 'raw_customers', COUNT(*) FROM raw.raw_customers
""").df()
counts
```

Practice dataset:

```python
con.sql("""
  SELECT year, COUNT(*) AS countries
  FROM raw.raw_population_csv
  GROUP BY year
  ORDER BY year DESC
  LIMIT 10
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Table to count |
| `GROUP BY` column | `order_status`, `source_file` | Breakdown dimension |
| Key column | `order_id` | Non-null vs total comparison |
| Filter | `WHERE order_date >= '2024-01-01'` | Scoped counts |

## Expected Output

- **Total count:** one row, one integer (`row_count` or `n`)
- **Grouped count:** one row per distinct group value with `row_count`
- **Reconciliation:** one row per layer with comparable `n` values

## Common Variations

### Count distinct business keys

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS distinct_order_ids
FROM raw.raw_orders;
```

### Count by ingest file (glob ingest)

```sql
SELECT source_file, COUNT(*) AS row_count
FROM raw.raw_orders
GROUP BY source_file
ORDER BY row_count DESC;
```

### Daily volume trend

```sql
SELECT
  CAST(order_date AS DATE) AS order_day,
  COUNT(*) AS row_count
FROM staging.stg_orders
GROUP BY 1
ORDER BY 1;
```

### Approximate count on very large tables

```sql
SELECT approx_count_distinct(order_id) AS approx_distinct_orders
FROM raw.raw_orders;
```

## Interpretation Guidance

- **`COUNT(*)` vs `COUNT(DISTINCT key)`** — a large gap implies duplicate keys; run [duplicate_check](duplicate_check.md).
- **Raw > staging** — expected when staging filters bad rows; document every filter.
- **Staging > raw** — unexpected unless staging explodes arrays or joins; investigate joins.
- **Skewed group counts** — one `order_status` dominating may affect downstream aggregates; note for [categorical_frequency](categorical_frequency.md).

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Count mismatch vs source | Re-ingest `raw`; verify file completeness |
| Duplicate keys suspected | [duplicate_check](duplicate_check.md), [distinct_profile](distinct_profile.md) |
| High null rate on keys | [null_profile](null_profile.md) |
| Volume OK | Proceed to column-level EDA or `staging` transforms |

## Related Pages

- [Duplicate check](duplicate_check.md)
- [Distinct profile](distinct_profile.md)
- [Preview rows](preview_rows.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB aggregate functions](https://duckdb.org/docs/current/sql/functions/aggregates.html)
