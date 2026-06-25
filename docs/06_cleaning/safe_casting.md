# Safe Casting

Convert string and loosely typed columns to proper SQL types without failing the entire `staging` build.

## Purpose

Use `TRY_CAST` (and related patterns) to coerce values from `raw` into `INTEGER`, `DOUBLE`, `DATE`, and other types while turning bad values into `NULL` instead of query errors.

## When to Use

- After CSV/JSON ingest when numeric and date columns arrive as `VARCHAR`
- Before joins and aggregates that require typed keys
- When [numeric summary](../04_eda/numeric_summary.md) or [date range check](../04_eda/date_range_check.md) needs typed columns
- Alongside [text cleaning](text_cleaning.md) when values include spaces or currency symbols

## SQL Template

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE TRY_CAST(year AS INTEGER) IS NOT NULL
  AND TRY_CAST(value AS DOUBLE) IS NOT NULL;
```

Audit cast failures before filtering:

```sql
SELECT
  year AS year_raw,
  value AS value_raw,
  TRY_CAST(year AS INTEGER) AS year_cast,
  TRY_CAST(value AS DOUBLE) AS value_cast
FROM raw.raw_population_csv
WHERE TRY_CAST(year AS INTEGER) IS NULL
   OR TRY_CAST(value AS DOUBLE) IS NULL
LIMIT 50;
```

Boolean from text flags:

```sql
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT
  customer_id,
  customer_name,
  CASE
    WHEN LOWER(TRIM(is_active)) IN ('true', 't', 'yes', 'y', '1') THEN TRUE
    WHEN LOWER(TRIM(is_active)) IN ('false', 'f', 'no', 'n', '0') THEN FALSE
    ELSE TRY_CAST(is_active AS BOOLEAN)
  END AS is_active
FROM raw.raw_customers;
```

## Notebook Usage

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")

# Profile cast failures
failures = con.sql("""
  SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE TRY_CAST(year AS INTEGER) IS NULL) AS bad_year,
    COUNT(*) FILTER (WHERE TRY_CAST(value AS DOUBLE) IS NULL) AS bad_value
  FROM raw.raw_population_csv
""").df()
failures
```

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE TRY_CAST(year AS INTEGER) IS NOT NULL
  AND TRY_CAST(value AS DOUBLE) IS NOT NULL;
""")

con.sql("SELECT MIN(year), MAX(year), AVG(population) FROM staging.stg_population").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_population_csv` | Source with loose types |
| `{stg_table}` | `staging.stg_population` | Typed output |
| Target type | `INTEGER`, `DOUBLE`, `DATE`, `TIMESTAMP` | Match downstream use |
| Filter null casts | `WHERE TRY_CAST(...) IS NOT NULL` | Quarantine bad rows |
| Source column | `year`, `amount`, `order_date` | One cast per column |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Example: `raw.raw_population_csv` — numeric fields may be `VARCHAR` from `read_csv_auto`.

| country_name | year | value |
|--------------|------|-------|
| United States | 2020 | 331002651 |
| Bad Row | not_a_year | N/A |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_population` — typed columns; failed casts excluded or nulled.

| country_name | year | population |
|--------------|------|------------|
| United States | 2020 | 331002651.0 |

## Validation Checks

```sql
-- No nulls in required typed columns
SELECT
  COUNT(*) FILTER (WHERE year IS NULL) AS null_year,
  COUNT(*) FILTER (WHERE population IS NULL) AS null_population
FROM staging.stg_population;
```

```sql
-- Year range sanity check
SELECT MIN(year) AS min_year, MAX(year) AS max_year
FROM staging.stg_population;
```

```sql
-- Compare row counts: raw vs staging after cast filter
SELECT
  (SELECT COUNT(*) FROM raw.raw_population_csv) AS raw_rows,
  (SELECT COUNT(*) FROM staging.stg_population) AS stg_rows,
  (SELECT COUNT(*) FROM raw.raw_population_csv) -
    (SELECT COUNT(*) FROM staging.stg_population) AS dropped_rows;
```

## Common Variations

### `TRY_CAST` vs `CAST`

Use `CAST` only when the column is guaranteed clean; use `TRY_CAST` in `staging` pipelines:

```sql
-- Fails entire statement on one bad value
SELECT CAST(amount AS DOUBLE) FROM raw.raw_orders;

-- Returns NULL for bad values
SELECT TRY_CAST(amount AS DOUBLE) FROM raw.raw_orders;
```

### Strip currency before cast

```sql
TRY_CAST(
  REGEXP_REPLACE(TRIM(amount), '[^0-9.\-]', '', 'g') AS DOUBLE
) AS amount
```

### Cast with default via `COALESCE`

```sql
COALESCE(TRY_CAST(priority AS INTEGER), 0) AS priority
```

See [missing values](missing_values.md) for imputation patterns.

### Separate quarantine table for bad casts

```sql
CREATE OR REPLACE TABLE staging.stg_orders_bad_casts AS
SELECT *
FROM raw.raw_orders
WHERE TRY_CAST(amount AS DOUBLE) IS NULL
  AND amount IS NOT NULL;
```

## Known Limitations

- `TRY_CAST` returns `NULL` on failure — you lose the original error message unless you audit separately.
- Locale-specific decimals (`1.234,56`) need preprocessing before `TRY_CAST`.
- `TRY_CAST` to `DATE` depends on recognizable date strings — see [date parsing](date_parsing.md) for ambiguous formats.
- Silent drops from `WHERE TRY_CAST(...) IS NOT NULL` reduce row counts — always log `dropped_rows`.

## Related Pages

- [Text cleaning](text_cleaning.md)
- [Date parsing](date_parsing.md)
- [Missing values](missing_values.md)
- [Null profile](../04_eda/null_profile.md)

Official reference: [TRY_CAST](https://duckdb.org/docs/current/sql/data_types/typecasting.html)
