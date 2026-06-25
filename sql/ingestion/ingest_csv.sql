-- =============================================================================
-- ingest_csv.sql
-- Purpose: Load a CSV file from local disk or HTTP into a raw schema table.
-- Workflow: source → raw
-- Prerequisites: load_common_extensions.sql (httpfs for remote URLs)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM read_csv_auto(
  '{{input_path}}',
  header = true,
  sample_size = -1
);

-- -----------------------------------------------------------------------------
-- Example: population dataset from GitHub into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_population_csv AS
-- SELECT *
-- FROM read_csv_auto(
--   'https://raw.githubusercontent.com/datasets/population/master/data/population.csv',
--   header = true,
--   sample_size = -1
-- );
