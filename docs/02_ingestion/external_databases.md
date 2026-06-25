# External Databases

Ingest or federate data from PostgreSQL, SQLite, and other attached databases into DuckDB's `raw` layer using scanner extensions.

## Purpose

Copy tables from operational systems into `raw_<dataset_name>` snapshots for notebook analytics, or query remote databases in place during exploration before committing to a full ingest.

## When to Use

- Legacy SQLite `.db` files on disk (`data/source/legacy.db`)
- Read-only PostgreSQL replicas for analytics extracts
- Joining warehouse dimensions with local files in one DuckDB session
- Prototyping before a formal CDC or ETL pipeline

For production repeatability, prefer **copying into `raw` tables** over live federation — you get an auditable snapshot aligned with `source → raw → staging`.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Extensions | `postgres` and/or `sqlite` — `INSTALL` + `LOAD` per session |
| Access | Connection strings, VPN, or local file path to `.db` |
| Permissions | Read-only user for federation; write not required for ingest |
| Layer | Remote DB is **source**; local snapshot in schema `raw` |
| Naming | `raw_<entity>_<system>` — e.g. `raw.raw_customers_pg`, `raw.raw_orders_sqlite` |
| Secrets | Use environment variables — never commit passwords |

## Basic DuckDB SQL

### PostgreSQL scan

```sql
INSTALL postgres;
LOAD postgres;

SELECT *
FROM postgres_scan(
  'host=localhost port=5432 dbname=analytics user=reader password=secret',
  'public',
  'customers'
)
LIMIT 10;
```

### SQLite scan

```sql
INSTALL sqlite;
LOAD sqlite;

SELECT *
FROM sqlite_scan('data/source/legacy.db', 'orders')
LIMIT 10;
```

### Attach SQLite (query multiple tables)

```sql
ATTACH 'data/source/legacy.db' AS legacy (TYPE SQLITE);

SELECT o.order_id, c.name
FROM legacy.orders o
JOIN legacy.customers c ON o.customer_id = c.id
LIMIT 10;
```

## Create Raw View Pattern

Live federation — remote data can change between queries:

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_customers_pg AS
SELECT *
FROM postgres_scan(
  'host=localhost port=5432 dbname=analytics user=reader password=secret',
  'public',
  'customers'
);
```

```sql
CREATE OR REPLACE VIEW raw.raw_orders_sqlite AS
SELECT *
FROM sqlite_scan('data/source/legacy.db', 'orders');
```

## Create Raw Table Pattern

Recommended workflow snapshot:

```sql
CREATE OR REPLACE TABLE raw.raw_customers_pg AS
SELECT *
FROM postgres_scan(
  'host=localhost port=5432 dbname=analytics user=reader password=secret',
  'public',
  'customers'
);
```

```sql
CREATE OR REPLACE TABLE raw.raw_orders_sqlite AS
SELECT *
FROM sqlite_scan('data/source/legacy.db', 'orders');
```

Add ingest metadata:

```sql
CREATE OR REPLACE TABLE raw.raw_events_pg AS
SELECT
  *,
  current_timestamp AS ingested_at,
  'public.events' AS source_relation
FROM postgres_scan(
  'host=localhost port=5432 dbname=analytics user=reader password=secret',
  'public',
  'events'
);
```

## Notebook Usage Example

Use environment variables for credentials:

```python
import os

pg_conn = os.environ.get(
    "DUCKEB_PG_CONN",
    "host=localhost port=5432 dbname=analytics user=reader password=changeme",
)

