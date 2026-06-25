-- =============================================================================
-- export_parquet.sql
-- Purpose: Export a table to a single Parquet file for downstream analytics.
-- Workflow: curated → output
-- =============================================================================

COPY (
  SELECT *
  FROM {{table_name}}
) TO '{{output_path}}'
(FORMAT PARQUET);

-- -----------------------------------------------------------------------------
-- Example: export curated population summary to output
-- -----------------------------------------------------------------------------
-- COPY (
--   SELECT *
--   FROM curated.cur_population_by_country
-- ) TO 'data/output/cur_population_by_country.parquet'
-- (FORMAT PARQUET);
