-- =============================================================================
-- preview_rows.sql
-- Purpose: Quickly inspect the first N rows of a table or view.
-- Workflow: EDA on raw, staging, or curated layers
-- =============================================================================

SELECT *
FROM {{table_name}}
LIMIT {{row_limit}};

-- -----------------------------------------------------------------------------
-- Example: preview staging orders
-- -----------------------------------------------------------------------------
-- SELECT *
-- FROM staging.stg_orders
-- LIMIT 20;
