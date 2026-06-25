# Large File Patterns

Handle files that do not fit comfortably in interactive memory using staging Parquet, selective materialization, and pushdown-friendly reads.

## Purpose

Provide repeatable patterns for large CSV, Parquet, and spatial files in the `source → raw → staging → curated → output` workflow without loading entire datasets into every notebook cell.

## Why it matters

Real-world `source` files — vendor CSV dumps, national lineitem samples, county parcel shapefiles — can be hundreds of MB to many GB. Reading them repeatedly as raw text does not scale. The highest-leverage pattern in this repository is: **ingest once to `raw`, convert to filtered staging Parquet, query Parquet with column selection and early filters**.

## Recommended pattern

```text
source (large CSV)
  → raw.raw_*           (full snapshot, once)
  → data/staging/*.parquet  (typed, filtered, column-pruned)
  → staging.stg_*       (view or table over Parquet)
  → curated / output
```

1. Snapshot `source` to `raw` once per delivery.
2. Convert `raw` → staging Parquet with `COPY` and a selective `SELECT`.
3. Use `read_parquet` with explicit columns and `WHERE` for all repeated work.
4. Validate row counts between `raw` and staging before `curated`.
5. Set `memory_limit` and `temp_directory` for joins on large staging tables.

## Anti-pattern

- Re-running `read_csv_auto` on a 2 GB URL in every notebook section.
- `CREATE TABLE staging.stg AS SELECT * FROM raw.raw_huge` with no filter.
- Joining two full spatial layers with no study-area bounding box.
- Keeping only a DuckDB table inside `work.duckdb` with no external Parquet copy — file growth and lock contention.

## SQL example

### Step 1 — source → raw (online CSV)

```sql
INSTALL httpfs;
LOAD httpfs;

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_lineitem_csv AS
SELECT *
FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv');
```

### Step 2 — raw → staging Parquet (convert once)

```sql
COPY (
  SELECT
    l_orderkey,
    l_linenumber,
    CAST(l_shipdate AS DATE) AS ship_date,
    l_extendedprice AS extended_price,
    l_quantity AS quantity
  FROM raw.raw_lineitem_csv
  WHERE l_shipdate IS NOT NULL
    AND l_shipdate >= DATE '1995-01-01'
) TO 'data/staging/stg_lineitem.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
```

### Step 3 — repeated analytics on staging Parquet

```sql
CREATE OR REPLACE VIEW staging.stg_lineitem AS
SELECT * FROM read_parquet('data/staging/stg_lineitem.parquet');

SELECT
  DATE_TRUNC('year', ship_date) AS ship_year,
  COUNT(*) AS lines,
  SUM(extended_price) AS revenue
FROM staging.stg_lineitem
GROUP BY 1
ORDER BY 1;
```

### Step 4 — verify reconciliation

```sql
SELECT
  (SELECT COUNT(*) FROM raw.raw_lineitem_csv WHERE l_shipdate IS NOT NULL) AS raw_n,
  (SELECT COUNT(*) FROM staging.stg_lineitem) AS staging_n,
  (SELECT SUM(l_extendedprice) FROM raw.raw_lineitem_csv WHERE l_shipdate >= DATE '1995-01-01') AS raw_sum,
  (SELECT SUM(extended_price) FROM staging.stg_lineitem) AS staging_sum;
```

### Inspect plan on large read

```sql
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(extended_price)
FROM read_parquet('data/staging/stg_lineitem.parquet')
WHERE ship_date >= DATE '1996-01-01';
```

## Notebook usage

