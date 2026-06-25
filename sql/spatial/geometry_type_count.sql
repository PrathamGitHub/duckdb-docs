-- =============================================================================
-- geometry_type_count.sql
-- Purpose: Count features by geometry type (POINT, POLYGON, etc.).
-- Workflow: spatial EDA on raw, staging, or curated layers
-- Prerequisites: load_spatial_extensions.sql
-- =============================================================================

SELECT
  ST_GeometryType({{geometry_column}}) AS geometry_type,
  COUNT(*) AS feature_count
FROM {{table_name}}
WHERE {{geometry_column}} IS NOT NULL
GROUP BY ST_GeometryType({{geometry_column}})
ORDER BY feature_count DESC;

-- -----------------------------------------------------------------------------
-- Example: geometry types in raw California GeoJSON
-- -----------------------------------------------------------------------------
-- SELECT
--   ST_GeometryType(geom) AS geometry_type,
--   COUNT(*) AS feature_count
-- FROM raw.raw_ca_regions_geojson
-- WHERE geom IS NOT NULL
-- GROUP BY ST_GeometryType(geom)
-- ORDER BY feature_count DESC;
