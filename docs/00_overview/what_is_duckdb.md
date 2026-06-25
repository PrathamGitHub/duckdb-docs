# What Is DuckDB?

DuckDB is an in-process analytical database: you run it inside your Python notebook, script, or CLI session without standing up a separate database server. It speaks SQL, reads files directly, and is built for fast analytics on tabular and spatial data.

In this repository, **notebooks are the primary working interface**. You explore data in cells, keep SQL visible, and promote stable logic into reusable `.sql` or `.py` files when a workflow matures.

## Who This Is For

| Role | Typical use in this repo |
|------|--------------------------|
| Analyst | Explore CSVs, run aggregations, export reports |
| Data engineer | Layered ETL with `raw` → `staging` → `curated` → `output` |
| GIS analyst | Ingest Shapefile, GeoJSON, GeoParquet, FileGDB; spatial joins and exports |
| Python user | `duckdb` package in Jupyter; mix SQL and DataFrames |
| SQL user | Pure SQL workflows in notebook cells or `.sql` templates |

## What DuckDB Does Well Here

- **Read files in place** — CSV, Parquet, JSON, Excel, and remote URLs without a separate loader step
- **Run analytics SQL** — filters, joins, window functions, pivots, aggregations
- **Work with geometry** — via the `spatial` extension (`ST_Read`, `ST_Intersects`, buffers, exports)
- **Stay local and portable** — one `.duckdb` file or in-memory session; no cluster to manage
- **Federate sources** — query Postgres, SQLite, S3, and HTTP-hosted files in one session

## A Minimal Notebook Example

```python
import duckdb

con = duckdb.connect("work.duckdb")
con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("CREATE SCHEMA IF NOT EXISTS raw;")
```

Ingest a real-world online dataset into the `raw` layer:

```sql
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

Preview and summarize in the next cell:

```sql
SELECT country_name, year, value AS population
FROM raw.raw_population_csv
WHERE year = '2020'
ORDER BY population DESC
LIMIT 10;
```

## Spatial in the Same Session

Load the spatial extension and read GeoJSON from a URL:

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_regions_geojson AS
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
```

Other first-class spatial sources in this repo: **Shapefile**, **GeoParquet**, **GeoJSON**, and **ESRI File Geodatabase** (`.gdb`).

## How DuckDB Fits the Workflow Convention

Every example in this repository follows:

```text
source → raw → staging → curated → output
```

- **source** — external file, API, or database you do not control
- **raw** — as-ingested copy in DuckDB (minimal transformation)
- **staging** — cleaned, typed, join-ready tables
- **curated** — business-ready models for analysis and reporting
- **output** — Parquet, CSV, GeoParquet, GeoJSON, and other deliverables

DuckDB holds `raw`, `staging`, and `curated` in schemas (or views/tables). Files on disk under `data/` mirror exports and optional file-based layers.

## DuckDB vs. Other Tools (Practical View)

| Need | DuckDB in this repo |
|------|---------------------|
| Quick EDA on a CSV or Parquet file | Open notebook, `read_csv_auto` or `read_parquet`, query |
| Repeatable pipeline with validation | Layered schemas + templates + export to `output/` |
| Spatial overlay or clip | `spatial` extension; same SQL patterns as tabular |
| Massive multi-tenant production warehouse | Use DuckDB for local prep; hand off curated Parquet to your warehouse |

DuckDB is not a replacement for every system. It is an excellent **notebook-first engine** for ingestion, transformation, validation, and export—especially when your data fits on a single machine or you are prototyping before scaling out.

## Common Extensions in This Repo

```sql
INSTALL httpfs;  LOAD httpfs;   -- remote HTTP / S3 reads
INSTALL spatial; LOAD spatial;  -- geometry types and GDAL drivers
INSTALL json;    LOAD json;     -- nested JSON documents
```

## Next Steps

- [When to use DuckDB](when_to_use_duckdb.md) — fit and trade-offs
- [Workflow layers](workflow_layers.md) — what happens at each stage
- [Project structure](project_structure.md) — folders and files
- [Naming conventions](naming_conventions.md) — schemas, tables, and outputs

Official reference: [DuckDB documentation](https://duckdb.org/docs/current/)
