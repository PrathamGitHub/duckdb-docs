-- =============================================================================
-- cte_pipeline.sql
-- Purpose: Chain reusable CTE steps from raw through staging logic.
-- Workflow: raw → staging → curated (multi-step SQL pipeline)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE {{table_name}} AS
WITH source AS (
  SELECT * FROM {{source_table}}
),
cleaned AS (
  SELECT
    {{key_column}},
    TRIM({{text_column}}) AS {{text_column}},
    TRY_CAST({{numeric_column}} AS DOUBLE) AS {{numeric_column}}
  FROM source
  WHERE {{key_column}} IS NOT NULL
),
enriched AS (
  SELECT
    *,
    CASE
      WHEN {{numeric_column}} >= {{threshold_value}} THEN 'high'
      ELSE 'low'
    END AS {{category_column}}
  FROM cleaned
)
SELECT *
FROM enriched;

-- -----------------------------------------------------------------------------
-- Example: population staging pipeline with year filter
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS staging;
--
-- CREATE OR REPLACE TABLE staging.stg_population_recent AS
-- WITH source AS (
--   SELECT * FROM raw.raw_population_csv
-- ),
-- cleaned AS (
--   SELECT
--     TRIM("Country Name") AS country_name,
--     TRY_CAST("Year" AS INTEGER) AS year,
--     TRY_CAST("Value" AS BIGINT) AS population
--   FROM source
--   WHERE "Country Name" IS NOT NULL
-- ),
-- enriched AS (
--   SELECT
--     *,
--     CASE
--       WHEN population >= 100000000 THEN 'large'
--       ELSE 'small'
--     END AS country_size
--   FROM cleaned
--   WHERE year >= 2000
-- )
-- SELECT *
-- FROM enriched;