con.execute("INSTALL postgres; LOAD postgres;")

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_customers_pg AS
SELECT * FROM postgres_scan('{pg_conn}', 'public', 'customers');
""")

con.sql("SELECT COUNT(*) AS n FROM raw.raw_customers_pg").df()
```

SQLite practice without a remote server — ship a sample `.db` under `data/source/`:

```python
import sqlite3

sqlite_path = SOURCE_DIR / "practice.db"
if not sqlite_path.exists():
    db = sqlite3.connect(sqlite_path)
    db.execute("CREATE TABLE orders (order_id TEXT, customer_id TEXT, amount REAL)")
    db.executemany(
        "INSERT INTO orders VALUES (?, ?, ?)",
        [("o1", "c1", 10.0), ("o2", "c2", 25.5)],
    )
    db.commit()
    db.close()

con.execute("INSTALL sqlite; LOAD sqlite;")
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_orders_sqlite AS
SELECT * FROM sqlite_scan('{sqlite_path.as_posix()}', 'orders');
""")
```

## Common Variations

### Filter at ingest (still minimal — heavy logic belongs in `staging`)

```sql
CREATE OR REPLACE TABLE raw.raw_orders_pg AS
SELECT *
FROM postgres_scan('{{ conn }}', 'public', 'orders')
WHERE order_date >= DATE '2024-01-01';
```

### Attach Postgres

```sql
INSTALL postgres;
LOAD postgres;

ATTACH 'dbname=analytics host=localhost user=reader password=secret'
  AS pg (TYPE POSTGRES);

SELECT * FROM pg.public.customers LIMIT 10;
```

### Multiple tables from one SQLite file

```sql
CREATE OR REPLACE TABLE raw.raw_customers_sqlite AS
SELECT * FROM sqlite_scan('data/source/legacy.db', 'customers');

CREATE OR REPLACE TABLE raw.raw_orders_sqlite AS
SELECT * FROM sqlite_scan('data/source/legacy.db', 'orders');
```

### Spatial via Postgres PostGIS (federation)

When geometry lives in Postgres, ingest as WKB/WKT and convert in `staging`:

```sql
CREATE OR REPLACE TABLE staging.stg_sites AS
SELECT
  site_id,
  ST_GeomFromWKB(geom_wkb) AS geom
FROM raw.raw_sites_pg;
```

(Exact function depends on how geometry is stored — inspect `raw` first.)

### Export `raw` back to file for offline sharing

```sql
COPY (SELECT * FROM raw.raw_orders_sqlite)
TO 'data/raw/orders_snapshot.parquet'
(FORMAT PARQUET);
```

## Validation Checks After Ingestion

```sql
-- Row count vs source (run equivalent COUNT on source when possible)
SELECT COUNT(*) AS row_count FROM raw.raw_orders_sqlite;

-- Schema
DESCRIBE raw.raw_customers_pg;

-- Null keys
SELECT COUNT(*) AS null_customer_id
FROM raw.raw_customers_pg
WHERE customer_id IS NULL;

-- Duplicates
SELECT customer_id, COUNT(*) AS n
FROM raw.raw_customers_pg
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Ingest timestamp present (if captured)
SELECT MAX(ingested_at) AS last_ingest FROM raw.raw_events_pg;

-- Compare SQLite snapshot to live file
SELECT COUNT(*) FROM sqlite_scan('data/source/legacy.db', 'orders');
```

## Performance Notes

- **Copy to `raw` tables** once per pipeline run — faster than repeated `postgres_scan` in every cell.
- Pushdown filters in `postgres_scan` reduce data moved over the network when you must filter at ingest.
- SQLite file on local SSD is fast; network-mounted `.db` files are slow — copy locally first.
- Wide tables — select columns explicitly when you know the subset needed for `staging`.
- Large Postgres extracts may need chunked ingest by date key — multiple `raw` loads or `WHERE` slices.

## Known Limitations

- Federation requires live connectivity — snapshots insulate you from downtime.
- Postgres types may not map 1:1 (arrays, JSONB, custom types) — inspect `DESCRIBE` and cast in `staging`.
- Write-back to source databases is out of scope for this repo's ingest patterns.
- Connection strings in notebooks are a security risk — use `DUCKEB_PG_CONN` env vars.
- PostGIS geometry may need special handling — test a small `LIMIT` ingest first.
- DuckDB extension names: use `postgres` and `sqlite` in DuckDB 1.x (see [extensions](../01_setup/extensions.md)).

## Related Pages

- [Extensions](../01_setup/extensions.md)
- [Notebook setup cell](../01_setup/notebook_setup_cell.md)
- [Remote files (HTTP / S3)](remote_files_http_s3.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB PostgreSQL extension](https://duckdb.org/docs/current/extensions/postgres.html), [SQLite extension](https://duckdb.org/docs/current/extensions/sqlite.html)
