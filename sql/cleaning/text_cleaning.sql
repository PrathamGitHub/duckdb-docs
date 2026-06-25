-- =============================================================================
-- text_cleaning.sql
-- Purpose: Trim, normalize case, and standardize text fields in staging.
-- Workflow: raw → staging (text normalization)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  {{key_column}},
  TRIM({{text_column}}) AS {{text_column}}_trimmed,
  UPPER(TRIM({{text_column}})) AS {{text_column}}_normalized,
  REGEXP_REPLACE(TRIM({{text_column}}), '\s+', ' ', 'g') AS {{text_column}}_collapsed
FROM {{source_table}};

-- -----------------------------------------------------------------------------
-- Example: normalize country names in staging
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS staging;
--
-- CREATE OR REPLACE TABLE staging.stg_population_clean AS
-- SELECT
--   ROW_NUMBER() OVER () AS row_id,
--   TRIM("Country Name") AS country_name,
--   UPPER(TRIM("Country Name")) AS country_name_normalized,
--   REGEXP_REPLACE(TRIM("Country Name"), '\s+', ' ', 'g') AS country_name_collapsed,
--   TRY_CAST("Year" AS INTEGER) AS year,
--   TRY_CAST("Value" AS BIGINT) AS population
-- FROM raw.raw_population_csv;
