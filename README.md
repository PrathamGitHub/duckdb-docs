# DuckDB Notebook-First Workflow Docs & Templates

A practical documentation and template repository for building repeatable DuckDB workflows across EDA, ETL, validation, exports, and spatial analytics.

## Purpose

This repository helps teams move from ad-hoc queries to reusable, layered workflows in DuckDB.  
It focuses on examples you can run in notebooks first, then adapt to scripts and pipelines.

Use this repo to:
- Ingest real-world online datasets
- Standardize SQL + Python patterns
- Build reliable layer-by-layer transformations
- Validate data quality before publishing outputs
- Work with both tabular and spatial sources

## Target Users

- Analysts
- Data engineers
- GIS analysts
- Python users
- SQL users

## Workflow Philosophy

Core convention:

```text
source → raw → staging → curated → output
```

Principles:
- Keep each layer simple and auditable
- Prefer small, composable notebook steps
- Separate ingestion, cleaning, business logic, and export
- Make validation a default step, not an afterthought

## Layer Definitions

- `source`: External systems and files (APIs, object storage, portals, local files)
- `raw`: As-ingested copies with minimal changes; schema preserved where possible
- `staging`: Cleaned, typed, standardized, and join-ready tables
- `curated`: Business-ready models for reporting, analytics, and downstream tools
- `output`: Final exports (Parquet, CSV, GeoParquet, GeoJSON, and related deliverables)

## Naming Conventions

Use clear and predictable names:

- Schemas by layer: `raw`, `staging`, `curated`
- Table prefixes by layer:
  - `raw_...` for ingested tables (include format suffix when helpful, e.g. `raw_orders_csv`)
  - `stg_...` for cleaned staging tables
  - `cur_...`, `fct_...`, `dim_...`, or `geo_...` for curated models (see [naming conventions](docs/00_overview/naming_conventions.md))
- Snake case for all table and column names
- Date-partitioned outputs when useful, for example: `output/sales_2026_06.parquet`

Example names:
- `raw.raw_population_csv`
- `staging.stg_population`
- `curated.cur_population_by_region`
- `curated.fct_orders`, `curated.dim_customers`, `curated.geo_parcels`

## Repository Structure

```text
duckeb-docs/
  README.md
  template_index.md       # Template catalog
  mkdocs.yml              # MkDocs site config
  docs/
    00_overview/          # Concepts and conventions
    01_setup/             # Connections, paths, extensions
    02_ingestion/         # Tabular source → raw
    03_spatial_ingestion/ # Shapefile, GeoJSON, GeoParquet, FileGDB
    04_eda/               # Profiling and exploration
    05_spatial_eda/       # Geometry QA and spatial profiling
    06_cleaning/          # Staging transforms
    07_transformation/    # Joins, aggregates, facts/dims
    08_spatial_transformation/
    09_validation/
    10_export/
    11_performance/
  notebooks/
    00_eda_base.ipynb
    01_etl_base.ipynb
    02_spatial_eda_base.ipynb
    03_validation_base.ipynb
    04_export_base.ipynb
  sql/                    # Reusable SQL templates
  python/                 # Notebook helper modules
  examples/               # Worked end-to-end scripts
  data/
    source/               # Optional local mirrors
    raw/
    staging/
    curated/
    output/
```

See [template_index.md](template_index.md) for the full catalog of template IDs and file locations.

## Notebook-First Approach

- Start each workflow as a notebook with short, testable cells
- Keep SQL in notebook cells for transparency and quick iteration
- Use Python where it improves ergonomics (I/O, orchestration, plotting)
- Promote stable notebook logic into reusable `sql/` and `python/` assets later

## Supported Data Sources

Common non-spatial sources:
- CSV / TSV
- Parquet
- JSON / NDJSON
- Excel
- HTTP-hosted files (direct URL reads)
- Local files and object storage paths

Real-world online dataset examples:
- City open data portals (CSV/GeoJSON endpoints)
- Public transport GTFS files
- Government statistics in CSV/Parquet

## Supported Spatial Sources

Spatial workflows are first-class in this repository.  
Supported source formats include:

- Shapefile (`.shp`)
- GeoParquet
- GeoJSON
- ESRI File Geodatabase (`.gdb`)

## Common DuckDB Extensions

Frequently used extensions:

- `httpfs` for remote file access
- `spatial` for geometry types and spatial functions
- `json` for nested and semi-structured data
- `postgres_scanner` or `sqlite_scanner` when federating external databases

```sql
INSTALL httpfs;
LOAD httpfs;

INSTALL spatial;
LOAD spatial;

INSTALL json;
LOAD json;
```

## Basic Setup Example

```python
import duckdb

con = duckdb.connect("work.duckdb")

con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("INSTALL spatial; LOAD spatial;")

con.execute("CREATE SCHEMA IF NOT EXISTS raw;")
con.execute("CREATE SCHEMA IF NOT EXISTS staging;")
con.execute("CREATE SCHEMA IF NOT EXISTS curated;")
```

## Example Source Registration

Ingest a real-world online CSV into the `raw` layer:

```sql
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

Spatial source registration example (GeoJSON):

```sql
CREATE OR REPLACE TABLE raw.raw_regions_geojson AS
SELECT *
FROM ST_Read('https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson');
```

## Example Staging Transformation

```sql
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  country_name,
  CAST(year AS INTEGER) AS year,
  CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv
WHERE value IS NOT NULL
  AND TRY_CAST(year AS INTEGER) IS NOT NULL;
```

Python notebook cell style:

```python
con.execute("""
CREATE OR REPLACE TABLE staging.stg_population_recent AS
SELECT *
FROM staging.stg_population
WHERE year >= 2000;
""")
```

## Example Validation Query

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(*) FILTER (WHERE population IS NULL) AS null_population_rows,
  MIN(year) AS min_year,
  MAX(year) AS max_year
FROM staging.stg_population;
```

Duplicate key check (zero rows means pass):

```sql
SELECT country_name, year, COUNT(*) AS n
FROM staging.stg_population
GROUP BY 1, 2
HAVING COUNT(*) > 1;
```

## Example Export Query

Export curated data to Parquet:

```sql
COPY (
  SELECT *
  FROM curated.cur_population_by_region
) TO 'data/output/population_by_region.parquet'
(FORMAT PARQUET);
```

Export spatial output to GeoJSON:

```sql
COPY (
  SELECT id, name, geom
  FROM curated.cur_regions
) TO 'data/output/regions.geojson'
(FORMAT GDAL, DRIVER 'GeoJSON');
```

## Design Principles

- Notebook-first, production-friendly
- Layered transformations over monolithic SQL
- Reusable examples over long theory
- Explicit validation before export
- Consistent naming and folder layout
- Spatial and tabular workflows treated equally

## Recommended Development Order

1. Create connection, schemas, and required extensions
2. Register and ingest one real online source into `raw`
3. Build minimal `staging` cleaning and typing logic
4. Add validation checks (nulls, duplicates, ranges, row counts)
5. Build first `curated` model for a specific use case
6. Export to `output` formats required by consumers
7. Repeat with spatial sources (Shapefile, GeoParquet, GeoJSON, FileGDB)

## Documentation Site (MkDocs)

Run docs locally:

```bash
uv sync --group dev
uv run mkdocs serve
```

Build docs locally:

```bash
uv run mkdocs build --strict
```

Publish with GitHub Pages:

1. Push to the `main` branch.
2. The workflow at `.github/workflows/docs-pages.yml` builds and deploys the site.
3. In repository settings, ensure Pages uses **GitHub Actions** as the source.
