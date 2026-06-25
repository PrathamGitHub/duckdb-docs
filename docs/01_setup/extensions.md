# Extensions

DuckDB extensions add formats, protocols, and federated database access. Load only what each notebook needs — `httpfs` and `spatial` are the most common in this repository.

## Purpose

Enable reading remote files, spatial formats, Excel workbooks, nested JSON, and external Postgres or SQLite databases from the same DuckDB session used for layered SQL workflows.

## When to Use

| Extension | Use when |
|-----------|----------|
| `httpfs` | Reading CSV, Parquet, or GeoJSON from HTTP/HTTPS URLs; S3 and cloud paths |
| `spatial` | Shapefile, GeoJSON, GeoParquet, FileGDB; `ST_*` functions |
| `excel` | Ingesting `.xlsx` / `.xls` spreadsheets into `raw` |
| `json` | Nested JSON, `read_json`, JSON export functions |
| `postgres` | Querying or attaching PostgreSQL tables (federation) |
| `sqlite` | Querying or attaching SQLite `.db` files |

Install once per database (or environment), then `LOAD` at the start of each session.

## Required Code

```python
import duckdb

con = duckdb.connect("work.duckdb")

def load_extensions(connection, names: list[str]) -> None:
    for name in names:
        connection.execute(f"INSTALL {name};")
        connection.execute(f"LOAD {name};")

load_extensions(con, ["httpfs", "spatial"])
```

```sql
-- SQL equivalent (run in a notebook %%sql cell or con.execute)
INSTALL httpfs;  LOAD httpfs;
INSTALL spatial; LOAD spatial;
```

## Example

### `httpfs` — real-world online CSV into `raw`

```sql
INSTALL httpfs;
LOAD httpfs;

CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

### `spatial` — GeoJSON from URL

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_regions_geojson AS
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
```

Supported spatial sources in this repo: **Shapefile**, **GeoParquet**, **GeoJSON**, **ESRI File Geodatabase** (`.gdb`).

```sql
-- Local Shapefile (path from project_paths.md)
CREATE OR REPLACE TABLE raw.raw_parcels_shp AS
SELECT * FROM ST_Read('data/source/parcels.shp');

-- GeoParquet
CREATE OR REPLACE TABLE raw.raw_boundaries_geoparquet AS
SELECT * FROM ST_Read('data/source/boundaries.parquet');

-- File Geodatabase (folder path)
CREATE OR REPLACE TABLE raw.raw_zoning_gdb AS
SELECT * FROM ST_Read('data/source/city_zoning.gdb', layer='Zoning');
```

### `excel` — spreadsheet ingest

```sql
INSTALL excel;
LOAD excel;

CREATE OR REPLACE TABLE raw.raw_sales_xlsx AS
SELECT * FROM read_xlsx('data/source/sales_report.xlsx', sheet='Sheet1');
```

### `json` — nested documents

```sql
INSTALL json;
LOAD json;

CREATE OR REPLACE TABLE raw.raw_api_json AS
SELECT *
FROM read_json('https://example.com/api/data.json', auto_detect=true);
```

### `postgres` — federate PostgreSQL

```sql
INSTALL postgres;
LOAD postgres;

-- Query remote schema without copying (adjust connection string)
CREATE OR REPLACE TABLE raw.raw_customers_pg AS
SELECT *
FROM postgres_scan(
  'host=localhost port=5432 dbname=analytics user=reader password=secret',
  'public',
  'customers'
);
```

### `sqlite` — attach or scan SQLite

```sql
INSTALL sqlite;
LOAD sqlite;

CREATE OR REPLACE TABLE raw.raw_legacy_sqlite AS
SELECT *
FROM sqlite_scan('data/source/legacy.db', 'orders');
```

## Common Variations

### Check installed and loaded extensions

```sql
SELECT extension_name, loaded, installed
FROM duckdb_extensions()
ORDER BY extension_name;
```

### Load extensions in Python with error handling (scripts)

```python
REQUIRED = ["httpfs", "spatial", "json"]

for ext in REQUIRED:
    con.execute(f"INSTALL {ext};")
    con.execute(f"LOAD {ext};")
```

### S3 reads (requires `httpfs` + credentials)

```sql
INSTALL httpfs;
LOAD httpfs;

SET s3_region = 'us-east-1';
-- SET s3_access_key_id = '...';
-- SET s3_secret_access_key = '...';

SELECT *
FROM read_parquet('s3://bucket/path/data.parquet')
LIMIT 10;
```

### Spatial export via GDAL driver

```sql
COPY (
  SELECT id, name, geom
  FROM curated.cur_regions
) TO 'data/output/regions.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

### Minimal tabular-only notebook

```python
load_extensions(con, ["httpfs", "json"])
```

### Spatial + remote + Excel notebook

```python
load_extensions(con, ["httpfs", "spatial", "excel", "json"])
```

## Notes or Limitations

- `INSTALL` downloads the extension artifact; `LOAD` activates it for the **current connection**. After kernel restart, run `LOAD` again (re-`INSTALL` only if not already installed).
- Extension names in DuckDB 1.x: use `postgres` and `sqlite` (older docs may say `postgres_scanner` / `sqlite_scanner`).
- `spatial` depends on GDAL drivers available in your environment; some formats (FileGDB, certain projections) may need extra system libraries.
- `postgres_scan` and `sqlite_scan` are for **read-heavy federation**; for production pipelines, prefer copying into `raw` for auditability and repeatability.
- Remote URLs depend on network access and stable hosts; mirror critical sources to `data/source/` ([project_paths.md](project_paths.md)).
- Do not commit secrets in connection strings; use environment variables or local config outside git.

## Related Pages

- [Notebook setup cell](notebook_setup_cell.md)
- [Local database](local_database.md)
- [Project paths](project_paths.md)

Official reference: [DuckDB extensions](https://duckdb.org/docs/stable/extensions/overview.html)
