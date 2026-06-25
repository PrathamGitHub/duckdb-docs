# Missing Values

Handle `NULL`, empty strings, and placeholder sentinels in `raw` tables using `COALESCE` and related patterns in `staging`.

## Purpose

Define explicit rules for missing data: replace sentinels with `NULL`, fill defaults with `COALESCE`, and document imputation so downstream `curated` models behave predictably.

## When to Use

- After [null profile](../04_eda/null_profile.md) flags high null rates or sentinel values (`-1`, `N/A`, `unknown`)
- Before joins where null keys cause row loss
- When optional attributes need defaults for reporting (not for primary keys)
- After [safe casting](safe_casting.md) when `TRY_CAST` produces `NULL` for bad values

## SQL Template

Replace sentinels, then default with `COALESCE`:

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  customer_id,
  order_date,
  COALESCE(
    NULLIF(TRIM(order_status), ''),
    'unknown'
  ) AS order_status,
  COALESCE(amount, 0.0) AS amount
FROM raw.raw_orders;
```

Sentinel cleanup before `COALESCE`:

```sql
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT
  customer_id,
  TRIM(customer_name) AS customer_name,
  COALESCE(
    NULLIF(LOWER(TRIM(email)), 'n/a'),
    NULLIF(LOWER(TRIM(email)), 'none')
  ) AS email,
  COALESCE(
    NULLIF(TRY_CAST(loyalty_points AS INTEGER), -1),
    0
  ) AS loyalty_points
FROM raw.raw_customers;
```

Flag imputed rows for audit:

```sql
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  COALESCE(amount, 0.0) AS amount,
  amount IS NULL AS was_amount_imputed
FROM raw.raw_orders;
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

# Null profile before cleaning
con.sql("""
  SELECT
    COUNT(*) AS total,
    COUNT(*) - COUNT(value) AS null_value,
    COUNT(*) - COUNT(country_name) AS null_country
  FROM raw.raw_population_csv
""").df()
```

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  COALESCE(TRY_CAST(value AS DOUBLE), 0.0) AS population,
  TRY_CAST(value AS DOUBLE) IS NULL AS was_population_imputed
FROM raw.raw_population_csv
WHERE TRIM(country_name) IS NOT NULL
  AND TRIM(country_name) <> '';
""")

imputed = con.sql("""
  SELECT COUNT(*) AS imputed_rows
  FROM staging.stg_population
  WHERE was_population_imputed
""").df()
imputed
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_orders` | Source with nulls/sentinels |
| `{stg_table}` | `staging.stg_orders` | Cleaned output |
| Sentinel values | `'N/A'`, `-1`, `''` | Map to `NULL` with `NULLIF` |
| Default value | `0`, `'unknown'` | Second arg to `COALESCE` |
| Audit flag | `was_amount_imputed` | Boolean for traceability |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Example: `raw.raw_orders` — nulls, blanks, and placeholders.

| order_id | order_status | amount |
|----------|--------------|--------|
| ORD-001 | shipped | 99.50 |
| ORD-002 | | NULL |
| ORD-003 | N/A | -1 |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_orders` — explicit defaults; optional imputation flags.

| order_id | order_status | amount | was_amount_imputed |
|----------|--------------|--------|--------------------|
| ORD-001 | shipped | 99.50 | false |
| ORD-002 | unknown | 0.0 | true |
| ORD-003 | unknown | 0.0 | true |

## Validation Checks

```sql
-- Required keys must remain non-null
SELECT COUNT(*) AS null_keys
FROM staging.stg_orders
WHERE order_id IS NULL;
```

```sql
-- Imputation rate for optional fields
SELECT
  COUNT(*) AS total_rows,
  SUM(CASE WHEN was_amount_imputed THEN 1 ELSE 0 END) AS imputed_count,
  ROUND(100.0 * SUM(CASE WHEN was_amount_imputed THEN 1 ELSE 0 END) / COUNT(*), 2) AS imputed_pct
FROM staging.stg_orders;
```

```sql
-- No sentinel strings left in cleaned text columns
SELECT COUNT(*) AS bad_status
FROM staging.stg_orders
WHERE LOWER(order_status) IN ('n/a', 'none', '');
```

## Common Variations

### `COALESCE` chain (first non-null wins)

```sql
COALESCE(work_email, personal_email, 'no-email@placeholder.local') AS contact_email
```

### `IFNULL` alias (same as two-arg `COALESCE`)

```sql
IFNULL(region_code, 'UNK') AS region_code
```

### Do not impute primary keys — filter instead

```sql
SELECT *
FROM raw.raw_orders
WHERE order_id IS NOT NULL;
```

### Spatial: null geometry handling

Filter or flag in `staging` — do not use `COALESCE` on geometry columns:

```sql
SELECT
  parcel_id,
  geom,
  geom IS NULL AS has_null_geometry
FROM raw.raw_parcels
WHERE geom IS NOT NULL;  -- or keep all with flag
```

See [spatial geometry cleaning](spatial_geometry_cleaning.md).

### Forward-fill with window functions (time series)

```sql
SELECT
  country_name,
  year,
  COALESCE(
    population,
    LAST_VALUE(population IGNORE NULLS) OVER (
      PARTITION BY country_name ORDER BY year
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
  ) AS population_filled
FROM staging.stg_population;
```

## Known Limitations

- `COALESCE` defaults hide data quality issues — always profile nulls in `raw` first.
- Imputing `0` for missing amounts skews aggregates — prefer `NULL` for analytics or use explicit flags.
- `COALESCE` evaluates arguments left to right — expensive expressions run even if an earlier arg is non-null (usually fine for literals).
- Filling missing join keys creates orphan relationships — never impute foreign keys.

## Related Pages

- [Null profile](../04_eda/null_profile.md)
- [Safe casting](safe_casting.md)
- [Text cleaning](text_cleaning.md)
- [Spatial geometry cleaning](spatial_geometry_cleaning.md)

Official reference: [COALESCE](https://duckdb.org/docs/current/sql/functions/utility.html)
