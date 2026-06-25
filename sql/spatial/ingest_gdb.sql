-- =============================================================================
-- ingest_gdb.sql
-- Purpose: Load a layer from an ESRI File Geodatabase (.gdb folder) into raw.
-- Workflow: source → raw (spatial)
-- Prerequisites: load_spatial_extensions.sql; OpenFileGDB GDAL driver
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM ST_Read(
  '{{input_path}}',
  layer := '{{layer_name}}'
);

-- Inspect layers before ingest:
-- SELECT * FROM ST_Read_Meta('{{input_path}}');

-- -----------------------------------------------------------------------------
-- Example: zoning layer from File Geodatabase into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_zoning_gdb AS
-- SELECT *
-- FROM ST_Read(
--   'data/source/city_zoning.gdb',
--   layer := 'Zoning'
-- );
