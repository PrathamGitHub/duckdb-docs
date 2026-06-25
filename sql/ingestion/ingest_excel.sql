-- =============================================================================
-- ingest_excel.sql
-- Purpose: Load an Excel workbook sheet into a raw schema table.
-- Workflow: source → raw
-- Prerequisites: INSTALL excel; LOAD excel;
-- =============================================================================

INSTALL excel;
LOAD excel;

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE {{table_name}} AS
SELECT *
FROM read_xlsx(
  '{{input_path}}',
  sheet = '{{sheet_name}}',
  header = true
);

-- -----------------------------------------------------------------------------
-- Example: local sales workbook into raw
-- -----------------------------------------------------------------------------
-- INSTALL excel; LOAD excel;
--
-- CREATE SCHEMA IF NOT EXISTS raw;
--
-- CREATE OR REPLACE TABLE raw.raw_sales_xlsx AS
-- SELECT *
-- FROM read_xlsx(
--   'data/source/sales_report.xlsx',
--   sheet = 'Sheet1',
--   header = true
-- );
