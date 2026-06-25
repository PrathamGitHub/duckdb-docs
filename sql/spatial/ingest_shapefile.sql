-- =============================================================================
-- ingest_shapefile.sql
-- Purpose: Load an ESRI Shapefile into a raw spatial table.
-- Workflow: source → raw (spatial)
-- Prerequisites: load_spatial_extensions.sql
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM ST_Read('{{input_path}}');

-- Optional: bbox filter at read time (when supported by driver)
-- CREATE OR REPLACE TABLE {{table_name}} AS
-- SELECT *
-- FROM ST_Read(
--   '{{input_path}}',
--   spatial_filter_box := ST_MakeEnvelope({{min_x}}, {{min_y}}, {{max_x}}, {{max_y}})
-- );

-- -----------------------------------------------------------------------------
-- Example: Natural Earth admin boundaries shapefile into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_countries_shp AS
-- SELECT *
-- FROM ST_Read('data/source/ne_110m_admin_0_countries.shp');
