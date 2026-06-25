# Python Helpers

Reusable, notebook-friendly helpers for DuckDB workflows in this repository.  
They follow the **source → raw → staging → curated → output** convention and align with the SQL patterns in `docs/`.

## Modules

| Module | Purpose |
|--------|---------|
| `path_helpers.py` | Resolve project root and workflow folder paths |
| `duckdb_helpers.py` | Connect, load extensions, run SQL files, introspect tables |
| `eda_helpers.py` | Preview data, row counts, null/distinct profiles, summaries |
| `spatial_helpers.py` | Spatial extension setup and geometry QA SQL |
| `validation_helpers.py` | Required fields, keys, row counts, referential integrity |

## Quick Start

Add the `python/` folder to your import path from a notebook at the project root:

```python
import sys
from pathlib import Path

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "python"))

from duckdb_helpers import connect_database, load_common_extensions
from path_helpers import ensure_project_dirs

paths = ensure_project_dirs(ROOT)
con = connect_database()
load_common_extensions(con)
```

Or run notebooks with the project root on `PYTHONPATH`:

```bash
PYTHONPATH=python uv run jupyter notebook
```

## path_helpers.py

- **`find_project_root()`** — locate the repo by walking up to `pyproject.toml`
- **`get_default_project_paths()`** — return `data/source`, `data/raw`, `data/staging`, `data/curated`, `data/output`, and `work.duckdb`
- **`ensure_project_dirs()`** — create workflow folders when missing
- **`sql_path()`** — forward-slash paths for DuckDB SQL strings

## duckdb_helpers.py

- **`connect_database()`** — open `work.duckdb`, create `raw` / `staging` / `curated` schemas
- **`load_extension()`** / **`load_common_extensions()`** — install and load `httpfs`, `spatial`, `json`
- **`run_sql_file()`** — execute a `.sql` file from disk
- **`list_tables()`** / **`describe_table()`** — schema inspection as DuckDB relations (call `.df()` in notebooks when pandas is installed)

## eda_helpers.py

- **`preview_table()`** — first N rows
- **`row_count()`** — scalar count
- **`generate_null_profile_sql()`** / **`generate_distinct_profile_sql()`** — return SQL strings for unpivoted column profiles
- **`numeric_summary()`** — min, max, avg, stddev for numeric columns
- **`categorical_frequency()`** — top values with counts and percentages

Example:

```python
from eda_helpers import preview_table, generate_null_profile_sql

preview_table(con, "staging.stg_orders", limit=10)
sql = generate_null_profile_sql(
    "staging.stg_orders",
    ["order_id", "customer_id", "order_date", "amount"],
)
con.sql(sql).df()
```

## spatial_helpers.py

- **`load_spatial_extension()`** — install and load `spatial`
- **`spatial_extent_sql()`** — bounding box for a geometry column
- **`geometry_type_count_sql()`** — feature counts by geometry type
- **`null_geometry_check_sql()`** — null/empty geometry summary or row list
- **`invalid_geometry_check_sql()`** — invalid geometry summary or row list

Example:

```python
from spatial_helpers import load_spatial_extension, spatial_extent_sql

load_spatial_extension(con)
con.sql(spatial_extent_sql("raw.raw_parcels")).df()
```

## validation_helpers.py

All generators return SQL where **zero result rows means pass** (except row-count reconciliation, which reports status per layer).

- **`required_fields_null_check_sql()`** — rows with NULL required columns
- **`primary_key_uniqueness_sql()`** — duplicate key groups
- **`row_count_reconciliation_sql()`** — compare counts across layers
- **`referential_integrity_sql()`** — orphan foreign keys

Example:

```python
from validation_helpers import primary_key_uniqueness_sql

sql = primary_key_uniqueness_sql("staging.stg_orders", ["order_id"])
dupes = con.sql(sql).df()
assert dupes.empty, "Duplicate order_id values found"
```

## Dependencies

- `duckdb` — database connection and queries
- `pathlib` / `typing` — standard library only otherwise

Query helpers return DuckDB relations. In notebooks, call `.df()` on the result when pandas is available for display.

## Related Documentation

- [Project paths](../docs/01_setup/project_paths.md)
- [Extensions](../docs/01_setup/extensions.md)
- [Null profile](../docs/04_eda/null_profile.md)
- [Spatial extent](../docs/05_spatial_eda/spatial_extent.md)
- [Primary key uniqueness](../docs/09_validation/primary_key_uniqueness.md)
