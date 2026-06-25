-- =============================================================================
-- ingest_parquet.sql
-- Purpose: Load a single Parquet file into a raw schema table.
-- Workflow: source → raw
-- Prerequisites: load_common_extensions.sql (httpfs for remote URLs)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM read_parquet('{{input_path}}');

-- -----------------------------------------------------------------------------
-- Example: DuckDB sample lineitem Parquet into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_lineitem_parquet AS
-- SELECT *
-- FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
