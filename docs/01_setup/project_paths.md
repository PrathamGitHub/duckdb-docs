# Project Paths

Use `pathlib` to define stable paths for data layers, the DuckDB file, and exports. Notebooks and scripts should resolve paths from a **project root**, not from wherever the shell or Jupyter server happened to start.

## Purpose

Centralize folder locations for the workflow convention:

```text
source → raw → staging → curated → output
```

Consistent paths make ingest SQL, `COPY` exports, and spatial file reads work the same in every notebook and template.

## When to Use

- Every notebook that reads or writes under `data/`
- SQL that uses absolute or relative file paths (`read_csv_auto`, `ST_Read`, `COPY ... TO`)
- Promoting notebook logic into `templates/python/paths.py`
- Switching between local files and `data/source/` mirrors of online datasets

## Required Code

```python
from pathlib import Path

def find_project_root(start: Path | None = None) -> Path:
    """Walk up from cwd until pyproject.toml is found."""
    start = start or Path.cwd()
    for path in [start, *start.parents]:
        if (path / "pyproject.toml").exists():
            return path
    return start

ROOT = find_project_root()

# Workflow folders on disk
DATA_DIR = ROOT / "data"
SOURCE_DIR = DATA_DIR / "source"
RAW_DIR = DATA_DIR / "raw"
STAGING_DIR = DATA_DIR / "staging"
CURATED_DIR = DATA_DIR / "curated"
OUTPUT_DIR = DATA_DIR / "output"

# DuckDB database file (see local_database.md)
DB_PATH = ROOT / "work.duckdb"

# Ensure export and optional layer folders exist
for folder in (SOURCE_DIR, RAW_DIR, STAGING_DIR, CURATED_DIR, OUTPUT_DIR):
    folder.mkdir(parents=True, exist_ok=True)
```

## Example

Use paths in Python and pass string paths into SQL:

```python
import duckdb
from pathlib import Path

ROOT = find_project_root()
DB_PATH = ROOT / "work.duckdb"
OUTPUT_DIR = ROOT / "data" / "output"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(DB_PATH))
con.execute("CREATE SCHEMA IF NOT EXISTS curated;")
```

Ingest from a URL (source layer — no local folder required):

```sql
INSTALL httpfs;
LOAD httpfs;

CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

Export curated results to a pathlib-resolved path:

```python
export_path = OUTPUT_DIR / "population_top_2020.parquet"
con.execute(f"""
COPY (
  SELECT country_name, CAST(value AS DOUBLE) AS population
  FROM raw.raw_population_csv
  WHERE year = '2020'
  ORDER BY population DESC
  LIMIT 20
) TO '{export_path.as_posix()}' (FORMAT PARQUET);
""")
```

Mirror an unstable online file into `data/source/` before ingest:

```python
import urllib.request

url = "https://raw.githubusercontent.com/datasets/population/master/data/population.csv"
local_source = SOURCE_DIR / "population.csv"
if not local_source.exists():
    urllib.request.urlretrieve(url, local_source)
```

```sql
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto('{{ local_path }}');
```

Replace `{{ local_path }}` in a template, or in Python:

```python
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto('{local_source.as_posix()}');
""")
```

Spatial example — read Shapefile or GeoJSON from disk:

```python
geojson_path = SOURCE_DIR / "regions.geojson"
```

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_regions_geojson AS
SELECT *
FROM ST_Read('path/to/data/source/regions.geojson');
```

## Common Variations

### Notebook-only: cwd is project root

If you always launch Jupyter from the repository root:

```python
from pathlib import Path

ROOT = Path.cwd()
DATA_DIR = ROOT / "data"
OUTPUT_DIR = DATA_DIR / "output"
```

Prefer `find_project_root()` when cwd is unreliable.

### Database file under `data/`

```python
DB_PATH = DATA_DIR / "work.duckdb"
```

### Glob many files in a layer folder

```python
parquet_files = list(RAW_DIR.glob("*.parquet"))
```

```python
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT * FROM read_parquet({[p.as_posix() for p in parquet_files]!r});
""")
```

### Path helpers for SQL templates

```python
def sql_path(path: Path) -> str:
    """Return forward-slash path safe for DuckDB SQL strings."""
    return path.resolve().as_posix()
```

### Environment override for output location

```python
import os

OUTPUT_DIR = Path(os.environ.get("DUCKEB_OUTPUT_DIR", DATA_DIR / "output"))
```

## Notes or Limitations

- DuckDB SQL strings need **forward slashes** on all platforms; use `Path.as_posix()` when embedding paths.
- Escape or parameterize carefully — avoid building SQL from untrusted path input.
- Large downloads belong in `data/source/` or `data/raw/` and should be **gitignored**; commit notebooks and templates, not multi-GB mirrors.
- The on-disk folders are optional mirrors; primary layered tables live in DuckDB schemas `raw`, `staging`, and `curated`. See [workflow layers](../00_overview/workflow_layers.md).
- ESRI File Geodatabase (`.gdb`) paths are directories; pass the folder path to `ST_Read`, not a single file inside it.

## Related Pages

- [Local database](local_database.md)
- [Notebook setup cell](notebook_setup_cell.md)
- [Naming conventions](../00_overview/naming_conventions.md)
- [Project structure](../00_overview/project_structure.md)
