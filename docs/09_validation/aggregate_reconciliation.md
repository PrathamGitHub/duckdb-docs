# Aggregate Reconciliation

Compare summed or counted metrics between pipeline stages to confirm transforms preserved totals within tolerance.

## Purpose

Produce a metric comparison report (sums, counts, distinct counts) so analysts can verify that filters and joins did not silently change business totals. This is a **summary check** — it always returns rows; interpret the `delta` and `status` columns.

## When to Use

- After `staging.stg_orders` → `curated.fct_orders` — shipped revenue should match
- After status filters — document excluded `cancelled` amounts
- After spatial clip — parcel count and total acreage vs `raw`
- Before executive delivery — revenue tie-out

## SQL Template

Shipped revenue: staging vs fact:

```sql
WITH metrics AS (
  SELECT
    'staging.stg_orders (shipped)' AS source,
    SUM(amount) AS total_amount,
    COUNT(*) AS row_count
  FROM staging.stg_orders
  WHERE order_status = 'shipped'
  UNION ALL
  SELECT
    'curated.fct_orders',
    SUM(amount),
    COUNT(*)
  FROM curated.fct_orders
),
compare AS (
  SELECT
    MAX(CASE WHEN source LIKE 'staging%' THEN total_amount END) AS stg_amount,
    MAX(CASE WHEN source = 'curated.fct_orders' THEN total_amount END) AS fct_amount,
    MAX(CASE WHEN source LIKE 'staging%' THEN row_count END) AS stg_rows,
    MAX(CASE WHEN source = 'curated.fct_orders' THEN row_count END) AS fct_rows
  FROM metrics
)
SELECT
  'total_amount' AS metric_name,
  stg_amount AS source_value,
  fct_amount AS compare_value,
  fct_amount - stg_amount AS delta,
  CASE
    WHEN ABS(fct_amount - stg_amount) <= 0.01 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM compare
UNION ALL
SELECT
  'row_count',
  stg_rows,
  fct_rows,
  fct_rows - stg_rows,
  CASE WHEN stg_rows = fct_rows THEN 'PASS' ELSE 'FAIL' END
FROM compare;
```

Raw vs staging row count and amount:

```sql
SELECT
  'raw.raw_orders' AS layer,
  COUNT(*) AS n,
  SUM(TRY_CAST(amount AS DOUBLE)) AS total_amount
FROM raw.raw_orders
UNION ALL
SELECT
  'staging.stg_orders',
  COUNT(*),
  SUM(amount)
FROM staging.stg_orders;
```

Distinct customer count reconciliation:

```sql
SELECT
  'staging.stg_orders' AS source,
  COUNT(DISTINCT customer_id) AS distinct_customers
FROM staging.stg_orders
UNION ALL
SELECT
  'curated.fct_orders',
  COUNT(DISTINCT customer_id)
FROM curated.fct_orders;
```

## Notebook Usage

```python
recon = con.sql("""
  WITH stg AS (
    SELECT SUM(amount) AS amt, COUNT(*) AS n
    FROM staging.stg_orders
    WHERE order_status = 'shipped'
  ),
  fct AS (
    SELECT SUM(amount) AS amt, COUNT(*) AS n
    FROM curated.fct_orders
  )
  SELECT
    stg.amt AS stg_amount,
    fct.amt AS fct_amount,
    fct.amt - stg.amt AS amount_delta,
    stg.n AS stg_rows,
    fct.n AS fct_rows
  FROM stg, fct
""").df()
recon

row = recon.iloc[0]
assert abs(row.amount_delta) < 0.01, f"Amount delta: {row.amount_delta}"
assert row.stg_rows == row.fct_rows, "Row count mismatch"
```

Spatial acreage example:

