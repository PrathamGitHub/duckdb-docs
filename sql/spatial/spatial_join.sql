-- =============================================================================
-- spatial_join.sql
-- Purpose: Join point/line/polygon layers using spatial predicates.
-- Workflow: staging → curated (spatial enrichment)
-- Prerequisites: load_spatial_extensions.sql
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  a.{{left_key_column}},
  b.{{right_key_column}},
  a.{{left_attribute_column}},
  b.{{right_attribute_column}}
FROM {{left_table}} AS a
INNER JOIN {{right_table}} AS b
  ON ST_Intersects(a.{{left_geometry_column}}, b.{{right_geometry_column}});

-- Other predicates: ST_Contains, ST_Within, ST_DWithin (with distance)
-- ON ST_Contains(b.{{right_geometry_column}}, a.{{left_geometry_column}})

-- -----------------------------------------------------------------------------
-- Example: points within polygon regions
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.cur_sites_in_regions AS
-- SELECT
--   s.site_id,
--   r.region_name,
--   s.site_name,
--   r.geom AS region_geom
-- FROM staging.stg_sites AS s
-- INNER JOIN staging.stg_regions AS r
--   ON ST_Within(s.geom, r.geom);
