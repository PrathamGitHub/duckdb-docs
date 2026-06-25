# Notebook Setup Cell

Copy this pattern into the **first code cell** of every workflow notebook. It wires paths, opens the database, loads extensions, and creates layer schemas so later cells can focus on ingest and transforms.

## Purpose

Provide a single, repeatable bootstrap for notebook-first work: analysts, engineers, and GIS users get the same connection, folders, and schemas without duplicating setup in every notebook.

## When to Use

- Starting any notebook under `notebooks/` (quickstart, ingest, staging, spatial, exports)
- Copying a template from `notebooks/templates/`
- Before ingesting a real-world online dataset into `raw`
- Whenever you open a new Jupyter kernel (re-run this cell after restart)

Skip or slim down for throwaway EDA — use [in_memory_database.md](in_memory_database.md) with only `httpfs` instead.

## Required Code

Recommended first cell (adjust `EXTENSIONS` per notebook):

```python
from pathlib import Path

import duckdb

# --- Project paths ---
def find_project_root(start: Path | None = None) -> Path:
    start = start or Path.cwd()
    for path in [start, *start.parents]:
        if (path / "pyproject.toml").exists():
            return path
    return start

ROOT = find_project_root()
DATA_DIR = ROOT / "data"
SOURCE_DIR = DATA_DIR / "source"
OUTPUT_DIR = DATA_DIR / "output"
DB_PATH = ROOT / "work.duckdb"

for folder in (SOURCE_DIR, DATA_DIR / "raw", DATA_DIR / "staging", DATA_DIR / "curated", OUTPUT_DIR):
    folder.mkdir(parents=True, exist_ok=True)

# --- Connection ---
con = duckdb.connect(str(DB_PATH))

# --- Extensions (edit list per notebook) ---
EXTENSIONS = ["httpfs", "spatial", "json"]

for ext in EXTENSIONS:
    con.execute(f"INSTALL {ext};")
    con.execute(f"LOAD {ext};")

# --- Workflow schemas: source → raw → staging → curated → output ---
con.execute("CREATE SCHEMA IF NOT EXISTS raw;")
con.execute("CREATE SCHEMA IF NOT EXISTS staging;")
con.execute("CREATE SCHEMA IF NOT EXISTS curated;")

# --- Sanity check ---
print(f"Project root: {ROOT}")
print(f"Database:     {DB_PATH}")
print(con.execute("SELECT extension_name FROM duckdb_extensions() WHERE loaded").df())
```

Optional second cell — confirm schemas:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('raw', 'staging', 'curated')
ORDER BY schema_name;
```

## Example

Full quickstart: setup, ingest online CSV to `raw`, preview in SQL.

**Cell 1 — setup** (code above).

**Cell 2 — ingest (source → raw)**

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")
```

**Cell 3 — explore**

```python
con.sql("""
SELECT country_name, year, value AS population
FROM raw.raw_population_csv
WHERE year = '2020'
ORDER BY population DESC
LIMIT 10
""").df()
```

Or pure SQL in a `%%sql` cell (after registering `con` with `%sql con` or your Jupyter SQL magic):

```sql
SELECT country_name, year, value AS population
FROM raw.raw_population_csv
WHERE year = '2020'
ORDER BY population DESC
LIMIT 10;
```

**Cell 4 — spatial check (same session, `spatial` already loaded)**

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_regions_geojson AS
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")
con.sql("SELECT * FROM raw.raw_regions_geojson LIMIT 3").df()
```

## Common Variations

### Tabular-only notebook (no spatial)

```python
EXTENSIONS = ["httpfs", "json"]
```

### Ingest Excel or federate SQLite / Postgres

```python
EXTENSIONS = ["httpfs", "json", "excel"]           # spreadsheets
EXTENSIONS = ["httpfs", "sqlite"]                  # legacy .db
EXTENSIONS = ["httpfs", "postgres"]              # remote PG (use env for secrets)
```

### In-memory sandbox (no `work.duckdb`)

```python
con = duckdb.connect()
EXTENSIONS = ["httpfs"]
# Omit CREATE SCHEMA if you only need temp tables, or keep schemas for practice
```

### Read-only open of an existing database

```python
con = duckdb.connect(str(DB_PATH), read_only=True)
```

### Display SQL results as DataFrame (default in many notebooks)

```python
con.sql("SELECT COUNT(*) AS n FROM raw.raw_population_csv").df()
```

### Promote to a shared module later

When the same cell appears in many notebooks, extract paths and extension loading to `templates/python/paths.py` and `templates/python/extensions.py` — keep the notebook cell thin:

```python
# Future pattern (when templates exist)
# from templates.python.paths import ROOT, DB_PATH, OUTPUT_DIR
# from templates.python.extensions import connect_with_extensions
# con = connect_with_extensions(DB_PATH, ["httpfs", "spatial"])
```

## Notes or Limitations

- **Re-run cell 1 after every kernel restart** — otherwise `con` and loaded extensions are missing.
- Running setup twice in the same kernel is safe: `CREATE SCHEMA IF NOT EXISTS` and `INSTALL` are idempotent; `LOAD` is cheap.
- `find_project_root()` depends on `pyproject.toml` at the repository root; clone layout must match [project structure](../00_overview/project_structure.md).
- Add `excel`, `postgres`, or `sqlite` only when needed — fewer extensions mean faster startup and fewer dependency surprises.
- Close or avoid duplicating connections: one `con` per kernel is enough; opening many `duckdb.connect()` handles to the same file can cause lock contention.
- This cell does not install Python packages — ensure `duckdb` is available (`uv sync` per `pyproject.toml`).

## Related Pages

- [Local database](local_database.md)
- [In-memory database](in_memory_database.md)
- [Project paths](project_paths.md)
- [Extensions](extensions.md)
- [Workflow layers](../00_overview/workflow_layers.md)
