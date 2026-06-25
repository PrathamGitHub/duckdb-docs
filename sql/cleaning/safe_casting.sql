-- =============================================================================
-- safe_casting.sql
-- Purpose: Cast messy text columns to typed values with TRY_CAST fallbacks.
-- Workflow: raw → staging (type normalization)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  {{key_column}},
  TRY_CAST({{text_column}} AS {{target_type}}) AS {{output_column}},
  -- Preserve original when cast fails (optional audit column)
  {{text_column}} AS {{text_column}}_raw
FROM {{source_table}}
WHERE {{key_column}} IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Example: cast population values from text to BIGINT
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS staging;
--
-- CREATE OR REPLACE TABLE staging.stg_population AS
-- SELECT
--   "Country Name" AS country_name,
--   TRY_CAST("Year" AS INTEGER) AS year,
--   TRY_CAST("Value" AS BIGINT) AS population,
--   "Value" AS value_raw
-- FROM raw.raw_population_csv
-- WHERE "Country Name" IS NOT NULL;
