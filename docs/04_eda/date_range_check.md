# Date Range Check

Find minimum and maximum dates, future-dated rows, and values outside expected business windows.

## Purpose

Validate temporal coverage and detect impossible or out-of-scope dates before time-series analysis, partitioning, or incremental loads.

## When to Use

- After parsing dates in `staging.stg_orders` (`order_date`, `ship_date`)
- Before filtering "last 90 days" in `curated`
- Incremental ingest — confirm new batch date range abuts prior data
- Any table with `TIMESTAMP`, `DATE`, or date-like `VARCHAR` columns

## SQL Template

Min / max range:

```sql
SELECT
  MIN(CAST(order_date AS DATE)) AS min_order_date,
  MAX(CAST(order_date AS DATE)) AS max_order_date,
  COUNT(*) AS total_rows,
  COUNT(order_date) AS non_null_dates
FROM staging.stg_orders;
```

Future dates (relative to today):

```sql
SELECT *
FROM staging.stg_orders
WHERE CAST(order_date AS DATE) > CURRENT_DATE
ORDER BY order_date DESC
LIMIT 50;
```

Pre-epoch or sentinel dates:

```sql
SELECT *
FROM raw.raw_orders
WHERE CAST(order_date AS DATE) < DATE '2000-01-01'
   OR CAST(order_date AS DATE) > DATE '2099-12-31'
LIMIT 50;
```

Rows outside business window:

```sql
SELECT
  COUNT(*) FILTER (WHERE CAST(order_date AS DATE) < DATE '2020-01-01') AS before_2020,
  COUNT(*) FILTER (WHERE CAST(order_date AS DATE) > CURRENT_DATE) AS future_dates,
  COUNT(*) FILTER (WHERE order_date IS NULL) AS null_dates
FROM staging.stg_orders;
```

Monthly volume histogram:

```sql
SELECT
  DATE_TRUNC('month', CAST(order_date AS DATE)) AS order_month,
  COUNT(*) AS row_count
FROM staging.stg_orders
WHERE order_date IS NOT NULL
GROUP BY 1
ORDER BY 1;
```

## Notebook Usage

```python
con.sql("""
  SELECT
    MIN(CAST(order_date AS DATE)) AS min_date,
    MAX(CAST(order_date AS DATE)) AS max_date
  FROM staging.stg_orders
""").df()
```

Flag future orders:

```python
future = con.sql("""
  SELECT order_id, order_date, amount
  FROM staging.stg_orders
  WHERE CAST(order_date AS DATE) > CURRENT_DATE
""").df()
future
```

Practice dataset — year coverage:

```python
con.sql("""
  SELECT
    MIN(CAST(year AS INTEGER)) AS min_year,
    MAX(CAST(year AS INTEGER)) AS max_year
  FROM raw.raw_population_csv
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Date column | `order_date`, `ship_date`, `created_at` | Cast if `VARCHAR` |
| `{schema}.{table}` | `staging.stg_orders` | Prefer typed dates in `staging` |
| Business start | `DATE '2020-01-01'` | Lower bound |
| Business end | `CURRENT_DATE` or fixed date | Upper bound |
| `DATE_TRUNC` grain | `'month'`, `'day'` | Histogram bucket |

## Expected Output

**Range summary:**

| min_order_date | max_order_date | total_rows | non_null_dates |
|----------------|----------------|------------|----------------|
| 2019-03-15 | 2025-06-01 | 10000 | 9980 |

**Flag counts:**

| before_2020 | future_dates | null_dates |
|-------------|--------------|------------|
| 12 | 3 | 20 |

## Common Variations

### Parse heterogeneous date strings in raw

```sql
SELECT
  order_date AS raw_value,
  TRY_CAST(order_date AS DATE) AS parsed_date
FROM raw.raw_orders
WHERE TRY_CAST(order_date AS DATE) IS NULL
  AND order_date IS NOT NULL
LIMIT 20;
```

### Gap detection between expected daily grain

```sql
WITH days AS (
  SELECT CAST(order_date AS DATE) AS d, COUNT(*) AS n
  FROM staging.stg_orders
  GROUP BY 1
)
SELECT
  d + INTERVAL 1 DAY AS missing_after
FROM days
WHERE NOT EXISTS (
  SELECT 1 FROM days d2 WHERE d2.d = days.d + INTERVAL 1 DAY
)
AND d < (SELECT MAX(d) FROM days)
ORDER BY 1
LIMIT 20;
```

### Customer created vs order date sanity

```sql
SELECT o.order_id, o.order_date, c.created_at
FROM staging.stg_orders o
JOIN staging.stg_customers c ON o.customer_id = c.customer_id
WHERE CAST(o.order_date AS DATE) < CAST(c.created_at AS DATE)
LIMIT 20;
```

### Timestamp timezone note (store UTC in staging)

```sql
SELECT
  MIN(order_ts AT TIME ZONE 'UTC') AS min_utc,
  MAX(order_ts AT TIME ZONE 'UTC') AS max_utc
FROM staging.stg_orders;
```

## Interpretation Guidance

- **`max_date` in the future** — clock errors, timezone bugs, or placeholder `9999-12-31`; exclude or fix in `staging`.
- **`min_date` too early** — test data or wrong century (`0025` vs `2025`); inspect [preview_rows](preview_rows.md).
- **Sparse months in histogram** — missing ingest months or true business seasonality; compare to [row_counts](row_counts.md).
- **Many null dates** — [null_profile](null_profile.md); block time-series until resolved.

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Unparseable strings | Cast with `TRY_CAST` / `strptime` in `staging` |
| Future / sentinel dates | Filter or cap in `staging` |
| Gaps in time series | Investigate source; document expected gaps |
| Valid range | Partition `curated` by date; export to `output` |

## Related Pages

- [Null profile](null_profile.md)
- [Row counts](row_counts.md)
- [Numeric summary](numeric_summary.md)
- [Outlier scan](outlier_scan.md)

Official reference: [DuckDB date functions](https://duckdb.org/docs/current/sql/functions/date.html)
