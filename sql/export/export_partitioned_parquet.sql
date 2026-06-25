-- =============================================================================
-- export_partitioned_parquet.sql
-- Purpose: Export a table to Hive-partitioned Parquet files by a partition column.
-- Workflow: curated → output
-- =============================================================================

COPY (
  SELECT *
  FROM {{table_name}}
) TO '{{output_path}}'
(FORMAT PARQUET, PARTITION_BY ({{partition_column}}));

-- -----------------------------------------------------------------------------
-- Example: export orders partitioned by order year
-- -----------------------------------------------------------------------------
-- COPY (
--   SELECT
--     *,
--     EXTRACT(YEAR FROM order_date) AS order_year
--   FROM curated.fct_orders
-- ) TO 'data/output/fct_orders_partitioned/'
-- (FORMAT PARQUET, PARTITION_BY (order_year));
