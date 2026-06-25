# Distinct Profile

Measure cardinality per column and surface top distinct values for categorical fields.

## Purpose

Understand how many unique values each column has, detect accidental high-cardinality categoricals, and preview dominant categories before frequency analysis.

## When to Use

- Choosing join keys — `customer_id` should be high cardinality; `order_status` should be low
- Before [categorical_frequency](categorical_frequency.md) — skip columns with millions of distinct values
- Validating dimensions: country codes, product SKUs, region IDs
- After `staging` deduplication — confirm key cardinality matches expectations

## SQL Template

### Static SQL (per-column distinct counts)

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS distinct_order_id,
  COUNT(DISTINCT customer_id) AS distinct_customer_id,
  COUNT(DISTINCT order_status) AS distinct_order_status,
  COUNT(DISTINCT CAST(order_date AS DATE)) AS distinct_order_dates
FROM staging.stg_orders;
```

Unpivoted distinct profile (fixed columns):

```sql
WITH base AS (SELECT * FROM raw.raw_orders)
SELECT 'order_id' AS column_name, COUNT(DISTINCT order_id) AS distinct_count FROM base
UNION ALL SELECT 'customer_id', COUNT(DISTINCT customer_id) FROM base
UNION ALL SELECT 'order_status', COUNT(DISTINCT order_status) FROM base
UNION ALL SELECT 'order_date', COUNT(DISTINCT order_date) FROM base
ORDER BY distinct_count DESC;
```

Top-N values for a low-cardinality column:

```sql
SELECT
  order_status,
  COUNT(*) AS row_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM raw.raw_orders
GROUP BY order_status
ORDER BY row_count DESC
LIMIT 10;
```

### Python-generated dynamic SQL

Distinct count for every column (numeric and text):

```python
def distinct_profile_sql(schema: str, table: str, exclude: list[str] | None = None) -> str:
    exclude = exclude or []
    cols = con.sql(f"""
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = '{schema}' AND table_name = '{table}'
      ORDER BY ordinal_position
    """).df()["column_name"].tolist()
    cols = [c for c in cols if c not in exclude]

    parts = []
    for col in cols:
        parts.append(f"""
  SELECT '{col}' AS column_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT "{col}") AS distinct_count,
    ROUND(100.0 * COUNT(DISTINCT "{col}") / COUNT(*), 4) AS distinct_pct_of_rows
  FROM {schema}.{table}
""")
    return "\nUNION ALL\n".join(parts) + "\nORDER BY distinct_count DESC;"

con.sql(distinct_profile_sql("raw", "raw_customers")).df()
```

Top values for selected low-cardinality columns:

```python
def top_values_sql(schema: str, table: str, column: str, n: int = 10) -> str:
    return f"""
SELECT "{column}" AS value, COUNT(*) AS row_count
FROM {schema}.{table}
GROUP BY 1
ORDER BY row_count DESC
LIMIT {n};
"""

for col in ["order_status", "ship_region"]:
    display(con.sql(top_values_sql("staging", "stg_orders", col)).df())
```

## Notebook Usage

```python
# Static cardinality check on keys
con.sql("""
  SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT customer_id) AS distinct_customers
  FROM raw.raw_orders
""").df()

# Dynamic full profile
profile = con.sql(distinct_profile_sql("staging", "stg_orders")).df()
profile
```

Practice dataset:

```python
con.sql("""
  SELECT COUNT(DISTINCT country_name) AS countries,
         COUNT(DISTINCT year) AS years
  FROM raw.raw_population_csv
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `staging.stg_orders` | Target table |
| Column list | static UNION branches | Known fields |
| `exclude` | `['geom']` | Dynamic SQL skips |
| `n` in top-N | `10` | Values per categorical column |

## Expected Output

**Distinct profile:**

| column_name | total_rows | distinct_count | distinct_pct_of_rows |
|-------------|------------|----------------|----------------------|
| order_id | 10000 | 10000 | 100.0 |
| order_status | 10000 | 5 | 0.05 |

**Top values:**

| order_status | row_count | pct |
|--------------|-----------|-----|
| completed | 6200 | 62.0 |
| pending | 2100 | 21.0 |

## Common Variations

### Cardinality ratio flag (near-duplicate keys)

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS distinct_keys,
  COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_key_rows
FROM raw.raw_orders;
```

### Distinct count approximations on huge columns

```sql
SELECT approx_count_distinct(customer_id) AS approx_customers
FROM raw.raw_orders;
```

### Composite key cardinality

```sql
SELECT COUNT(*) AS rows, COUNT(DISTINCT (customer_id, order_date)) AS distinct_pairs
FROM staging.stg_orders;
```

### Distinct profile by group

```sql
SELECT
  order_status,
  COUNT(DISTINCT customer_id) AS distinct_customers
FROM staging.stg_orders
GROUP BY order_status;
```

## Interpretation Guidance

- **`distinct_count = total_rows` on business key** — good candidate primary key; confirm with [duplicate_check](duplicate_check.md).
- **`distinct_count` very low on ID column** — mis-typed column, constant fill, or wrong ingest column.
- **`distinct_pct` near 100% on descriptive fields** — high cardinality text (names, notes); use top-N only, not full frequency tables.
- **Mismatch: many distinct `customer_id` in orders vs few in `raw_customers`** — orphan orders or incomplete customer ingest.

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Key duplicates | [duplicate_check](duplicate_check.md) |
| Low-cardinality columns | [categorical_frequency](categorical_frequency.md) |
| Numeric columns | [numeric_summary](numeric_summary.md) |
| Date columns | [date_range_check](date_range_check.md) |

## Related Pages

- [Categorical frequency](categorical_frequency.md)
- [Duplicate check](duplicate_check.md)
- [Null profile](null_profile.md)
- [Row counts](row_counts.md)

Official reference: [DuckDB DISTINCT](https://duckdb.org/docs/current/sql/query_syntax/select.html#distinct)
