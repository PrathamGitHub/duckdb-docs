-- =============================================================================
-- load_common_extensions.sql
-- Purpose: Install and load DuckDB extensions for tabular ingest, remote files,
--          and JSON workflows. Run at the start of notebook sessions.
-- Workflow: setup (before source → raw ingest)
-- =============================================================================

INSTALL httpfs;
LOAD httpfs;

INSTALL json;
LOAD json;

-- Optional: verify loaded extensions
-- SELECT extension_name, loaded, installed
-- FROM duckdb_extensions()
-- WHERE extension_name IN ('httpfs', 'json')
-- ORDER BY extension_name;

-- -----------------------------------------------------------------------------
-- Example: minimal tabular + remote ingest session
-- -----------------------------------------------------------------------------
-- INSTALL httpfs; LOAD httpfs;
-- INSTALL json;   LOAD json;
--
-- CREATE SCHEMA IF NOT EXISTS raw;
-- CREATE OR REPLACE TABLE raw.raw_population_csv AS
-- SELECT *
-- FROM read_csv_auto(
--   'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
-- );
