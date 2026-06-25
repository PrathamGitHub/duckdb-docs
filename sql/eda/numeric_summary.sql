-- =============================================================================
-- numeric_summary.sql
-- Purpose: Summarize numeric columns with min, max, average, and stddev.
-- Workflow: EDA on staging or curated tables
-- =============================================================================

SELECT
  COUNT({{numeric_column}}) AS non_null_count,
  MIN({{numeric_column}}) AS min_value,
  MAX({{numeric_column}}) AS max_value,
  ROUND(AVG({{numeric_column}}), 4) AS avg_value,
  ROUND(STDDEV({{numeric_column}}), 4) AS stddev_value
FROM {{table_name}};

-- -----------------------------------------------------------------------------
-- Example: summarize order amounts in staging
-- -----------------------------------------------------------------------------
-- SELECT
--   COUNT(amount) AS non_null_count,
--   MIN(amount) AS min_value,
--   MAX(amount) AS max_value,
--   ROUND(AVG(amount), 4) AS avg_value,
--   ROUND(STDDEV(amount), 4) AS stddev_value
-- FROM staging.stg_orders;
