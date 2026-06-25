-- =============================================================================
-- row_count.sql
-- Purpose: Return total row count for reconciliation and sanity checks.
-- Workflow: EDA on raw, staging, or curated layers
-- =============================================================================

SELECT COUNT(*) AS row_count
FROM {{table_name}};

-- -----------------------------------------------------------------------------
-- Example: count rows in curated fact table
-- -----------------------------------------------------------------------------
-- SELECT COUNT(*) AS row_count
-- FROM curated.fct_orders;
