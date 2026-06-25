-- =============================================================================
-- primary_key_uniqueness.sql
-- Purpose: Detect duplicate primary key values. Zero rows = pass.
-- Workflow: validation on staging or curated tables
-- =============================================================================

SELECT
  {{key_column}},
  COUNT(*) AS duplicate_count
FROM {{table_name}}
GROUP BY {{key_column}}
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- Composite key variant:
-- SELECT {{key_column_1}}, {{key_column_2}}, COUNT(*) AS duplicate_count
-- FROM {{table_name}}
-- GROUP BY {{key_column_1}}, {{key_column_2}}
-- HAVING COUNT(*) > 1;

-- -----------------------------------------------------------------------------
-- Example: validate unique order_id in staging
-- -----------------------------------------------------------------------------
-- SELECT
--   order_id,
--   COUNT(*) AS duplicate_count
-- FROM staging.stg_orders
-- GROUP BY order_id
-- HAVING COUNT(*) > 1
-- ORDER BY duplicate_count DESC;
