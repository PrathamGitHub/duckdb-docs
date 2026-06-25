# Project Structure

This repository is organized for **notebook-first** workflows: explore in Jupyter, reuse SQL templates, and keep data layers predictable on disk and in DuckDB.

## Top-Level Layout

```text
duckeb-docs/
  README.md                 # Repository entry point
  template_index.md         # Template catalog (IDs and file locations)
  mkdocs.yml                # MkDocs site configuration
  pyproject.toml            # Python deps (duckdb, ipykernel)
  docs/                     # MkDocs documentation (you are here)
    00_overview/
    01_setup/
    02_ingestion/
    03_spatial_ingestion/
    04_eda/
    05_spatial_eda/
    06_cleaning/
    07_transformation/
    08_spatial_transformation/
    09_validation/
    10_export/
    11_performance/
  notebooks/                # Runnable workflow notebooks
    00_eda_base.ipynb
    01_etl_base.ipynb
    02_spatial_eda_base.ipynb
    03_validation_base.ipynb
    04_export_base.ipynb
    templates/              # (planned) single-task notebook starters
  sql/                      # Reusable SQL snippets by task
  python/                   # Connection, paths, EDA, validation helpers
  examples/                 # Worked CSV and spatial pipelines
  data/                     # File-based layers (gitignore large files)
    source/                 # Optional local mirrors of external files
    raw/
    staging/
    curated/
    output/                 # Published deliverables
```

Not every project needs every folder on day one. Start with `notebooks/01_etl_base.ipynb`, one `work.duckdb`, and `data/output/`; add `sql/` patterns as workflows stabilize.

## Documentation (`docs/`)

| Path | Purpose |
|------|---------|
| `docs/00_overview/` | Concepts: DuckDB fit, layers, naming, structure |
| `docs/01_setup/` | Extensions, connections, paths, notebook setup |
| `docs/02_ingestion/` | CSV, Parquet, JSON, Excel, remote URLs |
| `docs/03_spatial_ingestion/` | Shapefile, GeoParquet, GeoJSON, FileGDB |
| `docs/04_eda/` | Profiling, nulls, duplicates, summaries |
| `docs/05_spatial_eda/` | Geometry type, extent, CRS, validity |
| `docs/06_cleaning/` | Text, casting, dates, deduplication |
| `docs/07_transformation/` | Joins, aggregates, windows, facts/dims |
| `docs/08_spatial_transformation/` | Spatial join, buffer, clip, curated layers |
| `docs/09_validation/` | Row counts, keys, domains, spatial validity |
| `docs/10_export/` | CSV, Parquet, GeoParquet, GeoJSON, delivery |
| `docs/11_performance/` | Pushdown, memory, `EXPLAIN ANALYZE` |

Published via **MkDocs** — Markdown sources, consistent headings, cross-links between overview and task guides.

## Notebooks (`notebooks/`)

Notebooks are the **primary working interface**.

| Notebook | Template ID | Workflow focus |
|----------|-------------|----------------|
| `00_eda_base.ipynb` | EDA-BASE | Profile `raw`, `staging`, or `curated` tables |
| `01_etl_base.ipynb` | ETL-BASE | End-to-end `source` → `raw` → `staging` → `curated` → `output` |
| `02_spatial_eda_base.ipynb` | SPATIAL-EDA-BASE | Spatial profiling and geometry QA |
| `03_validation_base.ipynb` | VALIDATION-BASE | VAL-001–VAL-009 pass/fail suite |
| `04_export_base.ipynb` | EXPORT-BASE | `curated` → `output` (Parquet, CSV) |

`notebooks/templates/` will hold blank scaffolds and single-task starters (connect, ingest CSV, ingest Shapefile, etc.) as they are added.

### Typical notebook flow

```text
Setup → Ingest (source → raw) → Stage → Validate → Curate → Export
```

Keep SQL in `%%sql` or `con.execute("""...""")` cells so non-Python users can read and run the same logic.

## SQL and Python Templates (`sql/`, `python/`)

Promote stable notebook SQL into reusable files:

```text
sql/
  setup/              # Extensions
  ingestion/          # Per-format ingest
  cleaning/           # Staging transforms
  transformation/     # Joins, aggregates, windows
  spatial/            # Ingest, spatial EDA, spatial transforms
  validation/         # Row counts, keys, referential integrity
  export/             # COPY patterns
python/
  path_helpers.py     # data/source, raw, staging, curated, output paths
  duckdb_helpers.py   # Connect, load extensions, run SQL files
  eda_helpers.py      # Preview, null profile, summaries
  spatial_helpers.py  # Geometry QA SQL generators
  validation_helpers.py
```

Run from a notebook:

```python
from pathlib import Path
sql = Path("sql/setup/load_common_extensions.sql").read_text()
con.execute(sql)
```

## Worked Examples (`examples/`)

| Example | Path | Workflow |
|---------|------|----------|
| CSV to Parquet | `examples/csv_to_parquet/` | `source` → `raw` → `staging` → `output` |
| Shapefile to GeoParquet | `examples/shapefile_to_geoparquet/` | `source` → `raw` → `curated` → `output` |

## Data Directories (`data/`)

On-disk folders mirror the workflow convention:

```text
source → raw → staging → curated → output
```

| Folder | Contents |
|--------|----------|
| `data/source/` | Optional local copies of vendor or portal downloads |
| `data/raw/` | File snapshots matching `raw.*` tables (optional) |
| `data/staging/` | Intermediate files if you materialize outside DuckDB |
| `data/curated/` | Curated Parquet/GeoParquet archives (optional) |
| `data/output/` | **Published** CSV, Parquet, GeoJSON, GeoParquet |

DuckDB schemas (`raw`, `staging`, `curated`) are the main working copies; `data/output/` is what you hand to consumers.

Example layout after a spatial run:

```text
data/
  source/
    city_parcels.zip          # optional local mirror
  output/
    parcels_by_zone.parquet
    parcels_by_zone.geojson
```

## DuckDB Database File

Most notebooks use a project-local database:

```python
import duckdb
con = duckdb.connect("work.duckdb")  # or data/work.duckdb
```

Schemas inside the file:

```sql
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;
```

Add `work.duckdb` and large files under `data/` to `.gitignore`; commit notebooks, SQL templates, and small sample data only.

## Workflow Layers vs. Folders vs. Schemas

| Layer | External | DuckDB schema | Disk (typical) |
|-------|----------|---------------|----------------|
| source | URL, API, vendor | — | `data/source/` (optional) |
| raw | — | `raw` | `data/raw/` (optional) |
| staging | — | `staging` | `data/staging/` (optional) |
| curated | — | `curated` | `data/curated/` (optional) |
| output | — | — | `data/output/` **required for exports** |

## Real-World Dataset Practice

Examples intentionally use **online datasets** (open data portals, public CSV/GeoJSON URLs) so you can re-run notebooks without proprietary files. When a source is large or unstable, mirror it once into `data/source/` and point ingest at the local path.

## Minimal Starter Checklist

1. Clone repo; `uv sync` or install `duckdb` + `ipykernel`
2. Open `notebooks/01_etl_base.ipynb`
3. Confirm `work.duckdb` and schemas `raw`, `staging`, `curated`
4. Run ingest from a public URL into `raw`
5. Write first `staging` table and export to `data/output/`

## Related Pages

- [Workflow layers](workflow_layers.md) — what each layer does
- [Naming conventions](naming_conventions.md) — table and file names
- [Template index](../template_index.md) — catalog of SQL and notebook templates
