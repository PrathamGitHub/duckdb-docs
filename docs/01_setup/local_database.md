# Local Database (Persistent `.duckdb`)

Use a project-local `.duckdb` file when you want tables, views, and schemas to survive across notebook sessions. This is the default connection pattern for layered workflows in this repository.

## Purpose

Create and reuse a **persistent DuckDB database file** on disk. The file holds schemas (`raw`, `staging`, `curated`), ingested tables, and intermediate results so you can stop a notebook, reopen it later, and continue from the same state.

## When to Use

- Building repeatable **source → raw → staging → curated → output** pipelines
- Ingesting real-world online datasets once and re-running transforms without re-downloading
- Spatial workflows where `raw.raw_parcels_shp` or similar tables are expensive to reload
- Sharing a single database file with teammates for review (small to medium projects)
- Prototyping ETL before promoting logic to SQL templates or scripts

Prefer an [in-memory database](in_memory_database.md) for quick one-off queries or throwaway exploration.

## Required Code

```python
import duckdb
from pathlib import Path

# Project root and database path (see project_paths.md)
ROOT = Path.cwd()
DB_PATH = ROOT / "work.duckdb"

# Open or create the persistent database file
con = duckdb.connect(str(DB_PATH))

# Layer schemas for the workflow convention
con.execute("CREATE SCHEMA IF NOT EXISTS raw;")
con.execute("CREATE SCHEMA IF NOT EXISTS staging;")
con.execute("CREATE SCHEMA IF NOT EXISTS curated;")
```

```sql
-- Confirm connection and list schemas
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('raw', 'staging', 'curated')
ORDER BY schema_name;
```

## Example

Ingest a public CSV into `raw`, then query from a later notebook cell or session:

```python
import duckdb
from pathlib import Path

con = duckdb.connect(str(Path.cwd() / "work.duckdb"))
con.execute("CREATE SCHEMA IF NOT EXISTS raw;")
```

```sql
INSTALL httpfs;
LOAD httpfs;

CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);

SELECT country_name, year, value AS population
FROM raw.raw_population_csv
WHERE year = '2020'
ORDER BY population DESC
LIMIT 5;
```

Close the connection when you are done with a long-running script (notebooks often keep the connection open for the session):

```python
con.close()
```

## Common Variations

### Database under `data/`

Colocate the file with on-disk layers:

```python
DB_PATH = Path.cwd() / "data" / "work.duckdb"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
con = duckdb.connect(str(DB_PATH))
```

### Read-only connection

Open an existing file without accidental writes:

```python
con = duckdb.connect(str(DB_PATH), read_only=True)
```

### SQL-only check of database file location

```sql
SELECT current_database();
```

### Reattach after changing working directory in a notebook

Always build `DB_PATH` from a stable [project root](project_paths.md), not a relative path that depends on where Jupyter was started.

```python
from pathlib import Path

def find_project_root(start: Path | None = None) -> Path:
    start = start or Path.cwd()
    for path in [start, *start.parents]:
        if (path / "pyproject.toml").exists():
            return path
    return start

ROOT = find_project_root()
con = duckdb.connect(str(ROOT / "work.duckdb"))
```

## Notes or Limitations

- The `.duckdb` file is a **single-file database**. Back it up by copying the file; add `work.duckdb` and large `data/` files to `.gitignore`.
- Only one writer should modify the file at a time. Concurrent writes from multiple processes can cause locking errors.
- Very large projects may outgrow one file; export curated layers to Parquet in `data/output/` and archive or split databases by domain.
- `duckdb.connect()` with no path opens an in-memory database — see [in_memory_database.md](in_memory_database.md).
- Load extensions ([extensions.md](extensions.md)) in each new process; extension install state may persist in the file, but `LOAD` is still required per session.

## Related Pages

- [In-memory database](in_memory_database.md)
- [Project paths](project_paths.md)
- [Extensions](extensions.md)
- [Notebook setup cell](notebook_setup_cell.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB Python DB API](https://duckdb.org/docs/stable/clients/python/dbapi.html)
