# When to Use DuckDB

Use DuckDB when you want fast, local analytics with SQL—and you are willing to work **notebook-first**, layer by layer, from real sources to validated outputs.

This page is practical guidance, not a product comparison matrix. If the scenarios below sound like your work, DuckDB is likely a strong fit for this repository's templates.

## Strong Fits

### Exploratory analysis and EDA

You have CSV, Parquet, or JSON (local or online) and need to profile, filter, and aggregate quickly.

```sql
-- In a notebook cell: row counts and null check after ingest
SELECT
  COUNT(*) AS total_rows,
  COUNT(*) FILTER (WHERE population IS NULL) AS null_population
FROM staging.stg_population;
```

**Why DuckDB:** reads files directly; no import step; SQL is easy to share in notebook cells.

### Repeatable ETL on a laptop or CI runner

You ingest the same online sources on a schedule and want auditable layers: `source → raw → staging → curated → output`.

```python
# Notebook orchestration: run SQL file, then validate
con.execute(open("sql/cleaning/safe_casting.sql").read())
con.execute(open("sql/validation/row_count_reconciliation.sql").read())
```

**Why DuckDB:** one `.duckdb` file per project; schemas separate layers; `COPY` exports to Parquet/CSV.

### Spatial workflows without a separate GIS database

You work with Shapefile, GeoJSON, GeoParquet, or FileGDB and need joins, clips, buffers, or exports.

```sql
-- Point-in-polygon: assign each store to a census tract
CREATE OR REPLACE TABLE curated.cur_stores_by_tract AS
SELECT
  s.store_id,
  t.tract_id,
  s.geom
FROM staging.stg_stores AS s
JOIN staging.stg_tracts AS t
  ON ST_Intersects(s.geom, t.geom);
```

**Why DuckDB:** `spatial` extension reads common GIS formats and keeps geometry in SQL alongside attributes.

### Python + SQL mixed teams

Analysts prefer SQL; engineers prefer Python for I/O and automation. Notebooks host both.

```python
import duckdb
import pandas as pd

con = duckdb.connect("work.duckdb")
df = con.execute("SELECT * FROM curated.cur_sales_summary").df()
df.plot(kind="bar", x="region", y="revenue")
```

**Why DuckDB:** tight Python integration (`.df()`, `.arrow()`, parameter binding) without leaving the notebook.

### Federating files and light external databases

You need one query across Parquet on S3, a CSV URL, and a Postgres table snapshot.

```sql
INSTALL postgres_scanner;
LOAD postgres_scanner;

CREATE OR REPLACE TABLE raw.raw_orders_pg AS
SELECT * FROM postgres_scan('host=... dbname=...', 'public', 'orders');
```

**Why DuckDB:** extensions attach remote sources; you still land snapshots in `raw` for reproducibility.

## Good Fit with Caveats

| Scenario | Use DuckDB when… | Consider something else when… |
|----------|------------------|-------------------------------|
| Datasets up to tens–low hundreds of GB on one machine | Fits in RAM/disk; use partitioned Parquet | Data requires distributed cluster storage |
| Many concurrent writers | Single analyst or small team pipeline | Dozens of simultaneous write workloads |
| Long-running production serving | Batch prep and export to `output/` | Sub-second API queries at high QPS |
| Strict row-level security / multi-tenant OLTP | Curated exports per consumer | Fine-grained per-user live transactions |

## When to Reach for Another Tool

Use a different primary engine (while still optionally using DuckDB locally) if:

- **Data never fits one machine** and you already operate Spark, BigQuery, Snowflake, or similar at scale.
- **You need a shared always-on write-heavy application database** (user signups, inventory mutations)—DuckDB is analytical, not OLTP-first.
- **Your org mandates a central warehouse** for all published metrics—use DuckDB to build and validate `curated` models, then publish Parquet to the warehouse.
- **Desktop GIS editing** is the main task—QGIS/ArcGIS for editing; DuckDB for extract-transform-export and SQL spatial analysis.

## Decision Checklist

Answer yes to most of these → start with the notebooks in this repo:

1. Can I run the workflow on one machine (or CI) with local or attached files?
2. Is SQL (with optional Python) an acceptable interface for the team?
3. Do I need tabular **or** spatial ingest from files and URLs?
4. Will I benefit from explicit `raw` / `staging` / `curated` layers and validation before export?
5. Is the deliverable Parquet, CSV, GeoParquet, GeoJSON, or a dashboard fed from those files?

## Example Paths by Role

**Analyst — population trends from open data**

1. Notebook: ingest CSV from URL → `raw`
2. Clean types in `staging`
3. Aggregate to `curated.cur_population_by_region`
4. Export `output/population_by_region.parquet`

**GIS user — parcels and zoning**

1. Notebook: `ST_Read` Shapefile or FileGDB → `raw`
2. CRS check and repair in `staging`
3. Spatial join to `curated.cur_parcels_zoned`
4. Export `output/parcels_zoned.geoparquet`

**Data engineer — nightly validation gate**

1. Script/notebook runs ingest templates into `raw`
2. SQL templates build `staging` and `curated`
3. Validation suite must pass before `COPY` to `output/`
4. Failures logged in notebook for review

## Related Pages

- [What is DuckDB?](what_is_duckdb.md)
- [Workflow layers](workflow_layers.md)
- [Project structure](project_structure.md)
