# Text Cleaning

Normalize string columns from messy `raw` ingest into consistent, join-ready text in `staging`.

## Purpose

Remove leading/trailing whitespace, standardize case, and collapse common text noise so keys, categories, and free-text fields match across sources and downstream joins.

## When to Use

- After CSV or Excel ingest when columns contain padded IDs, mixed case, or stray characters
- Before deduplication on text keys (`email`, `customer_name`, `region_code`)
- Before [safe casting](safe_casting.md) when numeric columns arrive as strings with spaces
- When [categorical frequency](../04_eda/categorical_frequency.md) shows duplicate values that differ only by case or spacing

## SQL Template

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  LOWER(TRIM(country_code)) AS country_code,
  UPPER(TRIM(region)) AS region,
  year,
  value
FROM raw.raw_population_csv
WHERE TRIM(country_name) <> '';
```

Whitespace and case on a business key:

```sql
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT
  customer_id,
  TRIM(customer_name) AS customer_name,
  LOWER(TRIM(email)) AS email,
  TRIM(phone) AS phone
FROM raw.raw_customers;
```

Replace empty strings with `NULL` after trim:

```sql
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  NULLIF(TRIM(order_status), '') AS order_status,
  amount
FROM raw.raw_orders;
```

## Notebook Usage

```python
# Practice dataset — population CSV from GitHub
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  LOWER(TRIM(country_code)) AS country_code,
  CAST(year AS INTEGER) AS year,
  CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE TRIM(country_name) <> '';
""")

# Spot-check distinct values before/after
con.sql("""
  SELECT 'raw' AS layer, country_name, COUNT(*) AS n
  FROM raw.raw_population_csv
  GROUP BY 1, 2
  HAVING COUNT(*) > 100
  ORDER BY n DESC
  LIMIT 5
""").df()
```

```python
con.sql("""
  SELECT country_name, COUNT(*) AS n
  FROM staging.stg_population
  GROUP BY 1
  ORDER BY n DESC
  LIMIT 10
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_population_csv` | Source table |
| `{stg_table}` | `staging.stg_population` | Cleaned output |
| Text columns | `country_name`, `email` | Apply `TRIM` / `LOWER` / `UPPER` |
| Case rule | `LOWER` for emails; `UPPER` for codes | Match business convention |
| Empty filter | `WHERE TRIM(col) <> ''` | Drop blank rows early |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Example: `raw.raw_population_csv` — strings as-ingested, possibly padded or mixed case.

| country_name | country_code | year | value |
|--------------|--------------|------|-------|
| ` United States ` | `us` | 2020 | 331002651 |
| `FRANCE` | ` FR ` | 2020 | 65273511 |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_population` — trimmed, consistently cased text.

| country_name | country_code | year | population |
|--------------|--------------|------|------------|
| United States | us | 2020 | 331002651.0 |
| FRANCE | fr | 2020 | 65273511.0 |

## Validation Checks

```sql
-- No leading/trailing spaces remain
SELECT COUNT(*) AS bad_trim
FROM staging.stg_population
WHERE country_name <> TRIM(country_name)
   OR country_code <> TRIM(country_code);
```

```sql
-- Country codes are lowercase after LOWER
SELECT COUNT(*) AS not_lower
FROM staging.stg_population
WHERE country_code <> LOWER(country_code);
```

```sql
-- Row count should not drop unexpectedly (compare to raw minus blanks)
SELECT
  (SELECT COUNT(*) FROM raw.raw_population_csv) AS raw_rows,
  (SELECT COUNT(*) FROM staging.stg_population) AS stg_rows;
```

## Common Variations

### Collapse internal whitespace

DuckDB does not ship `REGEXP_REPLACE` in all builds; use `REPLACE` for simple double spaces:

```sql
TRIM(REPLACE(REPLACE(column_name, CHR(9), ' '), '  ', ' ')) AS column_name
```

### Strip non-printable characters

```sql
TRIM(REGEXP_REPLACE(column_name, '[^[:print:]]', '', 'g')) AS column_name
```

### Title case for display names (when not using `LOWER`/`UPPER`)

```sql
INITCAP(TRIM(customer_name)) AS customer_name
```

### Text cleaning before deduplication

```sql
SELECT
  LOWER(TRIM(email)) AS email_key,
  *
FROM raw.raw_customers;
```

See [deduplication](deduplication.md) for `ROW_NUMBER()` on cleaned keys.

## Known Limitations

- `TRIM` removes spaces only at ends — internal tabs or double spaces need extra handling.
- `LOWER` / `UPPER` are locale-insensitive; some Unicode case mappings may not match application expectations.
- Cleaning in `staging` does not fix source encoding issues — inspect `raw` bytes or re-ingest with correct encoding.
- Over-aggressive `WHERE TRIM(col) <> ''` can drop rows you intended to impute — use [missing values](missing_values.md) instead.

## Related Pages

- [Column standardization](column_standardization.md)
- [Safe casting](safe_casting.md)
- [Deduplication](deduplication.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB string functions](https://duckdb.org/docs/current/sql/functions/char.html)
