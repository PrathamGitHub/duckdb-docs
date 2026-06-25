-- =============================================================================
-- build_fact_table.sql
-- Purpose: Build a curated fact table with measures and dimension foreign keys.
-- Workflow: staging → curated (dimensional modeling)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  f.{{fact_key_column}},
  d.{{surrogate_key_column}},
  f.{{measure_column}},
  f.{{date_column}}
FROM {{fact_source_table}} AS f
INNER JOIN {{dimension_table}} AS d
  ON f.{{natural_key_column}} = d.{{natural_key_column}}
WHERE f.{{measure_column}} IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Example: orders fact linked to customer dimension
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.fct_orders AS
-- SELECT
--   o.order_id,
--   d.customer_sk,
--   o.amount,
--   o.order_date
-- FROM staging.stg_orders AS o
-- INNER JOIN curated.dim_customers AS d
--   ON o.customer_id = d.customer_id
-- WHERE o.amount IS NOT NULL;
