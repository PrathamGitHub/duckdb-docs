-- =============================================================================
-- ingest_partitioned_parquet.sql
-- Purpose: Load Hive-partitioned Parquet datasets (glob or directory) into raw.
-- Workflow: source → raw
-- Prerequisites: load_common_extensions.sql (httpfs for remote paths)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM read_parquet(
  '{{input_path}}',
  hive_partitioning = true
);

-- -----------------------------------------------------------------------------
-- Example: partitioned events under data/source/events/
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_events_partitioned AS
-- SELECT *
-- FROM read_parquet(
--   'data/source/events/**/*.parquet',
--   hive_partitioning = true
-- );
