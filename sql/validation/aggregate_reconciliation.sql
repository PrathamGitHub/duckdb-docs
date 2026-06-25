-- =============================================================================
-- aggregate_reconciliation.sql
-- Purpose: Compare aggregate totals between two pipeline layers.
-- Workflow: validation (staging vs curated measure reconciliation)
-- =============================================================================

WITH source_agg AS (
  SELECT
    SUM({{measure_column}}) AS total_{{measure_column}},
    COUNT(*) AS row_count
  FROM {{source_table}}
),
target_agg AS (
  SELECT
    SUM({{measure_column}}) AS total_{{measure_column}},
    COUNT(*) AS row_count
  FROM {{target_table}}
)
SELECT
  'source' AS layer,
  s.total_{{measure_column}},
  s.row_count
FROM source_agg AS s
UNION ALL
SELECT
  'target',
  t.total_{{measure_column}},
  t.row_count
FROM target_agg AS t
UNION ALL
SELECT
  'delta',
  t.total_{{measure_column}} - s.total_{{measure_column}},
  t.row_count - s.row_count
FROM source_agg AS s, target_agg AS t;

-- -----------------------------------------------------------------------------
-- Example: reconcile order amount totals staging vs curated
-- -----------------------------------------------------------------------------
-- WITH source_agg AS (
--   SELECT SUM(amount) AS total_amount, COUNT(*) AS row_count
--   FROM staging.stg_orders
-- ),
-- target_agg AS (
--   SELECT SUM(amount) AS total_amount, COUNT(*) AS row_count
--   FROM curated.fct_orders
-- )
-- SELECT 'source' AS layer, s.total_amount, s.row_count FROM source_agg AS s
-- UNION ALL
-- SELECT 'target', t.total_amount, t.row_count FROM target_agg AS t
-- UNION ALL
-- SELECT 'delta', t.total_amount - s.total_amount, t.row_count - s.row_count
-- FROM source_agg AS s, target_agg AS t;
