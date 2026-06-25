-- =============================================================================
-- ingest_json.sql
-- Purpose: Load JSON or NDJSON files into a raw schema table.
-- Workflow: source → raw
-- Prerequisites: load_common_extensions.sql (httpfs for remote URLs, json extension)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM read_json(
  '{{input_path}}',
  auto_detect = true,
  format = 'auto'
);

-- -----------------------------------------------------------------------------
-- Example: JSON array from a local file into raw
-- -----------------------------------------------------------------------------
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_events_json AS
-- SELECT *
-- FROM read_json(
--   'data/source/events.json',
--   auto_detect = true,
--   format = 'auto'
-- );
