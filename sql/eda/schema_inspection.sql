-- =============================================================================
-- schema_inspection.sql
-- Purpose: List column names, types, and nullability for a table.
-- Workflow: EDA on raw, staging, or curated layers
-- =============================================================================

DESCRIBE {{table_name}};

-- Alternative: information_schema detail
-- SELECT
--   column_name,
--   data_type,
--   is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = '{{schema_name}}'
--   AND table_name = '{{base_table_name}}'
-- ORDER BY ordinal_position;

-- -----------------------------------------------------------------------------
-- Example: inspect raw population table
-- -----------------------------------------------------------------------------
-- DESCRIBE raw.raw_population_csv;
