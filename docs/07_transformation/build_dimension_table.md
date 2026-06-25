# Build Dimension Table

Create conformed `curated.dim_*` tables from `staging.stg_*` with stable keys and one row per entity.

## Purpose

Publish reusable customer (or product, region, location) attributes that fact tables and marts join to — enforcing uniqueness on natural keys and standard column names.

## When to Use

- Promoting cleaned `staging.stg_customers` to `curated.dim_customers`
- After [deduplication](../06_cleaning/deduplication.md) when staging still has history or snapshot duplicates
- Before [build fact table](build_fact_table.md) so facts reference conformed dimensions
- Adding surrogate keys (`customer_sk`) for slowly changing attribute patterns

## SQL Template

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE curated.dim_customers AS
WITH deduped AS (
  SELECT
    customer_id,
    customer_name,
    customer_segment,
    region,
    email,
    is_active,
    updated_at
  FROM staging.stg_customers
  WHERE customer_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY updated_at DESC NULLS LAST
  ) = 1
),
conformed AS (
  SELECT
    customer_id,
    TRIM(customer_name) AS customer_name,
    LOWER(TRIM(customer_segment)) AS customer_segment,
    UPPER(TRIM(region)) AS region,
    LOWER(TRIM(email)) AS email,
    COALESCE(is_active, FALSE) AS is_active,
    updated_at,
    MD5(customer_id::VARCHAR) AS customer_sk
  FROM deduped
)
SELECT
  customer_sk,
  customer_id,
  customer_name,
  customer_segment,
  region,
  email,
  is_active,
  updated_at,
  CURRENT_TIMESTAMP AS dim_loaded_at
FROM conformed;
```

Minimal dimension (no surrogate key):

```sql
CREATE OR REPLACE TABLE curated.dim_customers AS
SELECT DISTINCT
  customer_id,
  customer_name,
  customer_segment,
  region,
  is_active
FROM staging.stg_customers
WHERE customer_id IS NOT NULL;
```

Unknown / default member row for orphan facts:

```sql
INSERT INTO curated.dim_customers BY NAME
SELECT
  MD5('UNKNOWN') AS customer_sk,
  'UNKNOWN' AS customer_id,
  'Unknown Customer' AS customer_name,
  'unknown' AS customer_segment,
  'UNK' AS region,
  NULL AS email,
  FALSE AS is_active,
  NULL AS updated_at,
  CURRENT_TIMESTAMP AS dim_loaded_at;
```

## Notebook Usage

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM (VALUES
  ('C-100', 'Acme Corp', 'enterprise', 'west', 'sales@acme.com', TRUE, TIMESTAMP '2024-03-01'),
  ('C-100', 'Acme Corporation', 'enterprise', 'west', 'sales@acme.com', TRUE, TIMESTAMP '2024-06-01'),
  ('C-101', 'Beta LLC', 'smb', 'east', 'ops@beta.com', TRUE, TIMESTAMP '2024-01-15'),
  (NULL, 'Ghost', 'smb', 'east', NULL, FALSE, TIMESTAMP '2024-01-01')
) AS t(customer_id, customer_name, customer_segment, region, email, is_active, updated_at);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.dim_customers AS
WITH deduped AS (
  SELECT * FROM staging.stg_customers
  WHERE customer_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id ORDER BY updated_at DESC
  ) = 1
)
SELECT
  MD5(customer_id::VARCHAR) AS customer_sk,
  customer_id,
  TRIM(customer_name) AS customer_name,
  customer_segment,
  region,
  email,
  is_active,
  updated_at,
  CURRENT_TIMESTAMP AS dim_loaded_at
FROM deduped;
""")

con.sql("SELECT * FROM curated.dim_customers ORDER BY customer_id").df()
```

Practice with online reference data — country dimension:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_country_codes AS
SELECT * FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/country-codes/master/data/country-codes.csv'
);
""")

con.execute("""
CREATE OR REPLACE TABLE curated.dim_countries AS
SELECT DISTINCT
  "ISO3166-1-Alpha-3" AS country_code,
  TRIM("CLDR display name") AS country_name,
  "ISO4217-currency_alphabetic_code" AS currency_code
