# Outlier Scan

Flag numeric values that fall outside typical ranges using IQR, z-score, or domain-specific caps.

## Purpose

Identify extreme observations in measures like `amount` or `quantity` that may be data errors, fraud signals, or legitimate tail events worth reviewing before aggregation.

## When to Use

- After [numeric_summary](numeric_summary.md) shows a heavy tail (`max >> avg`)
- Before computing revenue KPIs in `curated`
- QA on ingested vendor files with known valid ranges
- Optional gate before exporting to downstream ML features

## SQL Template

### IQR method (per column)

```sql
WITH stats AS (
  SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount) AS q3
  FROM staging.stg_orders
  WHERE amount IS NOT NULL
),
bounds AS (
  SELECT
    q1,
    q3,
    q3 - q1 AS iqr,
    q1 - 1.5 * (q3 - q1) AS lower_bound,
    q3 + 1.5 * (q3 - q1) AS upper_bound
  FROM stats
)
SELECT
  o.order_id,
  o.customer_id,
  o.order_date,
  o.amount,
  b.lower_bound,
  b.upper_bound
FROM staging.stg_orders o
CROSS JOIN bounds b
WHERE o.amount < b.lower_bound
   OR o.amount > b.upper_bound
ORDER BY o.amount DESC
LIMIT 100;
```

### Z-score method (sample stddev)

```sql
WITH stats AS (
  SELECT
    AVG(amount) AS mean_amount,
    STDDEV_SAMP(amount) AS std_amount
  FROM staging.stg_orders
  WHERE amount IS NOT NULL
)
SELECT
  o.order_id,
  o.amount,
  (o.amount - s.mean_amount) / NULLIF(s.std_amount, 0) AS z_score
FROM staging.stg_orders o
CROSS JOIN stats s
WHERE s.std_amount > 0
  AND ABS((o.amount - s.mean_amount) / s.std_amount) > 3
ORDER BY ABS((o.amount - s.mean_amount) / s.std_amount) DESC
LIMIT 100;
```

### Domain cap (business rule)

```sql
SELECT order_id, amount, order_date
FROM staging.stg_orders
WHERE amount < 0
   OR amount > 10000  -- replace with domain max
ORDER BY amount DESC;
```

### Outlier count summary

```sql
WITH stats AS (
  SELECT AVG(amount) AS m, STDDEV_SAMP(amount) AS s
  FROM staging.stg_orders WHERE amount IS NOT NULL
)
SELECT
  COUNT(*) FILTER (WHERE ABS((amount - m) / NULLIF(s, 0)) > 3) AS z_outliers,
  COUNT(*) FILTER (WHERE amount < 0 OR amount > 10000) AS domain_outliers
FROM staging.stg_orders, stats
WHERE amount IS NOT NULL;
```

## Notebook Usage

```python
outliers = con.sql("""
  WITH stats AS (
    SELECT
      PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount) AS q1,
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount) AS q3
    FROM staging.stg_orders WHERE amount IS NOT NULL
  ),
  bounds AS (
    SELECT q1 - 1.5 * (q3 - q1) AS lo, q3 + 1.5 * (q3 - q1) AS hi
    FROM stats
  )
  SELECT o.*
  FROM staging.stg_orders o, bounds b
  WHERE o.amount < b.lo OR o.amount > b.hi
  ORDER BY o.amount DESC
  LIMIT 50
""").df()
outliers
```

Compare methods in one cell:

```python
summary = con.sql("""
  SELECT
    COUNT(*) AS n,
    MIN(amount) AS min_a,
    MAX(amount) AS max_a,
    AVG(amount) AS avg_a
  FROM staging.stg_orders
""").df()
summary
```

Practice dataset — population outliers by country (2020):