```python
con.sql("""
  SELECT
    'raw.raw_parcels' AS layer,
    SUM(acreage) AS total_acreage,
    COUNT(*) AS n
  FROM raw.raw_parcels
  UNION ALL
  SELECT 'curated.geo_parcels', SUM(acreage), COUNT(*)
  FROM curated.geo_parcels
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{source_table}` | `staging.stg_orders` | Pre-transform aggregate |
| `{target_table}` | `curated.fct_orders` | Post-transform aggregate |
| Metric | `SUM(amount)`, `COUNT(*)` | Business-specific |
| Filter | `order_status = 'shipped'` | Must match on both sides |
| Tolerance | `0.01` currency units | Floating-point rounding |
| `{tolerance_pct}` | `0.1%` | Alternative for large totals |

## Expected Output

| metric_name | source_value | compare_value | delta | status |
|-------------|--------------|---------------|-------|--------|
| total_amount | 1250000.00 | 1250000.00 | 0.00 | PASS |
| row_count | 9840 | 9840 | 0 | PASS |

**Layer comparison:**

| layer | n | total_amount |
|-------|---|--------------|
| raw.raw_orders | 10000 | 1285000.00 |
| staging.stg_orders | 9950 | 1270000.00 |

## Pass/Fail Interpretation

| Result | Status |
|--------|--------|
| `delta = 0` (or within tolerance) | **Pass** — totals preserved |
| Amount delta non-zero | **Fail** — cast loss, join duplication, or wrong filter |
| Row count delta with zero amount delta | Investigate — possible zero-amount rows dropped |
| Raw > staging amount | OK if cancelled/refunded rows excluded — document filter |
| Spatial acreage shrink | OK after clip to study area — document in validation log |

## Common Variations

### Percent tolerance

```sql
WITH stg AS (SELECT SUM(amount) AS v FROM staging.stg_orders WHERE order_status = 'shipped'),
     fct AS (SELECT SUM(amount) AS v FROM curated.fct_orders)
SELECT
  stg.v AS stg_sum,
  fct.v AS fct_sum,
  ABS(fct.v - stg.v) / NULLIF(stg.v, 0) AS pct_delta,
  CASE
    WHEN ABS(fct.v - stg.v) / NULLIF(stg.v, 0) <= 0.001 THEN 'PASS'
    ELSE 'FAIL'
  END AS status
FROM stg, fct;
```

### Reconcile by month

```sql
SELECT
  DATE_TRUNC('month', CAST(order_date AS DATE)) AS order_month,
  SUM(amount) AS stg_amount
FROM staging.stg_orders
WHERE order_status = 'shipped'
GROUP BY 1
ORDER BY 1;
-- Compare to same GROUP BY on curated.fct_orders
```

### Anti-join orphan amount (explains fact shortfall)

```sql
SELECT SUM(o.amount) AS orphan_amount, COUNT(*) AS orphan_rows
FROM staging.stg_orders o
LEFT JOIN curated.dim_customers d ON o.customer_id = d.customer_id
WHERE o.order_status = 'shipped'
  AND d.customer_id IS NULL;
```

### Multiple metrics in one summary table

```sql
SELECT * FROM (
  SELECT 'sum_amount' AS metric, SUM(amount) AS v FROM staging.stg_orders WHERE order_status = 'shipped'
  UNION ALL SELECT 'count_rows', COUNT(*) FROM staging.stg_orders WHERE order_status = 'shipped'
  UNION ALL SELECT 'distinct_customers', COUNT(DISTINCT customer_id) FROM staging.stg_orders
) staging_metrics;
```

## How to Document Results

```text
Check: VAL-008 Aggregate reconciliation
Metric: SUM(amount) shipped orders
Source: staging.stg_orders (shipped)
Target: curated.fct_orders
Tolerance: ±0.01
Result: PASS (delta = 0.00)
Excluded: cancelled orders ($35,000) documented in staging README
```

Export reconciliation DataFrame to `data/output/validation/aggregate_reconciliation.parquet`. Register in [validation summary table](validation_summary_table.md).

## Related Pages

- [Row count reconciliation](row_count_reconciliation.md)
- [Referential integrity](referential_integrity.md)
- [Build fact table](../07_transformation/build_fact_table.md)
- [Aggregations](../07_transformation/aggregations.md)

Official reference: [DuckDB aggregate functions](https://duckdb.org/docs/current/sql/functions/aggregates.html)
