# CSV Ingestion

Ingest comma-separated and delimiter-separated text files into the `raw` layer using DuckDB's CSV reader. CSV is the most common tabular `source` format for analysts and engineers; notebooks should register files as `raw_<dataset_name>` before any cleaning in `staging`.

## Purpose

Load delimited text files (local paths, `data/raw/` mirrors, or HTTP URLs) into DuckDB with automatic type detection, then expose them as auditable `raw` views or tables for downstream staging.

## When to Use

- Vendor or government exports delivered as `.csv`
- Small-to-medium datasets where Parquet is not yet available
- Quick exploration of a new file before promoting logic to a pipeline
- Mirroring an online dataset (e.g. open data portal) into `raw` for repeatable practice

Prefer Parquet when the source already provides it — CSV lacks embedded types and compresses poorly.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| File encoding | UTF-8 unless you set `encoding` |
| Header row | Present by default (`header=true`); set `header=false` for headerless files |
| Delimiter | Comma by default; use `delim='|'` or `delim='\t'` for pipe/TSV |
| Layer | File is **source**; DuckDB object lives in schema `raw` |
| Naming | Table or view name: `raw_<topic>_csv` (e.g. `raw.raw_orders_csv`) |
| Paths | Use `Path.as_posix()` when embedding local paths in SQL strings |

Optional local mirror path: `data/raw/orders.csv` (gitignore large files).

## Basic DuckDB SQL

Read without persisting (exploration):

```sql
SELECT *
FROM read_csv_auto('data/raw/orders.csv')
LIMIT 20;
```

Read from a real-world online dataset (population by country):

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT country_name, year, value
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
)
WHERE year = '2020'
ORDER BY value DESC
LIMIT 10;
```

Explicit options when auto-detection is wrong:

```sql
SELECT *
FROM read_csv(
  'data/raw/events.csv',
  header = true,
  delim = ',',
  quote = '"',
  escape = '"',
  nullstr = ['', 'NA', 'null'],
  types = {'order_id': 'VARCHAR', 'amount': 'DOUBLE'}
);
```

## Create Raw View Pattern

Use a **view** when the file is large, changes often, or you want zero-copy reads during early EDA. Views re-read the file on each query.

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_customers_csv AS
SELECT *
FROM read_csv_auto('data/raw/customers.csv');
```

Remote source as a view (practice dataset):

```sql
CREATE OR REPLACE VIEW raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

## Create Raw Table Pattern

Use a **table** for the standard workflow layer — snapshot what arrived from `source` so re-runs of `staging` do not depend on the file still being identical.

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_orders_csv AS
SELECT *
FROM read_csv_auto('data/raw/orders.csv');
```

Online ingest into a durable `raw` snapshot:

```sql
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

## Notebook Usage Example

After the [notebook setup cell](../01_setup/notebook_setup_cell.md):

```python
from pathlib import Path

SOURCE_URL = (
    "https://raw.githubusercontent.com/datasets/population/master/data/population.csv"
)
local_csv = RAW_DIR / "population.csv"

# Optional: mirror source to data/raw/ for offline practice
if not local_csv.exists():
    import urllib.request
    urllib.request.urlretrieve(SOURCE_URL, local_csv)

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto('{local_csv.as_posix()}');
""")

con.sql("""
SELECT country_name, year, CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE year = '2020'
ORDER BY population DESC
LIMIT 10
""").df()
```

## Common Variations

### Multiple CSV files with the same schema

```sql
CREATE OR REPLACE TABLE raw.raw_events_csv AS
SELECT *
FROM read_csv_auto(['data/raw/events_2024_01.csv', 'data/raw/events_2024_02.csv']);
```

### Glob all CSVs in a folder

```sql
CREATE OR REPLACE TABLE raw.raw_events_csv AS
SELECT *, filename AS source_file
FROM read_csv_auto('data/raw/events_*.csv', filename = true);
```

### Skip rows (metadata headers)

```sql
SELECT *
FROM read_csv_auto('data/raw/report.csv', skip = 3);
```

### Column selection at ingest (still `raw`, minimal projection only)

```sql
CREATE OR REPLACE TABLE raw.raw_orders_csv AS
SELECT order_id, customer_id, order_date, amount
FROM read_csv_auto('data/raw/orders.csv');
```

### GIS-friendly CSV (lon/lat columns, no geometry yet)

```sql
CREATE OR REPLACE TABLE raw.raw_stores_csv AS
SELECT *
FROM read_csv_auto('data/raw/stores.csv');
-- Build geometry in staging: ST_Point(lon, lat)
```

## Validation Checks After Ingestion

Run these before building `staging`:

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_orders_csv;

-- Column names and types
DESCRIBE raw.raw_orders_csv;

-- Null rate on expected key columns
SELECT
  COUNT(*) AS total_rows,
  COUNT(order_id) AS non_null_order_id,
  COUNT(*) - COUNT(order_id) AS null_order_id
FROM raw.raw_orders_csv;

-- Duplicate primary key (adjust column names)
SELECT order_id, COUNT(*) AS n
FROM raw.raw_orders_csv
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Sample rows
SELECT * FROM raw.raw_orders_csv USING SAMPLE 5;
```

For the population practice dataset:

```sql
SELECT MIN(year) AS min_year, MAX(year) AS max_year, COUNT(*) AS n
FROM raw.raw_population_csv;
```

## Performance Notes

- `read_csv_auto` samples the file for types — fast for exploration; for production ingest of huge files, pass explicit `types` to avoid rescan surprises.
- **Tables** materialize once; **views** re-parse CSV on every query — prefer tables in `raw` for pipelines.
- Use `parallel=true` (default in recent DuckDB versions) for large local files on SSD.
- Compress archives externally (`.gz`); DuckDB can read gzip CSV directly when the extension supports it.
- Narrow columns early in `staging`, not by hiding columns in a view during repeated full-file scans.

## Known Limitations

- Type inference can misclassify IDs with leading zeros or mixed-type columns — cast in `staging`.
- Very wide or messy CSVs (embedded newlines, inconsistent quoting) may need `read_csv` with manual options or pre-cleaning in `source`.
- CSV has no schema contract; upstream format changes break pipelines — validate column sets after each ingest.
- Remote HTTP reads require `httpfs` and a stable URL; mirror critical files to `data/raw/`.
- Not ideal for nested or hierarchical data — use [JSON ingestion](json.md) instead.

## Related Pages

- [Folders and globs](folders_and_globs.md)
- [Remote files (HTTP / S3)](remote_files_http_s3.md)
- [Workflow layers](../00_overview/workflow_layers.md)
- [Naming conventions](../00_overview/naming_conventions.md)

Official reference: [DuckDB CSV import](https://duckdb.org/docs/current/data/csv/overview.html)
