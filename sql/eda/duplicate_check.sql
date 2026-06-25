-- =============================================================================
-- duplicate_check.sql
-- Purpose: Find duplicate values for one or more key columns.
-- Workflow: EDA before deduplication in staging
-- =============================================================================

SELECT
  {{key_columns}},
  COUNT(*) AS duplicate_count
FROM {{table_name}}
GROUP BY {{key_columns}}
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- -----------------------------------------------------------------------------
-- Example: duplicate order_id values in staging
-- -----------------------------------------------------------------------------
-- SELECT
--   order_id,
--   COUNT(*) AS duplicate_count
-- FROM staging.stg_orders
-- GROUP BY order_id
-- HAVING COUNT(*) > 1
-- ORDER BY duplicate_count DESC;
