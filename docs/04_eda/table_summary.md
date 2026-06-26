# Table Summary

Single-call column profile for a DuckDB table — dtypes, nulls, cardinality, top values, numeric stats, and outlier counts — built from **SQL templates** with a minimal Python wrapper.

## Purpose

`get_table_summary()` mirrors the layout of a pandas `get_df_summary()` output but runs aggregates in DuckDB. The table stays in the database; Python only orchestrates SQL and assembles the result matrix.

Use it as a consolidated first pass after [schema inspection](schema_inspection.md). The existing notebook sections for [null profile](null_profile.md), [distinct profile](distinct_profile.md), [numeric summary](numeric_summary.md), and [outlier scan](outlier_scan.md) remain for deeper SQL-first profiling.

## When to Use

- After ingest — one overview before column-specific SQL
- On any `raw`, `staging`, or `curated` table registered in DuckDB
- When you want the transposed property layout (dtype / nulls / top values / stats per column)
- Prefer this over loading the full table into pandas for wide profiling

## SQL Building Blocks

The wrapper composes these patterns (implemented in `python/eda_helpers.py`).

### Column list and types

```sql
DESCRIBE raw.raw_orders;
```

### Null counts (all columns)

```sql
WITH base AS (
  SELECT * FROM raw.raw_orders
),
metrics AS (
  SELECT 'order_id' AS column_name, COUNT(*) - COUNT("order_id") AS null_count FROM base
  UNION ALL
  SELECT 'amount', COUNT(*) - COUNT("amount") FROM base
)
SELECT
  column_name,
  null_count,
  (SELECT COUNT(*) FROM base) AS total_rows,
  ROUND(100.0 * null_count / (SELECT COUNT(*) FROM base), 2) AS null_pct
FROM metrics
ORDER BY null_count DESC;
```

Use `generate_null_profile_sql(table, columns)` to build this dynamically.

### Distinct counts (all columns)

```sql
WITH base AS (SELECT * FROM raw.raw_orders)
SELECT 'order_id' AS column_name, COUNT(DISTINCT "order_id") AS distinct_count FROM base
UNION ALL
SELECT 'order_status', COUNT(DISTINCT "order_status") FROM base
ORDER BY distinct_count DESC;
```

Use `generate_distinct_profile_sql(table, columns)`.

### Top-N values (one column)

```sql
SELECT
  CAST("order_status" AS VARCHAR) AS value,
  COUNT(*) AS row_count,
  100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS pct
FROM raw.raw_orders
GROUP BY 1
ORDER BY row_count DESC
LIMIT 10;
```

Use `generate_top_values_sql(table, column, top_n=10)`. The wrapper runs this once per column and formats `value (pct%)` strings.

### Numeric stats (one column)

```sql
SELECT
  MIN("amount") AS min,
  MAX("amount") AS max,
  quantile_cont("amount", 0.25) AS q1,
  quantile_cont("amount", 0.5) AS median,
  quantile_cont("amount", 0.75) AS q3,
  AVG("amount") AS mean,
  STDDEV_SAMP("amount") AS std
FROM raw.raw_orders
WHERE "amount" IS NOT NULL;
```

Use `generate_numeric_column_stats_sql(table, column)`.

### Outlier counts (one column, after bounds computed)

```sql
SELECT COUNT(*) AS outlier_count
FROM raw.raw_orders
WHERE "amount" IS NOT NULL
  AND ("amount" < 0.8 OR "amount" > 41.0);
```

Bounds (`LW (1.5)`, `UW (1.5)`, `mean±3*std`) are computed in Python from the stats row, then `generate_outlier_count_sql(table, column, lower=…, upper=…)` returns the count.

### Table size (catalog estimate)

```sql
SELECT estimated_size
FROM duckdb_tables()
WHERE schema_name = 'raw' AND table_name = 'raw_orders';
```

Printed as a memory-style header (KB / MB / GB).

## Notebook Usage

```python
import sys

sys.path.insert(0, str(PROJECT_ROOT / "python"))

from eda_helpers import get_table_summary

table_summary = get_table_summary(
    con,
    "raw.raw_orders",
    print_summary=False,
    properties_as_columns=False,
    top_n=10,
)
table_summary
```

