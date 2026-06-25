-- =============================================================================
-- deduplication.sql
-- Purpose: Keep one row per business key using a deterministic window rule.
-- Workflow: staging (after EDA duplicate_check)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE {{table_name}} AS
WITH ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY {{key_column}}
      ORDER BY {{tie_breaker_column}} DESC NULLS LAST
    ) AS rn
  FROM {{source_table}}
)
SELECT * EXCLUDE (rn)
FROM ranked
WHERE rn = 1;

-- -----------------------------------------------------------------------------
-- Example: dedupe orders by order_id, keep latest order_date
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS staging;
--
-- CREATE OR REPLACE TABLE staging.stg_orders_deduped AS
-- WITH ranked AS (
--   SELECT
--     *,
--     ROW_NUMBER() OVER (
--       PARTITION BY order_id
--       ORDER BY order_date DESC NULLS LAST
--     ) AS rn
--   FROM staging.stg_orders
-- )
-- SELECT * EXCLUDE (rn)
-- FROM ranked
-- WHERE rn = 1;
