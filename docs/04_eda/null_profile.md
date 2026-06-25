# Null Profile

Count and percentage of null values per column to prioritize cleaning in `staging`.

## Purpose

Quantify missingness across all columns (or a critical subset) so you can set data-quality thresholds before joins and exports.

## When to Use

- After ingest on `raw.raw_orders` and `raw.raw_customers`
- Before defining `staging` `NOT NULL` constraints or join keys
- When preview rows show sporadic nulls — confirm overall rates
- Regression check after upstream source changes

## SQL Template

### Static SQL (explicit columns)

Best when you know the critical fields and want a readable, version-controlled query:

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(order_id) AS order_id_non_null,
  COUNT(*) - COUNT(order_id) AS order_id_null,
  ROUND(100.0 * (COUNT(*) - COUNT(order_id)) / COUNT(*), 2) AS order_id_null_pct,
  COUNT(customer_id) AS customer_id_non_null,
  COUNT(*) - COUNT(customer_id) AS customer_id_null,
  ROUND(100.0 * (COUNT(*) - COUNT(customer_id)) / COUNT(*), 2) AS customer_id_null_pct,
  COUNT(order_date) AS order_date_non_null,
  COUNT(*) - COUNT(order_date) AS order_date_null,
  ROUND(100.0 * (COUNT(*) - COUNT(order_date)) / COUNT(*), 2) AS order_date_null_pct,
  COUNT(amount) AS amount_non_null,
  COUNT(*) - COUNT(amount) AS amount_null,
  ROUND(100.0 * (COUNT(*) - COUNT(amount)) / COUNT(*), 2) AS amount_null_pct
FROM raw.raw_orders;
```

Unpivot-style null profile (one row per column) for a fixed column list:

```sql
WITH base AS (
  SELECT * FROM staging.stg_orders
),
metrics AS (
  SELECT 'order_id' AS column_name, COUNT(*) - COUNT(order_id) AS null_count FROM base
  UNION ALL SELECT 'customer_id', COUNT(*) - COUNT(customer_id) FROM base
  UNION ALL SELECT 'order_date', COUNT(*) - COUNT(order_date) FROM base
  UNION ALL SELECT 'amount', COUNT(*) - COUNT(amount) FROM base
  UNION ALL SELECT 'order_status', COUNT(*) - COUNT(order_status) FROM base
)
SELECT
  column_name,
  null_count,
  (SELECT COUNT(*) FROM base) AS total_rows,
  ROUND(100.0 * null_count / (SELECT COUNT(*) FROM base), 2) AS null_pct
FROM metrics
ORDER BY null_count DESC;
```

### Python-generated dynamic SQL

Use when tables are wide, columns change often, or you profile many tables in one notebook cell:

```python
def null_profile_sql(schema: str, table: str, exclude: list[str] | None = None) -> str:
    exclude = exclude or []
    cols = con.sql(f"""
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = '{schema}' AND table_name = '{table}'
      ORDER BY ordinal_position
    """).df()["column_name"].tolist()

    cols = [c for c in cols if c not in exclude]
    if not cols:
        raise ValueError(f"No columns to profile on {schema}.{table}")

    parts = []
    for col in cols:
        parts.append(f"""
  SELECT '{col}' AS column_name,
    COUNT(*) AS total_rows,
    COUNT("{col}") AS non_null_count,
    COUNT(*) - COUNT("{col}") AS null_count,
    ROUND(100.0 * (COUNT(*) - COUNT("{col}")) / COUNT(*), 4) AS null_pct
  FROM {schema}.{table}
""")
    return "\nUNION ALL\n".join(parts) + "\nORDER BY null_count DESC;"

sql = null_profile_sql("raw", "raw_orders", exclude=["geom"])
con.sql(sql).df()
```

Flag columns above a threshold:

```python
THRESHOLD_PCT = 5.0
profile = con.sql(null_profile_sql("raw", "raw_customers")).df()
flags = profile[profile["null_pct"] > THRESHOLD_PCT]
flags
```

## Notebook Usage

```python
# Static — paste SQL for known order columns
con.sql("""
  WITH base AS (SELECT * FROM raw.raw_orders)
  SELECT 'customer_id' AS column_name,
    COUNT(*) - COUNT(customer_id) AS null_count,
    ROUND(100.0 * (COUNT(*) - COUNT(customer_id)) / COUNT(*), 2) AS null_pct
  FROM base
""").df()

# Dynamic — full table profile
display(con.sql(null_profile_sql("staging", "stg_orders")).df())
```

Practice dataset:

```python
display(con.sql(null_profile_sql("raw", "raw_population_csv")).df())
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_orders` | Target table |
| Column list | `order_id`, `amount` | Static SQL columns |
| `exclude` | `['geom', 'wkb_geometry']` | Skip blobs in dynamic SQL |
| `THRESHOLD_PCT` | `5.0` | Flag for follow-up |

## Expected Output

| column_name | total_rows | non_null_count | null_count | null_pct |
|-------------|------------|----------------|------------|----------|
| amount | 10000 | 9850 | 150 | 1.5 |
| customer_id | 10000 | 9990 | 10 | 0.1 |

Sorted by `null_count` descending in dynamic queries.

## Common Variations

### Critical keys only (fast gate)

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(order_id) AS order_id_ok,
  COUNT(customer_id) AS customer_id_ok
FROM raw.raw_orders
HAVING COUNT(order_id) < COUNT(*) OR COUNT(customer_id) < COUNT(*);
```

### Null profile after join

```sql
SELECT
  COUNT(*) AS joined_rows,
  COUNT(o.order_id) AS order_id_non_null,
  COUNT(c.customer_id) AS customer_id_non_null
FROM staging.stg_orders o
LEFT JOIN raw.raw_customers c ON o.customer_id = c.customer_id;
```

### Empty string vs NULL (CSV ingest)

```sql
SELECT
  COUNT(*) FILTER (WHERE order_status IS NULL) AS null_status,
  COUNT(*) FILTER (WHERE order_status = '') AS empty_string_status
FROM raw.raw_orders;
```

## Interpretation Guidance

- **0% null on primary keys** — expected; any nulls block `curated` grain — fix in `staging` or re-ingest.
- **High null on optional attributes** — may be acceptable; document for consumers.
- **Sudden null spike vs prior run** — upstream breakage; compare counts across ingest dates.
- **Empty strings ≠ NULL** — common in CSV; normalize in `staging` (`NULLIF(TRIM(col), '')`).

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Nulls on join keys | Filter or impute in `staging`; do not join until resolved |
| High null on measures | Exclude from aggregates or flag in `curated` |
| Empty strings | Text cleaning in `staging` |
| All columns clean | [duplicate_check](duplicate_check.md), [numeric_summary](numeric_summary.md) |

## Related Pages

- [Schema inspection](schema_inspection.md)
- [Distinct profile](distinct_profile.md)
- [Duplicate check](duplicate_check.md)
- [Row counts](row_counts.md)

Official reference: [DuckDB COUNT](https://duckdb.org/docs/current/sql/functions/aggregates.html#count)
