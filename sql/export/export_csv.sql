-- =============================================================================
-- export_csv.sql
-- Purpose: Export a curated or output table to CSV for delivery or Excel import.
-- Workflow: curated → output
-- =============================================================================

COPY (
  SELECT *
  FROM {{table_name}}
) TO '{{output_path}}'
(FORMAT CSV, HEADER true, DELIMITER ',');

-- -----------------------------------------------------------------------------
-- Example: export curated orders to output folder
-- -----------------------------------------------------------------------------
-- COPY (
--   SELECT *
--   FROM curated.fct_orders
-- ) TO 'data/output/fct_orders.csv'
-- (FORMAT CSV, HEADER true, DELIMITER ',');