Parameters:

| Parameter | Default | Notes |
|-----------|---------|-------|
| `print_summary` | `True` | Set `False` when displaying the returned DataFrame |
| `properties_as_columns` | `True` | Set `False` for columns-as-fields layout (see sample below) |
| `top_n` | `10` | Top values per column |
| `exclude` | `None` | Column names to skip (e.g. geometry blobs) |

Practice dataset:

```python
get_table_summary(con, "raw.raw_population_csv", properties_as_columns=False)
```

## Expected Output

With `properties_as_columns=False`, each **source column** is a **column** in the summary; each **row** is a profile property:

| | order_id | customer_id | amount | order_status |
|---|----------|-------------|--------|--------------|
| dtype | BIGINT | BIGINT | DOUBLE | VARCHAR |
| Missing Counts | 0 | 10 | 150 | 0 |
| nUniques | 10000 | 4500 | 8200 | 5 |
| Top 10 Unique Values | 1 (0%), 2 (0%), … | … | 14.76 (4%), … | completed (62%), … |
| min | 1.0 | 1.0 | 0.5 | nan |
| Q1 | … | … | 13.9 | nan |
| Outlier Count (1.5*IQR) | 0 | 42 (0.4%) | 300 (2.8%) | nan |

Non-numeric columns show `nan` for numeric stat rows. Columns are sorted by `dtype` (descending).

Console header:

```text
RangeIndex: 10000 entries; Data columns (total 8 columns)
memory usage: 1.2+ MB
```

## What Each Row Covers

| Row | Equivalent EDA page |
|-----|---------------------|
| `dtype` | [Schema inspection](schema_inspection.md) |
| `Missing Counts` | [Null profile](null_profile.md) |
| `nUniques` | [Distinct profile](distinct_profile.md) |
| `Top N Unique Values` | [Categorical frequency](categorical_frequency.md) |
| `min` … `std` | [Numeric summary](numeric_summary.md) |
| `LW (1.5)` / `UW (1.5)` + IQR outlier count | [Outlier scan](outlier_scan.md) |
| `mean±3*std` + std outlier count | [Outlier scan](outlier_scan.md) |

## Common Variations

### Exclude geometry columns

```python
get_table_summary(con, "raw.raw_parcels_gdb", exclude=["geom"], properties_as_columns=False)
```

### Profile staging layer

```python
get_table_summary(con, "staging.stg_orders", properties_as_columns=False)
```

### Run SQL building blocks directly (no wrapper)

```python
from eda_helpers import (
    generate_null_profile_sql,
    generate_top_values_sql,
    list_table_columns,
)

cols = [name for name, _ in list_table_columns(con, "raw.raw_orders")]
con.sql(generate_null_profile_sql("raw.raw_orders", cols)).df()
con.sql(generate_top_values_sql("raw.raw_orders", "order_status")).df()
```

## Interpretation Guidance

- **High `nUniques` on IDs** — expected; confirm with [duplicate check](duplicate_check.md).
- **Non-zero `Missing Counts` on keys** — fix in `staging` before joins.
- **IQR vs 3σ outlier counts differ** — skewed data; prefer IQR for revenue-like fields.
- **Top-N on high-cardinality columns** — truncated preview only; use [distinct profile](distinct_profile.md) for full cardinality.

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Nulls on join keys | [Null profile](null_profile.md) + `staging` fixes |
| High outlier counts | [Outlier scan](outlier_scan.md) for row-level detail |
| Wrong dtypes | Re-ingest or cast in `staging` |
| Clean profile | Validation or `curated` build |

## Related Pages

- [Schema inspection](schema_inspection.md)
- [Null profile](null_profile.md)
- [Distinct profile](distinct_profile.md)
- [Numeric summary](numeric_summary.md)
- [Outlier scan](outlier_scan.md)

Official references: [DuckDB aggregates](https://duckdb.org/docs/current/sql/functions/aggregates.html), [quantile_cont](https://duckdb.org/docs/current/sql/functions/aggregates.html#quantile)