FROM raw.raw_country_codes
WHERE "ISO3166-1-Alpha-3" IS NOT NULL
  AND TRIM("CLDR display name") IS NOT NULL;
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{stg_table}` | `staging.stg_customers` | Cleaned staging input |
| `{dim_table}` | `curated.dim_customers` | Output dimension |
| Natural key | `customer_id` | Business identifier |
| Surrogate key | `MD5(customer_id::VARCHAR)` | Optional stable hash SK |
| Dedup order | `updated_at DESC` | Keep-latest rule |
| Audit column | `dim_loaded_at` | Load timestamp |

## Input Table Pattern

```text
staging.stg_<entity>
```

Example: **`staging.stg_customers`** — may contain duplicate keys

| customer_id | customer_name | customer_segment | region | updated_at |
|-------------|---------------|------------------|--------|------------|
| C-100 | Acme Corp | enterprise | west | 2024-03-01 |
| C-100 | Acme Corporation | enterprise | west | 2024-06-01 |
| C-101 | Beta LLC | smb | east | 2024-01-15 |

## Output Table Pattern

```text
curated.dim_<entity>
```

Example: **`curated.dim_customers`** — one row per `customer_id`

| customer_sk | customer_id | customer_name | customer_segment | region | is_active | dim_loaded_at |
|-------------|-------------|---------------|------------------|--------|-----------|---------------|
| …hash… | C-100 | Acme Corporation | enterprise | west | true | 2024-06-15 … |
| …hash… | C-101 | Beta LLC | smb | east | true | 2024-06-15 … |

## Validation Checks

```sql
-- Primary key uniqueness on natural key
SELECT customer_id, COUNT(*) AS n
FROM curated.dim_customers
WHERE customer_id != 'UNKNOWN'
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Surrogate key uniqueness
SELECT customer_sk, COUNT(*) AS n
FROM curated.dim_customers
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Row count: dim <= distinct keys in staging
SELECT
  (SELECT COUNT(DISTINCT customer_id) FROM staging.stg_customers
   WHERE customer_id IS NOT NULL) AS stg_distinct,
  (SELECT COUNT(*) FROM curated.dim_customers
   WHERE customer_id != 'UNKNOWN') AS dim_rows;
```

```sql
-- Required attributes not null
SELECT COUNT(*) AS bad_rows
FROM curated.dim_customers
WHERE customer_name IS NULL OR region IS NULL;
```

## Common Variations

### Type 1 slowly changing — overwrite attributes

Full refresh with `CREATE OR REPLACE` (template above) — latest staging row wins.

### Surrogate key with sequence

```sql
ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_sk
```

Use integer SKs only when you control ID assignment across reloads.

### Role-playing dimension (date)

```sql
CREATE OR REPLACE TABLE curated.dim_calendar AS
SELECT
  calendar_date,
  DATE_TRUNC('month', calendar_date) AS month_start,
  EXTRACT('year' FROM calendar_date) AS year
FROM staging.stg_calendar;
```

### Spatial dimension

```sql
CREATE OR REPLACE TABLE curated.dim_parcels AS
SELECT
  parcel_id,
  owner_name,
  ST_MakeValid(geom) AS geom,
  ST_SRID(geom) AS srid
FROM staging.stg_parcels
QUALIFY ROW_NUMBER() OVER (PARTITION BY parcel_id ORDER BY ingest_ts DESC) = 1;
```

### Bridge table for many-to-many

```sql
CREATE OR REPLACE TABLE curated.dim_customer_segments AS
SELECT customer_id, segment_code
FROM staging.stg_customer_segment_bridge;
```

## Performance Notes

- Dedupe in one pass with `QUALIFY ROW_NUMBER()` before adding expensive derived columns.
- `CREATE OR REPLACE` full refresh is simple for small/medium dimensions — use [incremental load](incremental_load_pattern.md) when staging grows large.
- Index-like benefits in DuckDB come from sorting on join keys — cluster dimension exports by `customer_id` if rereading often.
- Hash surrogate keys (`MD5`) are fast; integer sequences require careful reload semantics.

## Known Limitations

- Type 1 overwrite loses history — track history in separate `staging` snapshots if audit is required.
- `MD5` surrogate keys are not sequential — fine for joins, awkward for human display.
- `DISTINCT` without `ROW_NUMBER` tie-breaker picks arbitrary row among duplicates.
- Unknown member rows must be loaded before facts reference them in strict star schemas.

## Related Pages

- [Build fact table](build_fact_table.md)
- [Joins](joins.md)
- [Deduplication](../06_cleaning/deduplication.md)
- [Incremental load pattern](incremental_load_pattern.md)

Official reference: [CREATE TABLE](https://duckdb.org/docs/current/sql/statements/create_table.html)
