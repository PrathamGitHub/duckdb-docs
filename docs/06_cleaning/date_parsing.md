# Date Parsing

Parse and standardize date and timestamp columns from `raw` into consistent `DATE` or `TIMESTAMP` types in `staging`.

## Purpose

Turn heterogeneous date strings (`01/15/2024`, `2024-01-15T10:30:00`, epoch integers) into typed temporal columns for filtering, joins, and time-series analysis.

## When to Use

- After CSV/JSON ingest when date columns are `VARCHAR`
- Before [date range check](../04_eda/date_range_check.md) or window functions ordered by time
- When source systems mix US and ISO date formats
- Alongside [safe casting](safe_casting.md) for `TRY_CAST(... AS DATE)`

## SQL Template

ISO-style strings with `TRY_CAST`:

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  customer_id,
  TRY_CAST(order_date AS DATE) AS order_date,
  TRY_CAST(created_at AS TIMESTAMP) AS created_at,
  amount
FROM raw.raw_orders
WHERE TRY_CAST(order_date AS DATE) IS NOT NULL;
```

Explicit format with `STRPTIME` (when `TRY_CAST` is ambiguous):

```sql
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  STRPTIME(TRIM(order_date), '%m/%d/%Y')::DATE AS order_date,
  STRPTIME(TRIM(created_at), '%Y-%m-%d %H:%M:%S') AS created_at,
  amount
FROM raw.raw_orders;
```

Epoch seconds to timestamp:

```sql
SELECT
  event_id,
  epoch_ms(event_ts_ms) AS event_at
FROM raw.raw_events;
```

## Notebook Usage

```python
# Practice: build a small raw table with mixed date strings
con.execute("""
CREATE OR REPLACE TABLE raw.raw_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', '2024-01-15', 99.50),
  ('ORD-002', 'C-101', '01/20/2024', 45.00),
  ('ORD-003', 'C-102', 'not-a-date', 10.00)
) AS t(order_id, customer_id, order_date, amount);
""")

con.sql("""
  SELECT
    order_date AS raw_value,
    TRY_CAST(order_date AS DATE) AS try_cast_date,
    TRY_STRPTIME(order_date, '%m/%d/%Y')::DATE AS us_format_date
  FROM raw.raw_orders
""").df()
```

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  customer_id,
  COALESCE(
    TRY_CAST(order_date AS DATE),
    TRY_STRPTIME(order_date, '%m/%d/%Y')::DATE
  ) AS order_date,
  amount
FROM raw.raw_orders
WHERE COALESCE(
    TRY_CAST(order_date AS DATE),
    TRY_STRPTIME(order_date, '%m/%d/%Y')::DATE
  ) IS NOT NULL;
""")

con.sql("SELECT * FROM staging.stg_orders ORDER BY order_date").df()
```

Population dataset — year as integer (not a full date, but common temporal key):

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  MAKE_DATE(TRY_CAST(year AS INTEGER), 1, 1) AS year_start_date,
  TRY_CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE TRY_CAST(year AS INTEGER) IS NOT NULL;
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_orders` | Source with date strings |
| `{stg_table}` | `staging.stg_orders` | Typed output |
| Date column | `order_date`, `effective_date` | One or more columns |
| Target type | `DATE`, `TIMESTAMP` | Use `TIMESTAMP` when time matters |
| Format string | `'%m/%d/%Y'`, `'%Y-%m-%d'` | For `STRPTIME` / `TRY_STRPTIME` |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Example: `raw.raw_orders` — dates as strings in mixed formats.

| order_id | order_date | amount |
|----------|------------|--------|
| ORD-001 | 2024-01-15 | 99.50 |
| ORD-002 | 01/20/2024 | 45.00 |
| ORD-003 | not-a-date | 10.00 |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_orders` — `DATE` / `TIMESTAMP` columns; unparseable rows excluded.

| order_id | order_date | amount |
|----------|------------|--------|
| ORD-001 | 2024-01-15 | 99.50 |
| ORD-002 | 2024-01-20 | 45.00 |

## Validation Checks

```sql
-- No null dates in required column
SELECT COUNT(*) AS null_order_date
FROM staging.stg_orders
WHERE order_date IS NULL;
```

```sql
-- Date range sanity
SELECT
  MIN(order_date) AS min_date,
  MAX(order_date) AS max_date,
  COUNT(*) AS row_count
FROM staging.stg_orders;
```

```sql
-- Unparsed rows quarantined in raw
SELECT o.*
FROM raw.raw_orders o
LEFT JOIN staging.stg_orders s USING (order_id)
WHERE s.order_id IS NULL;
```

## Common Variations

### `TRY_STRPTIME` (safe parse)

```sql
TRY_STRPTIME(TRIM(order_date), '%d-%b-%Y')::DATE AS order_date
```

Returns `NULL` instead of error on bad input.

### Multiple format fallbacks with `COALESCE`

```sql
COALESCE(
  TRY_CAST(order_date AS DATE),
  TRY_STRPTIME(order_date, '%m/%d/%Y')::DATE,
  TRY_STRPTIME(order_date, '%d-%b-%Y')::DATE
) AS order_date
```

### Extract date parts for validation

```sql
SELECT
  order_date,
  EXTRACT(YEAR FROM order_date) AS order_year,
  EXTRACT(MONTH FROM order_date) AS order_month
FROM staging.stg_orders;
```

### Truncate timestamp to date

```sql
CAST(created_at AS DATE) AS created_date
```

## Known Limitations

- Ambiguous formats (`01/02/2024`) cannot be resolved without a declared format — document source locale.
- `TRY_CAST` on dates works best for ISO `YYYY-MM-DD`; US formats need `STRPTIME`.
- Time zones are not preserved unless stored explicitly — `TIMESTAMP WITH TIME ZONE` support varies by DuckDB version.
- `MAKE_DATE` returns `NULL` for invalid year/month/day combinations — validate with [safe casting](safe_casting.md).

## Related Pages

- [Safe casting](safe_casting.md)
- [Missing values](missing_values.md)
- [Date range check](../04_eda/date_range_check.md)

Official reference: [Date formatting functions](https://duckdb.org/docs/current/sql/functions/timestamp.html)
