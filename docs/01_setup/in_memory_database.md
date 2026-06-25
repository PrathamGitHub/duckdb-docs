# In-Memory Database

An in-memory DuckDB session runs entirely in RAM. Nothing is written to a `.duckdb` file unless you explicitly export or attach a persistent database.

## Purpose

Get a fast, isolated SQL engine for **exploration, prototyping, and tests** without creating or modifying `work.duckdb`. Ideal for trying a query, testing a function, or validating logic before committing data to a layered pipeline.

## When to Use

- Quick EDA on a CSV, Parquet file, or remote URL
- Unit-style checks in a notebook before ingesting into `raw`
- Teaching or demos where you want a clean slate every run
- CI or automated tests that must not touch project files
- Federating external sources temporarily (HTTP, Postgres, SQLite) without persisting

Use a [persistent local database](local_database.md) when you need tables to survive across sessions or when building `raw` → `staging` → `curated` workflows.

## Required Code

```python
import duckdb

# Default: in-memory connection (no file on disk)
con = duckdb.connect()

# Equivalent explicit form
con = duckdb.connect(database=":memory:")
```

```sql
-- Verify you are not using a named file database
SELECT current_database();
```

## Example

Query a public dataset without creating schemas or a `.duckdb` file:

```python
import duckdb

con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs;")
```

```sql
SELECT country_name, year, CAST(value AS BIGINT) AS population
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
)
WHERE year = '2020'
ORDER BY population DESC
LIMIT 10;
```

Spatial smoke test in memory:

```python
con.execute("INSTALL spatial; LOAD spatial;")
```

```sql
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
LIMIT 5;
```

## Common Variations

### Default connection vs. explicit `:memory:`

Both create a new in-memory database:

```python
con = duckdb.connect()
con2 = duckdb.connect(":memory:")
```

Each call to `duckdb.connect()` without a file path starts a **separate** in-memory instance.

### Attach a persistent file alongside memory

Query an on-disk `work.duckdb` from an in-memory session:

```python
import duckdb
from pathlib import Path

con = duckdb.connect()
con.execute(f"ATTACH '{Path.cwd() / 'work.duckdb'}' AS disk (READ_ONLY);")
```

```sql
SELECT COUNT(*) AS n
FROM disk.staging.stg_population;
```

### Copy in-memory results to a file database

Promote a successful experiment into the project database:

```python
import duckdb
from pathlib import Path

mem = duckdb.connect()
disk = duckdb.connect(str(Path.cwd() / "work.duckdb"))

mem.execute("CREATE TABLE demo AS SELECT 1 AS id, 'test' AS label;")
disk.execute("CREATE SCHEMA IF NOT EXISTS staging;")
disk.execute("CREATE TABLE staging.stg_demo AS SELECT * FROM mem.demo;")

mem.close()
disk.close()
```

### Context manager (scripts)

```python
import duckdb

with duckdb.connect() as con:
    print(con.execute("SELECT 42 AS answer").fetchone())
```

## Notes or Limitations

- **Data is lost** when the connection closes and no file was attached — export anything you need with `COPY ... TO 'data/output/...'`.
- In-memory databases still respect available RAM; loading huge spatial files or wide Parquet datasets can exhaust memory on a laptop.
- Extensions must be `INSTALL`ed and `LOAD`ed per connection; see [extensions.md](extensions.md).
- Jupyter kernels keep the connection alive until restart — an "in-memory" notebook can still accumulate tables across cell reruns within one session.
- For reproducible pipelines and real-world dataset practice, prefer persisting ingested `raw` tables in [local_database.md](local_database.md).

## Related Pages

- [Local database](local_database.md)
- [Notebook setup cell](notebook_setup_cell.md)
- [Extensions](extensions.md)

Official reference: [DuckDB Python DB API](https://duckdb.org/docs/stable/clients/python/dbapi.html)
