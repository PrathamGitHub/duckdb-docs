# Project Structure

This repository is organized for **notebook-first** workflows: explore in Jupyter, reuse SQL templates, and keep data layers predictable on disk and in DuckDB.

## Top-Level Layout

```text
duckeb-docs/
  README.md                 # Repository entry point
  pyproject.toml            # Python deps (duckdb, ipykernel)
  docs/                     # MkDocs documentation (you are here)
    00_overview/            # Concepts and conventions
    01-setup.md             # (planned) Environment and connection
    02-ingestion.md         # (planned) Source → raw patterns
    ...
  notebooks/                # Runnable workflow notebooks
    00_quickstart.ipynb
    01_ingest_online_data.ipynb
    02_staging_transformations.ipynb
    03_validation_checks.ipynb
    04_exports.ipynb
    05_spatial_workflows.ipynb
    templates/              # Copy-paste notebook starters
  templates/
    sql/                    # Layered SQL snippets by task
    python/                 # Connection, paths, export helpers
  data/                     # File-based layers (gitignored large files)
    source/                 # Optional local mirrors of external files
    raw/
    staging/
    curated/
    output/                 # Published deliverables
  duckdb-workflow-docs/     # Template catalog index
```

Not every project needs every folder on day one. Start with `notebooks/`, one `work.duckdb`, and `data/output/`; add `templates/` as patterns stabilize.

## Documentation (`docs/`)

| Path | Purpose |
|------|---------|
| `docs/00_overview/` | Concepts: DuckDB fit, layers, naming, structure |
| `docs/01-setup.md` | Extensions, connections, schemas |
| `docs/02-ingestion.md` | CSV, Parquet, JSON, remote URLs |
| `docs/03-staging.md` | Cleaning and typing |
| `docs/04-validation.md` | Quality checks before export |
| `docs/05-exports.md` | Parquet, CSV, GeoParquet, GeoJSON |
| `docs/06-spatial.md` | Shapefile, GeoParquet, GeoJSON, FileGDB |

Published via **MkDocs** — Markdown sources, consistent headings, cross-links between overview and task guides.

## Notebooks (`notebooks/`)

Notebooks are the **primary working interface**.

| Notebook | Workflow focus |
|----------|----------------|
| `00_quickstart.ipynb` | Mini end-to-end: ingest → validate → export |
| `01_ingest_online_data.ipynb` | Real-world URLs into `raw` |
| `02_staging_transformations.ipynb` | `raw` → `staging` |
| `03_validation_checks.ipynb` | Pass/fail checks |
| `04_exports.ipynb` | `curated` → `output` |
| `05_spatial_workflows.ipynb` | Spatial ingest through export |

`notebooks/templates/` holds blank scaffolds and single-task starters (connect, ingest CSV, ingest Shapefile, etc.). Copy a template into your project before customizing.

### Typical notebook flow

```text
Setup → Ingest (source → raw) → Stage → Validate → Curate → Export
```

Keep SQL in `%%sql` or `con.execute("""...""")` cells so non-Python users can read and run the same logic.

## SQL and Python Templates (`templates/`)

Promote stable notebook SQL into reusable files:

```text
templates/
  sql/
    setup/              # Extensions, create schemas
    ingestion/          # Per-format ingest
    cleaning/           # Staging transforms
    transformation/     # Joins, aggregates, windows
    spatial_transform/  # Buffers, spatial joins, clip
    validation/         # Row counts, keys, spatial validity
    export/             # COPY patterns
  python/
    connection.py       # DuckDB connection factory
    paths.py            # data/raw, staging, curated, output paths
    extensions.py       # Load httpfs, spatial, json
    export_helpers.py   # Named exports to output/
```

Run from a notebook:

```python
from pathlib import Path
sql = Path("templates/sql/setup/create_layer_schemas.sql").read_text()
con.execute(sql)
```

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
2. Open `notebooks/00_quickstart.ipynb`
3. Confirm `work.duckdb` and schemas `raw`, `staging`, `curated`
4. Run ingest from a public URL into `raw`
5. Write first `staging` table and export to `data/output/`

## Related Pages

- [Workflow layers](workflow_layers.md) — what each layer does
- [Naming conventions](naming_conventions.md) — table and file names
- [Template index](../../duckdb-workflow-docs/template_index.md) — catalog of SQL and notebook templates
