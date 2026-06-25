-- =============================================================================
-- build_dimension_table.sql
-- Purpose: Build a curated dimension table with surrogate keys and attributes.
-- Workflow: staging → curated (dimensional modeling)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS curated;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT
  ROW_NUMBER() OVER (ORDER BY {{natural_key_column}}) AS {{surrogate_key_column}},
  {{natural_key_column}},
  {{attribute_columns}}
FROM (
  SELECT DISTINCT
    {{natural_key_column}},
    {{attribute_columns}}
  FROM {{source_table}}
  WHERE {{natural_key_column}} IS NOT NULL
) AS deduped;

-- -----------------------------------------------------------------------------
-- Example: customer dimension from staging
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS curated;
--
-- CREATE OR REPLACE TABLE curated.dim_customers AS
-- SELECT
--   ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_sk,
--   customer_id,
--   customer_name,
--   region,
--   segment
-- FROM (
--   SELECT DISTINCT
--     customer_id,
--     customer_name,
--     region,
--     segment
--   FROM staging.stg_customers
--   WHERE customer_id IS NOT NULL
-- ) AS deduped;
