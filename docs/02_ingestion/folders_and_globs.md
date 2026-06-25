# Folders and Globs

Ingest many files at once from a directory using glob patterns. This pattern is essential when `source` delivers daily drops, regional extracts, or multi-file exports into `data/raw/`.

## Purpose

Register a folder of homogeneous files (CSV, Parquet, JSON) as a single `raw_<dataset_name>` view or table, optionally tracking `filename` for lineage.

## When to Use

- Multiple files share the same schema (e.g. `events_2024_01.csv`, `events_2024_02.csv`)
- A vendor drops files into `data/raw/orders/` without merging them
- You need one SQL table for `raw_events` while keeping files separate on disk
- Exploratory ingest before consolidating upstream

Use [partitioned Parquet](partitioned_parquet.md) when directory names encode partition columns (`year=2024/month=06/`).

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Homogeneity | Files in the glob should share compatible schemas |
| Layout | Files live under `data/raw/<topic>/` or `data/source/` mirrors |
| Pattern | DuckDB accepts `*`, `**`, and brace lists in paths |
| Lineage | Pass `filename = true` to add a `filename` column |
| Naming | `raw_<topic>_<format>` — e.g. `raw.raw_events_csv`, `raw.raw_orders_parquet` |

## Basic DuckDB SQL

CSV glob:

```sql
SELECT *, filename
FROM read_csv_auto('data/raw/events/*.csv', filename = true)
LIMIT 20;
```

Parquet recursive glob:

```sql
SELECT *
FROM read_parquet('data/raw/events/**/*.parquet')
LIMIT 20;
```

JSON lines folder:

```sql
SELECT *
FROM read_json('data/raw/events/*.jsonl', format = 'newline_delimited', auto_detect = true)
LIMIT 20;
```

## Create Raw View Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_events_csv AS
SELECT *, filename AS source_file
FROM read_csv_auto('data/raw/events/*.csv', filename = true);
```

```sql
CREATE OR REPLACE VIEW raw.raw_orders_parquet AS
SELECT *, filename AS source_file
FROM read_parquet('data/raw/orders/*.parquet', filename = true);
```

## Create Raw Table Pattern

```sql
CREATE OR REPLACE TABLE raw.raw_events_csv AS
SELECT *, filename AS source_file
FROM read_csv_auto('data/raw/events/*.csv', filename = true);
```

```sql
CREATE OR REPLACE TABLE raw.raw_customers_parquet AS
SELECT *
FROM read_parquet('data/raw/customers/**/*.parquet');
```

Materialize only new files (pattern for incremental practice — full refresh is simpler early on):

```sql
-- Full refresh (recommended until staging logic is stable)
CREATE OR REPLACE TABLE raw.raw_events_csv AS
SELECT *, filename AS source_file
FROM read_csv_auto('data/raw/events/**/*.csv', filename = true);
```

## Notebook Usage Example

Download or place multiple CSV shards, then ingest:

```python
from pathlib import Path

events_dir = RAW_DIR / "events"
events_dir.mkdir(parents=True, exist_ok=True)

# Example: two public CSV shards (replace with your drops)
URLS = {
    "events_part_a.csv": "https://raw.githubusercontent.com/datasets/population/master/data/population.csv",
}
for name, url in URLS.items():
    dest = events_dir / name
    if not dest.exists():
        import urllib.request
        urllib.request.urlretrieve(url, dest)

glob_path = (events_dir / "*.csv").as_posix()
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_events_csv AS
SELECT *, filename AS source_file
FROM read_csv_auto('{glob_path}', filename = true);
""")

con.sql("""
SELECT source_file, COUNT(*) AS n
FROM raw.raw_events_csv
GROUP BY source_file
""").df()
```

Build file list in Python when globs are dynamic:

```python
csv_files = sorted(RAW_DIR.glob("orders/*.csv"))
paths = [p.as_posix() for p in csv_files]

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_orders_csv AS
SELECT * FROM read_csv_auto({paths!r});
""")
```

## Common Variations

### Brace expansion (explicit months)

```sql
SELECT *
FROM read_csv_auto('data/raw/events/events_2024_{01,02,03}.csv');
```

### Union CSV + Parquet (separate raw tables — do not mix formats in one table)

```sql
CREATE OR REPLACE TABLE raw.raw_events_csv AS
SELECT *, filename AS source_file
FROM read_csv_auto('data/raw/events/*.csv', filename = true);

CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT *, filename AS source_file
FROM read_parquet('data/raw/events/*.parquet', filename = true);
```

### Filter files by name in SQL (after `filename = true`)

```sql
SELECT *
FROM raw.raw_events_csv
WHERE source_file LIKE '%_2024_%';
```

### Spatial folder of Shapefiles

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_parcels_shp AS
SELECT *, filename AS source_file
FROM ST_Read('data/raw/parcels/*.shp');
```

### Exclude sidecar files

Glob only the data extension — e.g. `*.csv` not `*.csv.meta`.

## Validation Checks After Ingestion

```sql
-- Files represented
SELECT source_file, COUNT(*) AS row_count
FROM raw.raw_events_csv
GROUP BY source_file
ORDER BY source_file;

-- Total rows
SELECT COUNT(*) AS total_rows FROM raw.raw_events_csv;

-- Schema drift across files (compare samples)
SELECT * FROM raw.raw_events_csv WHERE source_file LIKE '%part_a%' LIMIT 1;
SELECT * FROM raw.raw_events_csv WHERE source_file LIKE '%part_b%' LIMIT 1;

-- Duplicate keys within and across files
SELECT order_id, COUNT(*) AS n
FROM raw.raw_orders_csv
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Empty file detection
SELECT source_file
FROM raw.raw_events_csv
GROUP BY source_file
HAVING COUNT(*) = 0;
```

## Performance Notes

- Fewer, larger files outperform thousands of tiny shards — consolidate in `source` when you control layout.
- `read_parquet` globs use metadata efficiently; CSV globs must parse text — prefer Parquet at scale.
- `filename = true` adds a small metadata column — useful for debugging, cheap to keep through `staging`.
- Materializing a **table** avoids re-listing and re-reading the folder on every query.
- Place hot folders on local SSD; network mounts slow glob listing.

## Known Limitations

- One bad file in a glob can fail the entire read — isolate with per-file loops in Python for messy vendor drops.
- Schema drift across files may produce type widening or errors — validate per `source_file`.
- Globs do not infer Hive partition columns from path — use [partitioned Parquet](partitioned_parquet.md).
- Shapefile globs need all sidecar files (`.shx`, `.dbf`, `.prj`) per basename — broken pairs fail `ST_Read`.
- Order of rows across files is not guaranteed to be meaningful — sort in `staging` if needed.

## Related Pages

- [CSV ingestion](csv.md)
- [Parquet ingestion](parquet.md)
- [Partitioned Parquet](partitioned_parquet.md)
- [Project paths](../01_setup/project_paths.md)

Official reference: [DuckDB reading multiple files](https://duckdb.org/docs/current/data/multiple_files/overview.html)
