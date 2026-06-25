# Deduplication

Remove duplicate rows from `raw` tables using `ROW_NUMBER()` and business rules in `staging`.

## Purpose

Enforce expected grain (one row per `order_id`, one row per `parcel_id`) when sources deliver repeats from overlapping files, bad exports, or historical snapshots.

## When to Use

- After [duplicate check](../04_eda/duplicate_check.md) finds `COUNT(*) > 1` per key
- Before promoting data to `curated` with declared primary keys
- After [text cleaning](text_cleaning.md) when duplicates differ only by case or whitespace
- When re-ingesting batches that overlap prior `raw` loads

## SQL Template

Keep latest row per business key with `ROW_NUMBER()`:

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  order_status
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY order_date DESC, amount DESC
    ) AS rn
  FROM raw.raw_orders
) ranked
WHERE rn = 1;
```

Deduplicate on composite key:

```sql
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  country_name,
  year,
  population
FROM (
  SELECT
    TRIM(country_name) AS country_name,
    TRY_CAST(year AS INTEGER) AS year,
    TRY_CAST(value AS DOUBLE) AS population,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(country_name), TRY_CAST(year AS INTEGER)
      ORDER BY TRY_CAST(value AS DOUBLE) DESC NULLS LAST
    ) AS rn
  FROM raw.raw_population_csv
) ranked
WHERE rn = 1;
```

Full-row deduplication with `DISTINCT`:

```sql
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT DISTINCT
  customer_id,
  TRIM(customer_name) AS customer_name,
  LOWER(TRIM(email)) AS email
FROM raw.raw_customers
WHERE customer_id IS NOT NULL;
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

# Check duplicates before dedupe
con.sql("""
  SELECT country_name, year, COUNT(*) AS n
  FROM raw.raw_population_csv
  GROUP BY 1, 2
  HAVING COUNT(*) > 1
  ORDER BY n DESC
  LIMIT 10
""").df()
```

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT country_name, year, population
FROM (
  SELECT
    TRIM(country_name) AS country_name,
    TRY_CAST(year AS INTEGER) AS year,
    TRY_CAST(value AS DOUBLE) AS population,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(country_name), TRY_CAST(year AS INTEGER)
      ORDER BY TRY_CAST(value AS DOUBLE) DESC
    ) AS rn
  FROM raw.raw_population_csv
) ranked
WHERE rn = 1;
""")

# Confirm zero duplicates at grain
con.sql("""
  SELECT country_name, year, COUNT(*) AS n
  FROM staging.stg_population
  GROUP BY 1, 2
  HAVING COUNT(*) > 1
""").df()
```

Simulated duplicate orders for practice:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_orders AS
SELECT * FROM (VALUES
  ('ORD-001', 'C-100', DATE '2024-01-15', 100.0, 'shipped'),
  ('ORD-001', 'C-100', DATE '2024-01-16', 100.0, 'updated'),
  ('ORD-002', 'C-101', DATE '2024-01-20', 50.0, 'pending')
) AS t(order_id, customer_id, order_date, amount, order_status);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT order_id, customer_id, order_date, amount, order_status
FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY order_id ORDER BY order_date DESC
  ) AS rn
  FROM raw.raw_orders
) WHERE rn = 1;
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_orders` | Table with duplicates |
| `{stg_table}` | `staging.stg_orders` | Deduplicated output |
| Partition key | `order_id` or `(country_name, year)` | Expected unique grain |
| `ORDER BY` | `order_date DESC` | Tie-breaker for keep-latest |
| `rn` filter | `WHERE rn = 1` | Keep one row per partition |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Example: `raw.raw_orders` — duplicate keys allowed.

| order_id | customer_id | order_date | amount | order_status |
|----------|-------------|------------|--------|--------------|
| ORD-001 | C-100 | 2024-01-15 | 100.0 | shipped |
| ORD-001 | C-100 | 2024-01-16 | 100.0 | updated |
| ORD-002 | C-101 | 2024-01-20 | 50.0 | pending |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_orders` — one row per `order_id`.

| order_id | customer_id | order_date | amount | order_status |
|----------|-------------|------------|--------|--------------|
| ORD-001 | C-100 | 2024-01-16 | 100.0 | updated |
| ORD-002 | C-101 | 2024-01-20 | 50.0 | pending |

## Validation Checks

```sql
-- Zero duplicates at declared grain
SELECT order_id, COUNT(*) AS n
FROM staging.stg_orders
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Row count reconciliation
SELECT
  (SELECT COUNT(*) FROM raw.raw_orders) AS raw_rows,
  (SELECT COUNT(DISTINCT order_id) FROM raw.raw_orders) AS distinct_keys,
  (SELECT COUNT(*) FROM staging.stg_orders) AS stg_rows;
```

```sql
-- stg_rows should equal distinct_keys when deduping on order_id
SELECT
  (SELECT COUNT(DISTINCT order_id) FROM raw.raw_orders) =
  (SELECT COUNT(*) FROM staging.stg_orders) AS counts_match;
```

## Common Variations

### Keep earliest instead of latest

```sql
ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_date ASC) AS rn
```

### Aggregate duplicates (sum amounts)

```sql
SELECT
  order_id,
  MAX(order_date) AS order_date,
  SUM(amount) AS amount
FROM raw.raw_orders
GROUP BY order_id;
```

### Deduplicate after text normalization

```sql
PARTITION BY LOWER(TRIM(email))
```

### Archive duplicates instead of dropping

```sql
CREATE OR REPLACE TABLE staging.stg_orders_dupes AS
SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_date DESC) AS rn
  FROM raw.raw_orders
) WHERE rn > 1;
```

### Spatial tables — dedupe on feature ID

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT parcel_id, owner_name, geom
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY ingest_ts DESC) AS rn
  FROM raw.raw_parcels_shp
) WHERE rn = 1;
```

## Known Limitations

- `ROW_NUMBER()` choice depends on `ORDER BY` — document the keep rule in the notebook.
- `DISTINCT` removes full-row duplicates only; same key with different attributes needs `ROW_NUMBER()` or `GROUP BY`.
- Deduplicating before [text cleaning](text_cleaning.md) may leave case-variant duplicates in `staging`.
- Null partition keys collapse into one group — filter null keys before dedupe.

## Related Pages

- [Duplicate check](../04_eda/duplicate_check.md)
- [Text cleaning](text_cleaning.md)
- [Column standardization](column_standardization.md)

Official reference: [Window functions](https://duckdb.org/docs/current/sql/window_functions.html)
