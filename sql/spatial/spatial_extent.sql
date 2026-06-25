-- =============================================================================
-- spatial_extent.sql
-- Purpose: Compute bounding box and spatial extent for a geometry column.
-- Workflow: spatial EDA on raw, staging, or curated layers
-- Prerequisites: load_spatial_extensions.sql
-- =============================================================================

SELECT
  COUNT(*) AS feature_count,
  ST_XMin(ST_Extent({{geometry_column}})) AS min_x,
  ST_YMin(ST_Extent({{geometry_column}})) AS min_y,
  ST_XMax(ST_Extent({{geometry_column}})) AS max_x,
  ST_YMax(ST_Extent({{geometry_column}})) AS max_y,
  ST_AsText(ST_Extent({{geometry_column}})) AS extent_wkt
FROM {{table_name}}
WHERE {{geometry_column}} IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Example: extent of California regions in raw
-- -----------------------------------------------------------------------------
-- SELECT
--   COUNT(*) AS feature_count,
--   ST_XMin(ST_Extent(geom)) AS min_x,
--   ST_YMin(ST_Extent(geom)) AS min_y,
--   ST_XMax(ST_Extent(geom)) AS max_x,
--   ST_YMax(ST_Extent(geom)) AS max_y,
--   ST_AsText(ST_Extent(geom)) AS extent_wkt
-- FROM raw.raw_ca_regions_geojson
-- WHERE geom IS NOT NULL;
