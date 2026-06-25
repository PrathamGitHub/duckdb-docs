-- =============================================================================
-- buffer_analysis.sql
-- Purpose: Create buffer zones around geometries for proximity analysis.
-- Workflow: staging → curated (spatial transformation)
-- Prerequisites: load_spatial_extensions.sql
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  {{key_column}},
  {{geometry_column}},
  ST_Buffer({{geometry_column}}, {{buffer_distance}}) AS {{geometry_column}}_buffer
FROM {{source_table}}
WHERE {{geometry_column}} IS NOT NULL;

-- Note: buffer distance units match the geometry CRS (meters for projected, degrees for WGS84).

-- -----------------------------------------------------------------------------
-- Example: 500-unit buffer around road centerlines
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.cur_roads_buffer AS
-- SELECT
--   road_id,
--   geom,
--   ST_Buffer(geom, 500) AS geom_buffer
-- FROM staging.stg_roads
-- WHERE geom IS NOT NULL;
