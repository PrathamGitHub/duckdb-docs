-- =============================================================================
-- aggregation_template.sql
-- Purpose: Group and aggregate metrics for reporting or curated summaries.
-- Workflow: staging → curated
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  {{group_by_columns}},
  COUNT(*) AS row_count,
  SUM({{measure_column}}) AS total_{{measure_column}},
  ROUND(AVG({{measure_column}}), 4) AS avg_{{measure_column}}
FROM {{source_table}}
GROUP BY {{group_by_columns}}
ORDER BY total_{{measure_column}} DESC;

-- -----------------------------------------------------------------------------
-- Example: population totals by country (latest year per country)
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.cur_population_by_country AS
-- SELECT
--   country_name,
--   MAX(year) AS latest_year,
--   SUM(population) AS total_population,
--   ROUND(AVG(population), 0) AS avg_population
-- FROM staging.stg_population
-- GROUP BY country_name
-- ORDER BY total_population DESC;
