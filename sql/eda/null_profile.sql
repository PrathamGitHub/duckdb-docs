-- =============================================================================
-- null_profile.sql
-- Purpose: Profile NULL counts and percentages for selected columns.
-- Workflow: EDA on staging or curated tables before validation
-- =============================================================================

WITH base AS (
  SELECT * FROM {{table_name}}
),
metrics AS (
  SELECT '{{column_1}}' AS column_name, COUNT(*) - COUNT({{column_1}}) AS null_count FROM base
  UNION ALL
  SELECT '{{column_2}}', COUNT(*) - COUNT({{column_2}}) FROM base
  -- Add UNION ALL blocks for additional columns
)
SELECT
  column_name,
  null_count,
  (SELECT COUNT(*) FROM base) AS total_rows,
  ROUND(100.0 * null_count / (SELECT COUNT(*) FROM base), 2) AS null_pct
FROM metrics
ORDER BY null_count DESC;

-- -----------------------------------------------------------------------------
-- Example: null profile on staging orders
-- -----------------------------------------------------------------------------
-- WITH base AS (
--   SELECT * FROM staging.stg_orders
-- ),
-- metrics AS (
--   SELECT 'order_id'    AS column_name, COUNT(*) - COUNT(order_id)    AS null_count FROM base
--   UNION ALL
--   SELECT 'customer_id', COUNT(*) - COUNT(customer_id) FROM base
--   UNION ALL
--   SELECT 'order_date',  COUNT(*) - COUNT(order_date)  FROM base
--   UNION ALL
--   SELECT 'amount',      COUNT(*) - COUNT(amount)      FROM base
-- )
-- SELECT
--   column_name,
--   null_count,
--   (SELECT COUNT(*) FROM base) AS total_rows,
--   ROUND(100.0 * null_count / (SELECT COUNT(*) FROM base), 2) AS null_pct
-- FROM metrics
-- ORDER BY null_count DESC;
