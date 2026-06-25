-- =============================================================================
-- join_template.sql
-- Purpose: Join two staging or curated tables with explicit join keys.
-- Workflow: staging → curated (enrichment joins)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  a.{{left_key_column}},
  a.{{left_attribute_column}},
  b.{{right_attribute_column}}
FROM {{left_table}} AS a
{{join_type}} JOIN {{right_table}} AS b
  ON a.{{left_key_column}} = b.{{right_key_column}};

-- -----------------------------------------------------------------------------
-- Example: inner join orders to customers
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.cur_orders_enriched AS
-- SELECT
--   o.order_id,
--   o.order_date,
--   o.amount,
--   c.customer_name,
--   c.region
-- FROM staging.stg_orders AS o
-- INNER JOIN staging.stg_customers AS c
--   ON o.customer_id = c.customer_id;
