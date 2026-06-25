# Numeric Summary

Compute min, max, mean, standard deviation, and percentiles for numeric columns.

## Purpose

Summarize distribution of measures (`amount`, `quantity`, population `value`) to spot scale issues, negative values, and skew before aggregation or export.

## When to Use

- After typing numeric fields in `staging.stg_orders`
- Before financial or KPI reporting in `curated`
- When [preview rows](preview_rows.md) show suspicious magnitudes
- Baseline prior to [outlier_scan](outlier_scan.md)

## SQL Template

Single-column summary:

```sql
SELECT
  COUNT(amount) AS non_null_count,
  MIN(amount) AS min_amount,
  MAX(amount) AS max_amount,
  AVG(amount) AS avg_amount,
  STDDEV_SAMP(amount) AS stddev_amount,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount) AS p25_amount,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount) AS p75_amount
FROM staging.stg_orders
WHERE amount IS NOT NULL;
```

Multi-metric one-row summary:

```sql
SELECT
  MIN(amount) AS min_amount,
  MAX(amount) AS max_amount,
  AVG(amount) AS avg_amount,
  MIN(quantity) AS min_qty,
  MAX(quantity) AS max_qty,
  AVG(quantity) AS avg_qty
FROM staging.stg_orders;
```

Summary by category:

```sql
SELECT
  order_status,
  COUNT(*) AS n,
  AVG(amount) AS avg_amount,
  SUM(amount) AS total_amount
FROM staging.stg_orders
GROUP BY order_status
ORDER BY total_amount DESC;
```

Negative and zero flags:

```sql
SELECT
  COUNT(*) FILTER (WHERE amount < 0) AS negative_amount_rows,
  COUNT(*) FILTER (WHERE amount = 0) AS zero_amount_rows,
  COUNT(*) FILTER (WHERE amount IS NULL) AS null_amount_rows
FROM raw.raw_orders;
```

## Notebook Usage

```python
con.sql("""
  SELECT
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    ROUND(AVG(amount), 2) AS avg_amount,
    ROUND(STDDEV_SAMP(amount), 2) AS stddev_amount
  FROM staging.stg_orders
""").df()
```

Grouped summary for charts:

```python
by_status = con.sql("""
  SELECT order_status, AVG(amount) AS avg_amount, COUNT(*) AS n
  FROM staging.stg_orders
  GROUP BY 1
  ORDER BY avg_amount DESC
""").df()
by_status.plot.bar(x="order_status", y="avg_amount")
```

Practice dataset:

```python
con.sql("""
  SELECT
    MIN(CAST(value AS DOUBLE)) AS min_pop,
    MAX(CAST(value AS DOUBLE)) AS max_pop,
    AVG(CAST(value AS DOUBLE)) AS avg_pop
  FROM raw.raw_population_csv
  WHERE year = '2020'
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Numeric column | `amount`, `quantity`, `value` | Cast in `staging` if still `VARCHAR` |
| `{schema}.{table}` | `staging.stg_orders` | Typed table preferred |
| `GROUP BY` | `order_status`, `country_name` | Segment summaries |
| Percentiles | `0.25`, `0.5`, `0.75` | Adjust as needed |

## Expected Output

| non_null_count | min_amount | max_amount | avg_amount | stddev_amount | median_amount |
|----------------|------------|------------|------------|---------------|---------------|
| 9850 | 0.50 | 4999.99 | 127.34 | 89.12 | 98.00 |

Grouped output adds a dimension column plus `n`, `avg_*`, `sum_*`.

## Common Variations

### Summarize all numeric columns (dynamic)

```python
def numeric_columns(schema: str, table: str) -> list[str]:
    df = con.sql(f"""
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = '{schema}' AND table_name = '{table}'
        AND data_type IN ('TINYINT','SMALLINT','INTEGER','BIGINT','HUGEINT',
                          'UTINYINT','USMALLINT','UINTEGER','UBIGINT',
                          'FLOAT','DOUBLE','DECIMAL')
    """).df()
    return df["column_name"].tolist()

for col in numeric_columns("staging", "stg_orders"):
    display(con.sql(f"""
      SELECT '{col}' AS column_name,
        MIN("{col}") AS min_val, MAX("{col}") AS max_val, AVG("{col}") AS avg_val
      FROM staging.stg_orders
    """).df())
```

### Approximate quantiles (large tables)

```sql
SELECT quantile_cont(amount, 0.5) AS median_amount
FROM staging.stg_orders;
```

### Year-over-year numeric comparison (population practice)

```sql
SELECT
  year,
  AVG(CAST(value AS DOUBLE)) AS avg_population,
  SUM(CAST(value AS DOUBLE)) AS total_population
FROM raw.raw_population_csv
GROUP BY year
ORDER BY year;
```

## Interpretation Guidance

- **`min < 0` on amounts** — refunds, data errors, or valid credits; confirm with domain owners.
- **`max` orders of magnitude above `avg`** — skew; use median and [outlier_scan](outlier_scan.md).
- **High `stddev` relative to mean** — volatile measure; report median and percentiles in dashboards.
- **`avg` differs widely by group** — investigate segment logic before global KPIs.

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Extreme max/min | [outlier_scan](outlier_scan.md) |
| Wrong scale (cents vs dollars) | Fix in `staging` |
| VARCHAR numerics | `TRY_CAST` in `staging` |
| Clean distribution | Build `curated` aggregates |

## Related Pages

- [Outlier scan](outlier_scan.md)
- [Null profile](null_profile.md)
- [Categorical frequency](categorical_frequency.md)
- [Date range check](date_range_check.md)

Official reference: [DuckDB aggregate functions](https://duckdb.org/docs/current/sql/functions/aggregates.html)
