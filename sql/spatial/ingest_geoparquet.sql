-- =============================================================================
-- ingest_geoparquet.sql
-- Purpose: Load GeoParquet into a raw spatial table.
-- Workflow: source → raw (spatial)
-- Prerequisites: load_spatial_extensions.sql, httpfs for remote paths
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM ST_Read('{{input_path}}');

-- Alternative: read_parquet when geometry is a known WKB column
-- CREATE OR REPLACE TABLE {{table_name}} AS
-- SELECT *
-- FROM read_parquet('{{input_path}}');

-- -----------------------------------------------------------------------------
-- Example: local boundaries GeoParquet into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_boundaries_geoparquet AS
-- SELECT *
-- FROM ST_Read('data/source/boundaries.parquet');
