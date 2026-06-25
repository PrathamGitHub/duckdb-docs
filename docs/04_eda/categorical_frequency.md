# Categorical Frequency

Count rows per category value for low-cardinality columns — status codes, regions, product types.

## Purpose

Produce value-count tables (bar-chart ready) to understand category mix, rare levels, and unexpected enum values.

## When to Use

- After [distinct_profile](distinct_profile.md) shows low cardinality (`order_status`, `ship_region`)
- Validating domain codes from GIS or vendor feeds
- Before one-hot encoding or dimension tables in `curated`
- Communicating data mix to stakeholders in notebooks

## SQL Template

Basic frequency table:

```sql
SELECT
  order_status,
  COUNT(*) AS row_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM staging.stg_orders
GROUP BY order_status
ORDER BY row_count DESC;
```

Include null bucket:

```sql
SELECT
  COALESCE(order_status, '(null)') AS order_status,
  COUNT(*) AS row_count
FROM raw.raw_orders
GROUP BY 1
ORDER BY row_count DESC;
```

Top-N categories (collapse long tail):

```sql
SELECT *
FROM (
  SELECT
    ship_region,
    COUNT(*) AS row_count,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
  FROM staging.stg_orders
  GROUP BY ship_region
) t
WHERE rn <= 10
ORDER BY row_count DESC;
```

Cross-tab (two categoricals):

```sql
SELECT
  order_status,
  ship_region,
  COUNT(*) AS row_count
FROM staging.stg_orders
GROUP BY 1, 2
ORDER BY row_count DESC;
```

## Notebook Usage

```python
freq = con.sql("""
  SELECT order_status, COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
  FROM staging.stg_orders
  GROUP BY 1
  ORDER BY n DESC
""").df()
freq.plot.bar(x="order_status", y="n", title="Orders by status")
```

Customer segment mix:

```python
con.sql("""
  SELECT customer_segment, COUNT(*) AS customers
  FROM raw.raw_customers
  GROUP BY 1
  ORDER BY customers DESC
""").df()
```

Practice dataset — records per year:

```python
con.sql("""
  SELECT year, COUNT(*) AS country_rows
  FROM raw.raw_population_csv
  GROUP BY year
  ORDER BY year
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Category column | `order_status`, `customer_segment` | Low cardinality preferred |
| `{schema}.{table}` | `staging.stg_orders` | Any workflow layer |
| Top-N | `10` | Long-tail collapse |
| Second dimension | `ship_region` | Cross-tab only |

## Expected Output

| order_status | row_count | pct |
|--------------|-----------|-----|
| completed | 6200 | 62.00 |
| pending | 2100 | 21.00 |
| cancelled | 900 | 9.00 |
| returned | 800 | 8.00 |

## Common Variations

### Frequency with minimum count filter

```sql
SELECT order_status, COUNT(*) AS row_count
FROM staging.stg_orders
GROUP BY 1
HAVING COUNT(*) >= 100
ORDER BY row_count DESC;
```

### Normalize case before counting

```sql
SELECT
  LOWER(TRIM(order_status)) AS order_status,
  COUNT(*) AS row_count
FROM raw.raw_orders
GROUP BY 1
ORDER BY row_count DESC;
```

### Rare level alert (less than 1%)

```sql
WITH freq AS (
  SELECT
    order_status,
    COUNT(*) AS row_count,
    100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS pct
  FROM staging.stg_orders
  GROUP BY 1
)
SELECT * FROM freq WHERE pct < 1.0 ORDER BY row_count;
```

### GIS domain code frequency

```sql
SELECT zoning_code, COUNT(*) AS parcel_count
FROM staging.stg_parcels
GROUP BY 1
ORDER BY parcel_count DESC;
```

## Interpretation Guidance

- **Unexpected category strings** — typos or new upstream codes; map in `staging`.
- **Single dominant category (>95%)** — model may be degenerate; confirm filter logic.
- **Many rare levels** — consider bucketing to `OTHER` in `curated`.
- **Null bucket large** — pair with [null_profile](null_profile.md).

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Typos / inconsistent labels | Text cleaning in `staging` |
| New enum values | Update reference mapping table |
| Imbalanced classes | Document for ML or sampling |
| Clean categories | Build dimension table in `curated` |

## Related Pages

- [Distinct profile](distinct_profile.md)
- [Null profile](null_profile.md)
- [Numeric summary](numeric_summary.md)
- [Preview rows](preview_rows.md)

Official reference: [DuckDB window functions](https://duckdb.org/docs/current/sql/functions/window_functions.html)