```python
from pathlib import Path

LINEITEM_CSV = "https://blobs.duckdb.org/data/lineitem.csv"
STAGING_PATH = STAGING_DIR / "stg_lineitem.parquet"

con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("SET memory_limit = '4GB';")
con.execute(f"SET temp_directory = '{(DATA_DIR / '.duckdb_temp').as_posix()}';")

# --- source → raw (run when source changes) ---
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_lineitem_csv AS
SELECT * FROM read_csv_auto('{LINEITEM_CSV}');
""")

# --- raw → staging Parquet (run after raw ingest) ---
if not STAGING_PATH.exists():
    con.execute(f"""
    COPY (
      SELECT
        l_orderkey,
        CAST(l_shipdate AS DATE) AS ship_date,
        l_extendedprice AS extended_price
      FROM raw.raw_lineitem_csv
      WHERE l_shipdate >= DATE '1995-01-01'
    ) TO '{STAGING_PATH.as_posix()}'
    (FORMAT PARQUET, COMPRESSION ZSTD);
    """)

# --- downstream cells use Parquet only ---
con.sql(f"""
SELECT ship_month, SUM(extended_price) AS revenue
FROM (
  SELECT DATE_TRUNC('month', ship_date) AS ship_month, extended_price
  FROM read_parquet('{STAGING_PATH.as_posix()}')
  WHERE ship_date >= DATE '1996-01-01'
)
GROUP BY 1
ORDER BY 1
""").df()
```

## Common variations

### Skip `raw` table — write Parquet directly from `source` (prototyping only)

```sql
COPY (
  SELECT l_orderkey, CAST(l_shipdate AS DATE) AS ship_date, l_extendedprice
  FROM read_csv_auto('https://blobs.duckdb.org/data/lineitem.csv')
  WHERE l_shipdate >= DATE '1995-01-01'
) TO 'data/staging/stg_lineitem.parquet'
(FORMAT PARQUET);
```

Prefer full `raw` snapshot for production pipelines.

### Large remote Parquet — cache to `data/raw/` once

```python
import urllib.request

url = "https://blobs.duckdb.org/data/lineitem.parquet"
dest = RAW_DIR / "lineitem.parquet"
if not dest.exists():
    urllib.request.urlretrieve(url, dest)
```

### Folder of Parquet files

```sql
CREATE VIEW staging.stg_events AS
SELECT *
FROM read_parquet('data/staging/events/**/*.parquet', hive_partitioning = true);
```

### Spatial large file — bbox at read, then staging GeoParquet

```sql
INSTALL spatial;
LOAD spatial;

COPY (
  SELECT name, geom
  FROM ST_Read('data/raw/ne_110m_admin_0_countries.shp')
  WHERE ST_Intersects(geom, ST_MakeEnvelope(-130, 24, -65, 50))
) TO 'data/staging/stg_countries_us_bbox.parquet'
(FORMAT PARQUET);
```

### Sample during development

```sql
CREATE TABLE staging.stg_lineitem_sample AS
SELECT *
FROM read_parquet('data/staging/stg_lineitem.parquet')
USING SAMPLE 1%;
```

## Practical notes

- **Idempotent staging:** Check `Path.exists()` or row counts before re-running expensive `COPY` steps.
- **Compression:** ZSTD on staging Parquet typically shrinks CSV by 5–10× for numeric/tabular data.
- **Partitioning:** For very large curated outputs, partition by `year` or `region` before repeated filtered reads.
- **Development vs production:** Use `LIMIT`, `USING SAMPLE`, or bbox filters while writing SQL; remove only after validation.
- **Disk budget:** `raw` in `work.duckdb` + staging Parquet + `output` exports — plan disk upfront.

## Known limitations

- `COPY` from huge `raw` tables still requires one full pass — schedule during ingest windows.
- CSV `read_csv_auto` type inference on very large files can be slow — specify columns and types when schema is known.
- Spatial `ST_Read` on huge shapefiles may not support all pushdown options — use bbox filters where available.
- Sample tables are not valid for final validation — reconcile against full `raw` before delivery.
- Git should not store large `data/` artifacts — use `.gitignore` and document download steps.

## Related Pages

- [Parquet best practices](parquet_best_practices.md)
- [Memory management](memory_management.md)
- [Predicate pushdown](predicate_pushdown.md)
- [CSV ingestion](../02_ingestion/csv.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB CSV](https://duckdb.org/docs/current/data/csv/overview.html) · [DuckDB Parquet](https://duckdb.org/docs/current/data/parquet/overview.html)
