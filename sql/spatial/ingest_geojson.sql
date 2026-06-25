-- =============================================================================
-- ingest_geojson.sql
-- Purpose: Load GeoJSON from local path or URL into a raw spatial table.
-- Workflow: source → raw (spatial)
-- Prerequisites: load_spatial_extensions.sql, httpfs for remote URLs
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM ST_Read('{{input_path}}');

-- -----------------------------------------------------------------------------
-- Example: California GeoJSON from GitHub into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_ca_regions_geojson AS
-- SELECT *
-- FROM ST_Read(
--   'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
-- );
