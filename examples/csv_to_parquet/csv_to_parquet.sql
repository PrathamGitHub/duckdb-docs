-- csv_to_parquet.sql
-- Workflow: source → raw → staging → output
-- Run from repository root:
--   duckdb work.duckdb < examples/csv_to_parquet/csv_to_parquet.sql

-- =============================================================================
-- Setup
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;

-- Paths are relative to the repository root (current working directory).
-- Input:  data/raw/orders.csv
-- Output: data/output/orders.parquet

-- =============================================================================
-- Ingestion — land CSV in raw.raw_orders
-- =============================================================================

CREATE OR REPLACE TABLE raw.raw_orders AS
SELECT *
FROM read_csv_auto(
  'data/raw/orders.csv',
  header = true,
  sample_size = -1
);

-- =============================================================================
-- Basic EDA — inspect raw before transforming
-- =============================================================================

-- Preview
SELECT *
FROM raw.raw_orders
LIMIT 10;

-- Schema
DESCRIBE raw.raw_orders;

-- Row count
SELECT COUNT(*) AS raw_row_count
FROM raw.raw_orders;

-- Null profile on key columns (adjust if your CSV differs)
SELECT
  COUNT(*) AS total_rows,
  COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
  COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
  COUNT(*) FILTER (WHERE order_date IS NULL) AS null_order_date,
  COUNT(*) FILTER (WHERE amount IS NULL) AS null_amount
FROM raw.raw_orders;

-- Numeric summary
SELECT
  MIN(TRY_CAST(amount AS DOUBLE)) AS min_amount,
  MAX(TRY_CAST(amount AS DOUBLE)) AS max_amount,
  AVG(TRY_CAST(amount AS DOUBLE)) AS avg_amount,
  SUM(TRY_CAST(amount AS DOUBLE)) AS sum_amount
FROM raw.raw_orders;

-- Category distribution
SELECT
  COALESCE(TRIM(order_status), '(null)') AS order_status,
  COUNT(*) AS row_count
FROM raw.raw_orders
GROUP BY 1
ORDER BY row_count DESC;

-- =============================================================================
-- Staging transformation — clean, cast, standardize
-- =============================================================================

CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  TRY_CAST(order_id AS BIGINT) AS order_id,
  TRY_CAST(customer_id AS BIGINT) AS customer_id,
  TRY_CAST(order_date AS DATE) AS order_date,
  TRY_CAST(amount AS DOUBLE) AS amount,
  TRY_CAST(quantity AS INTEGER) AS quantity,
  LOWER(TRIM(COALESCE(order_status, 'unknown'))) AS order_status
FROM raw.raw_orders
WHERE order_id IS NOT NULL
  AND TRIM(CAST(order_id AS VARCHAR)) != '';

-- =============================================================================
-- Validation — block export when checks fail
-- =============================================================================

-- Staging must not be empty
SELECT
  CASE
    WHEN COUNT(*) > 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS staging_not_empty
FROM staging.stg_orders;

-- Required-field null check (0 failing rows = pass)
SELECT
  COUNT(*) AS rows_with_required_nulls
FROM staging.stg_orders
WHERE order_id IS NULL
   OR customer_id IS NULL
   OR order_date IS NULL
   OR amount IS NULL;

-- Primary key uniqueness (0 duplicate groups = pass)
SELECT
  order_id,
  COUNT(*) AS duplicate_count
FROM staging.stg_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- Row count reconciliation (staging should be <= raw)
SELECT
  (SELECT COUNT(*) FROM raw.raw_orders) AS raw_n,
  (SELECT COUNT(*) FROM staging.stg_orders) AS stg_n,
  (SELECT COUNT(*) FROM raw.raw_orders)
    - (SELECT COUNT(*) FROM staging.stg_orders) AS dropped_rows;

-- Value range: amounts should be positive in staging
SELECT
  COUNT(*) AS non_positive_amount_rows
FROM staging.stg_orders
WHERE amount IS NULL OR amount <= 0;

-- =============================================================================
-- Export — write validated staging table to Parquet
-- =============================================================================

COPY staging.stg_orders
TO 'data/output/orders.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

-- Post-export verification
SELECT
  (SELECT COUNT(*) FROM staging.stg_orders) AS staging_n,
  (SELECT COUNT(*) FROM read_parquet('data/output/orders.parquet')) AS parquet_n;
