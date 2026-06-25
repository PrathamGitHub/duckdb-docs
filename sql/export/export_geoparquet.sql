-- =============================================================================
-- export_geoparquet.sql
-- Purpose: Export spatial tables to GeoParquet for GIS and lakehouse consumers.
-- Workflow: curated → output (spatial delivery)
-- Prerequisites: load_spatial_extensions.sql
-- =============================================================================

COPY (
  SELECT
    {{attribute_columns}},
    {{geometry_column}}
  FROM {{table_name}}
) TO '{{output_path}}'
(FORMAT GDAL, DRIVER 'Parquet');

-- Alternative: ST_AsWKB when writing via COPY to Parquet without GDAL driver
-- COPY (
--   SELECT *, ST_AsWKB({{geometry_column}}) AS geom_wkb
--   FROM {{table_name}}
-- ) TO '{{output_path}}' (FORMAT PARQUET);

-- -----------------------------------------------------------------------------
-- Example: export California regions to GeoParquet
-- -----------------------------------------------------------------------------
-- COPY (
--   SELECT
--     name,
--     geom
--   FROM curated.cur_ca_regions
-- ) TO 'data/output/cur_ca_regions.parquet'
-- (FORMAT GDAL, DRIVER 'Parquet');
