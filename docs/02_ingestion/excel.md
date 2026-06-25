# Excel Ingestion

Ingest Microsoft Excel workbooks (`.xlsx`, `.xls`) into the `raw` layer using DuckDB's `excel` extension and `read_xlsx`.

## Purpose

Load spreadsheet exports — common from analysts, finance teams, and field data collection — into typed DuckDB `raw` tables without a separate Python pandas step, keeping SQL visible in notebooks.

## When to Use

- Source arrives as `.xlsx` or `.xls` from a business user
- Multiple sheets need to land as separate `raw` tables
- You are prototyping before asking upstream for CSV or Parquet
- One-off government or NGO reports published only as Excel

Avoid Excel for large recurring pipelines when a database or Parquet export is available.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Extension | `INSTALL excel; LOAD excel;` each session |
| Sheet | Default first sheet, or pass `sheet='Sheet1'` / `sheet=0` |
| Header | First row contains column names unless you reshape in `staging` |
| Layer | Workbook path is **source**; optional mirror under `data/raw/` |
| Naming | `raw_<topic>_xlsx` — e.g. `raw.raw_sales_xlsx` |
| Types | Mixed Excel types may need cleanup in `staging` |

## Basic DuckDB SQL

```sql
INSTALL excel;
LOAD excel;

SELECT *
FROM read_xlsx('data/raw/sales_report.xlsx', sheet = 'Orders')
LIMIT 20;
```

All sheets (explore names first):

```sql
SELECT *
FROM read_xlsx('data/raw/sales_report.xlsx', sheet = 'Customers')
LIMIT 10;
```

Range-limited read (skip title rows):

```sql
SELECT *
FROM read_xlsx(
  'data/raw/sales_report.xlsx',
  sheet = 'Orders',
  range = 'A4:F1000'
);
```

## Create Raw View Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_customers_xlsx AS
SELECT *
FROM read_xlsx('data/raw/customers.xlsx', sheet = 'Sheet1');
```

## Create Raw Table Pattern

```sql
CREATE OR REPLACE TABLE raw.raw_orders_xlsx AS
SELECT *
FROM read_xlsx('data/raw/orders.xlsx', sheet = 'Orders');
```

Multiple sheets → multiple `raw` tables:

```sql
CREATE OR REPLACE TABLE raw.raw_orders_xlsx AS
SELECT * FROM read_xlsx('data/raw/operations.xlsx', sheet = 'Orders');

CREATE OR REPLACE TABLE raw.raw_customers_xlsx AS
SELECT * FROM read_xlsx('data/raw/operations.xlsx', sheet = 'Customers');
```

## Notebook Usage Example

Mirror a public sample workbook, then ingest (replace URL with your organization's file when ready):

```python
SAMPLE_XLSX_URL = (
    "https://go.microsoft.com/fwlink/?LinkID=521962"
)
local_xlsx = RAW_DIR / "sample_workbook.xlsx"

if not local_xlsx.exists():
    import urllib.request
    urllib.request.urlretrieve(SAMPLE_XLSX_URL, local_xlsx)

con.execute("INSTALL excel; LOAD excel;")

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_sample_xlsx AS
SELECT * FROM read_xlsx('{local_xlsx.as_posix()}', sheet = 'Sheet1');
""")

con.sql("SELECT * FROM raw.raw_sample_xlsx LIMIT 10").df()
```

For project-specific orders and customers workbooks in `data/raw/`:

```python
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_orders_xlsx AS
SELECT * FROM read_xlsx('{(RAW_DIR / "orders.xlsx").as_posix()}', sheet = 'Orders');
""")
```

## Common Variations

### Treat row 2 as header (skip banner row)

Handle in `staging` if `read_xlsx` picks up a title row:

```sql
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT *
FROM raw.raw_orders_xlsx
WHERE order_id IS NOT NULL
  AND order_id <> 'Order ID';
```

### Add ingest metadata

```sql
CREATE OR REPLACE TABLE raw.raw_orders_xlsx AS
SELECT
  *,
  'data/raw/orders.xlsx' AS source_path,
  current_timestamp AS ingested_at
FROM read_xlsx('data/raw/orders.xlsx', sheet = 'Orders');
```

### Combine with HTTP download

```python
import urllib.request

url = "https://example.com/published/report.xlsx"
dest = RAW_DIR / "monthly_report.xlsx"
urllib.request.urlretrieve(url, dest)
```

### Spatial note

Excel sometimes stores lon/lat columns — ingest as `raw`, build `geom` in `staging`:

```sql
-- staging example (after raw ingest)
CREATE OR REPLACE TABLE staging.stg_sites AS
SELECT
  site_id,
  site_name,
  ST_Point(CAST(lon AS DOUBLE), CAST(lat AS DOUBLE)) AS geom
FROM raw.raw_sites_xlsx
WHERE lon IS NOT NULL AND lat IS NOT NULL;
```

## Validation Checks After Ingestion

```sql
-- Row and column count
SELECT COUNT(*) AS row_count FROM raw.raw_orders_xlsx;
DESCRIBE raw.raw_orders_xlsx;

-- Unexpected blank rows
SELECT COUNT(*) AS empty_id_rows
FROM raw.raw_orders_xlsx
WHERE order_id IS NULL;

-- Duplicate keys
SELECT order_id, COUNT(*) AS n
FROM raw.raw_orders_xlsx
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Sheet landed correctly (spot check)
SELECT * FROM raw.raw_orders_xlsx LIMIT 5;
```

Compare workbook row count to SQL count when the source documents expected totals.

## Performance Notes

- Excel is slower and larger than Parquet — convert stable datasets to Parquet in `output` or `data/raw/` after first ingest.
- Prefer **tables** in `raw` for workbooks you read repeatedly; views re-parse the workbook each query.
- Limit `range` when only a subsection of a huge sheet is needed.
- One workbook per ingest keeps failure isolation simpler than multi-sheet unions in one table.

## Known Limitations

- Requires the `excel` extension (extra dependency vs core CSV/Parquet).
- Macros, charts, and pivot tables are ignored — only cell data is read.
- Date cells may arrive as timestamps or Excel serial numbers — normalize in `staging`.
- Merged cells and multi-row headers confuse auto-detection — fix with `range` or manual cleanup.
- `.xls` (legacy binary) support varies; prefer `.xlsx` from upstream when possible.
- Not suitable for very large files (millions of rows) — request Parquet or database export instead.

## Related Pages

- [CSV ingestion](csv.md) — when users can export to CSV instead
- [Extensions](../01_setup/extensions.md)
- [Notebook setup cell](../01_setup/notebook_setup_cell.md)

Official reference: [DuckDB Excel import](https://duckdb.org/docs/current/guides/file_formats/excel_import.html)
