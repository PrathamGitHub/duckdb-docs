-- =============================================================================
-- window_function_template.sql
-- Purpose: Rank, lag, and running totals with window functions.
-- Workflow: staging → curated (analytical features)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  {{partition_column}},
  {{order_column}},
  {{measure_column}},
  ROW_NUMBER() OVER (
    PARTITION BY {{partition_column}}
    ORDER BY {{order_column}} DESC
  ) AS row_num,
  LAG({{measure_column}}) OVER (
    PARTITION BY {{partition_column}}
    ORDER BY {{order_column}}
  ) AS prev_{{measure_column}},
  SUM({{measure_column}}) OVER (
    PARTITION BY {{partition_column}}
    ORDER BY {{order_column}}
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS running_total_{{measure_column}}
FROM {{source_table}};

-- -----------------------------------------------------------------------------
-- Example: year-over-year population by country
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.cur_population_yoy AS
-- SELECT
--   country_name,
--   year,
--   population,
--   LAG(population) OVER (
--     PARTITION BY country_name
--     ORDER BY year
--   ) AS prev_population,
--   population - LAG(population) OVER (
--     PARTITION BY country_name
--     ORDER BY year
--   ) AS population_change
-- FROM staging.stg_population
-- WHERE population IS NOT NULL;
