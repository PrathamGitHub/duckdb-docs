-- =============================================================================
-- date_range_check.sql
-- Purpose: Find earliest, latest, and out-of-range dates for a date column.
-- Workflow: EDA on staging before curated builds
-- =============================================================================

SELECT
  COUNT({{date_column}}) AS non_null_count,
  MIN({{date_column}}) AS min_date,
  MAX({{date_column}}) AS max_date,
  COUNT(*) FILTER (
    WHERE {{date_column}} < DATE '{{min_expected_date}}'
       OR {{date_column}} > DATE '{{max_expected_date}}'
  ) AS out_of_range_count
FROM {{table_name}};

-- Optional: list out-of-range rows
-- SELECT *
-- FROM {{table_name}}
-- WHERE {{date_column}} < DATE '{{min_expected_date}}'
--    OR {{date_column}} > DATE '{{max_expected_date}}'
-- LIMIT 100;

-- -----------------------------------------------------------------------------
-- Example: order_date range in staging
-- -----------------------------------------------------------------------------
-- SELECT
--   COUNT(order_date) AS non_null_count,
--   MIN(order_date) AS min_date,
--   MAX(order_date) AS max_date,
--   COUNT(*) FILTER (
--     WHERE order_date < DATE '2010-01-01'
--        OR order_date > DATE '2030-12-31'
--   ) AS out_of_range_count
-- FROM staging.stg_orders;
