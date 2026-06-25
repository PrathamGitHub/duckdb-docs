-- =============================================================================
-- row_count_reconciliation.sql
-- Purpose: Compare row counts across pipeline layers (source vs raw vs staging).
-- Workflow: validation (zero unexpected deltas before curated publish)
-- =============================================================================

WITH counts AS (
  SELECT '{{layer_1_name}}' AS layer_name, COUNT(*) AS row_count FROM {{layer_1_table}}
  UNION ALL
  SELECT '{{layer_2_name}}', COUNT(*) FROM {{layer_2_table}}
  UNION ALL
  SELECT '{{layer_3_name}}', COUNT(*) FROM {{layer_3_table}}
)
SELECT
  layer_name,
  row_count,
  row_count - FIRST_VALUE(row_count) OVER (ORDER BY layer_name) AS delta_from_first
FROM counts
ORDER BY layer_name;

-- -----------------------------------------------------------------------------
-- Example: reconcile population counts raw vs staging
-- -----------------------------------------------------------------------------
-- WITH counts AS (
--   SELECT 'raw'     AS layer_name, COUNT(*) AS row_count FROM raw.raw_population_csv
--   UNION ALL
--   SELECT 'staging', COUNT(*) FROM staging.stg_population
-- )
-- SELECT
--   layer_name,
--   row_count,
--   row_count - FIRST_VALUE(row_count) OVER (ORDER BY layer_name) AS delta_from_first
-- FROM counts
-- ORDER BY layer_name;
