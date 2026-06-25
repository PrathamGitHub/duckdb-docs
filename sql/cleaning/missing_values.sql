-- =============================================================================
-- missing_values.sql
-- Purpose: Impute or flag NULL values with explicit staging rules.
-- Workflow: staging (before curated builds)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  {{key_column}},
  COALESCE({{nullable_column}}, {{default_value}}) AS {{nullable_column}}_filled,
  {{nullable_column}} IS NULL AS {{nullable_column}}_was_null
FROM {{source_table}};

-- -----------------------------------------------------------------------------
-- Example: fill missing population with zero and flag imputed rows
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS staging;
--
-- CREATE OR REPLACE TABLE staging.stg_population_imputed AS
-- SELECT
--   country_name,
--   year,
--   COALESCE(population, 0) AS population_filled,
--   population IS NULL AS population_was_null
-- FROM staging.stg_population;