```python
con.sql("""
  WITH base AS (
    SELECT country_name, CAST(value AS DOUBLE) AS pop
    FROM raw.raw_population_csv
    WHERE year = '2020' AND value IS NOT NULL
  ),
  stats AS (
    SELECT AVG(pop) AS m, STDDEV_SAMP(pop) AS s FROM base
  )
  SELECT b.country_name, b.pop,
    (b.pop - s.m) / s.s AS z
  FROM base b, stats s
  WHERE ABS((b.pop - s.m) / s.s) > 3
  ORDER BY b.pop DESC
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Numeric column | `amount`, `quantity` | Must be numeric type |
| `{schema}.{table}` | `staging.stg_orders` | Typed `staging` preferred |
| IQR multiplier | `1.5` | Standard Tukey fence |
| Z threshold | `3` | Common for normal-like data |
| Domain max/min | `0`, `10000` | Business-defined caps |
| `LIMIT` | `100` | Notebook row cap |

## Expected Output

**Outlier rows:** detail records with `amount`, bounds or `z_score`, and identifying keys (`order_id`).

**Summary:**

| z_outliers | domain_outliers |
|------------|-----------------|
| 42 | 8 |

## Common Variations

### Per-group IQR (by `order_status`)

```sql
WITH ranked AS (
  SELECT
    order_status,
    amount,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount)
      OVER (PARTITION BY order_status) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount)
      OVER (PARTITION BY order_status) AS q3
  FROM staging.stg_orders
  WHERE amount IS NOT NULL
)
SELECT DISTINCT order_status, amount, q1, q3
FROM ranked
WHERE amount < q1 - 1.5 * (q3 - q1)
   OR amount > q3 + 1.5 * (q3 - q1);
```

### Modified z-score (MAD — robust)

```sql
WITH med AS (
  SELECT MEDIAN(amount) AS med_amount FROM staging.stg_orders WHERE amount IS NOT NULL
),
mad AS (
  SELECT MEDIAN(ABS(o.amount - m.med_amount)) AS mad_amount
  FROM staging.stg_orders o, med m
  WHERE o.amount IS NOT NULL
)
SELECT o.order_id, o.amount,
  0.6745 * (o.amount - m.med_amount) / NULLIF(a.mad_amount, 0) AS modified_z
FROM staging.stg_orders o, med m, mad a
WHERE a.mad_amount > 0
  AND ABS(0.6745 * (o.amount - m.med_amount) / a.mad_amount) > 3.5;
```

### Log-scale scan for heavy-tailed positives

```sql
SELECT order_id, amount, LN(amount) AS log_amount
FROM staging.stg_orders
WHERE amount > 0
  AND LN(amount) > (
    SELECT AVG(LN(amount)) + 3 * STDDEV_SAMP(LN(amount))
    FROM staging.stg_orders WHERE amount > 0
  );
```

### Exclude known valid extremes before flagging

```sql
SELECT *
FROM staging.stg_orders
WHERE amount > 10000
  AND order_status != 'wholesale'  -- wholesale may legitimately be large
LIMIT 50;
```

## Interpretation Guidance

- **IQR** — robust to skew; preferred for revenue and price data with long tails.
- **Z-score** — sensitive to outliers in mean/stddev; use after trimming or on log-transformed positives.
- **Many flags** — may indicate true heavy-tailed business, not errors; tune thresholds or use domain caps.
- **Few extreme flags** — inspect manually via [preview_rows](preview_rows.md); may be unit errors (cents vs dollars).

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Data entry errors | Fix in `source` or filter in `staging` |
| Valid extremes | Document; optionally winsorize in `curated` |
| Unit mismatch | Scale in `staging` |
| Clean enough | Publish aggregates to `output` |

## Related Pages

- [Numeric summary](numeric_summary.md)
- [Date range check](date_range_check.md)
- [Duplicate check](duplicate_check.md)
- [Preview rows](preview_rows.md)

Official reference: [DuckDB percentile functions](https://duckdb.org/docs/current/sql/functions/aggregates.html#percentile)
