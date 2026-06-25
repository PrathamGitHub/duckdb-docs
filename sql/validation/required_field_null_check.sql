-- =============================================================================
-- required_field_null_check.sql
-- Purpose: Return rows where required columns are NULL. Zero rows = pass.
-- Workflow: validation before curated or output publish
-- =============================================================================

SELECT *
FROM {{table_name}}
WHERE {{required_column_1}} IS NULL
   OR {{required_column_2}} IS NULL
   -- OR {{required_column_3}} IS NULL
LIMIT {{row_limit}};

-- Summary variant (counts only):
-- SELECT
--   COUNT(*) FILTER (WHERE {{required_column_1}} IS NULL) AS null_{{required_column_1}},
--   COUNT(*) FILTER (WHERE {{required_column_2}} IS NULL) AS null_{{required_column_2}}
-- FROM {{table_name}};

-- -----------------------------------------------------------------------------
-- Example: required fields on staging orders
-- -----------------------------------------------------------------------------
-- SELECT *
-- FROM staging.stg_orders
-- WHERE order_id IS NULL
--    OR customer_id IS NULL
--    OR order_date IS NULL
-- LIMIT 100;
