-- =============================================================================
-- load_spatial_extensions.sql
-- Purpose: Install and load the spatial extension for Shapefile, GeoJSON,
--          GeoParquet, File Geodatabase, and ST_* geometry functions.
-- Workflow: setup (before spatial source → raw ingest)
-- =============================================================================

INSTALL spatial;
LOAD spatial;

-- Optional: confirm GDAL drivers available in your environment
-- SELECT short_name, long_name, can_open
-- FROM ST_Drivers()
-- WHERE short_name IN ('ESRI Shapefile', 'GeoJSON', 'Parquet', 'OpenFileGDB')
-- ORDER BY short_name;

-- -----------------------------------------------------------------------------
-- Example: load spatial and preview a remote GeoJSON layer
-- -----------------------------------------------------------------------------
-- INSTALL spatial; LOAD spatial;
--
-- SELECT *
-- FROM ST_Read(
--   'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
-- )
-- LIMIT 10;
