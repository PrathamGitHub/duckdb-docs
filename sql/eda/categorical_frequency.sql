-- =============================================================================
-- categorical_frequency.sql
-- Purpose: Top category values with counts and share of total rows.
-- Workflow: EDA on staging or curated dimension attributes
-- =============================================================================

WITH base AS (
  SELECT {{category_column}} AS category_value
  FROM {{table_name}}
),
totals AS (
  SELECT COUNT(*) AS total_rows FROM base
)
SELECT
  category_value,
  COUNT(*) AS value_count,
  ROUND(100.0 * COUNT(*) / (SELECT total_rows FROM totals), 2) AS pct_of_rows
FROM base
GROUP BY category_value
ORDER BY value_count DESC
LIMIT {{top_n}};

-- -----------------------------------------------------------------------------
-- Example: top countries in population raw table
-- -----------------------------------------------------------------------------
-- WITH base AS (
--   SELECT "Country Name" AS category_value
--   FROM raw.raw_population_csv
-- ),
-- totals AS (
--   SELECT COUNT(*) AS total_rows FROM base
-- )
-- SELECT
--   category_value,
--   COUNT(*) AS value_count,
--   ROUND(100.0 * COUNT(*) / (SELECT total_rows FROM totals), 2) AS pct_of_rows
-- FROM base
-- GROUP BY category_value
-- ORDER BY value_count DESC
-- LIMIT 20;
