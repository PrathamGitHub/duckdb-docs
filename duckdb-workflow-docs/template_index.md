# DuckDB Workflow Template Index

Central catalog of reusable DuckDB workflow templates for this repository.  
Templates follow the layered workflow convention:

```text
source → raw → staging → curated → output
```

Use this index to find a starting point by task, then copy the linked notebook, SQL file, or Python module into your project.  
Templates are designed for mixed audiences: analysts, data engineers, GIS users, Python users, and SQL users.

**Primary mode legend:** `Notebook` · `SQL` · `Python` · `Mixed`

---

## Setup

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SETUP-001 | Connect in-memory | Setup | Open a transient DuckDB session for exploration and unit-style checks | None | In-memory connection handle | Mixed | `notebooks/templates/00_setup_connect_memory.ipynb` | Read-only mode; attach additional in-memory DBs |
| SETUP-002 | Connect persistent database | Setup | Open or create a file-backed DuckDB database for repeatable pipelines | Database file path | Persistent `.duckdb` connection | Mixed | `notebooks/templates/00_setup_connect_persistent.ipynb` | Custom data directory; WAL settings; read-only attach |
| SETUP-003 | Configure project paths | Setup | Standardize `data/raw`, `data/staging`, `data/curated`, and `data/output` paths across notebooks | Project root | Path variables / config dict | Python | `templates/python/paths.py` | Environment-variable overrides; per-run timestamp folders |
| SETUP-004 | Load common extensions | Setup | Install and load `httpfs`, `json`, and other frequently used extensions | DuckDB connection | Extensions ready to query | SQL | `templates/sql/setup/load_common_extensions.sql` | Add `excel`, `postgres_scanner`, `sqlite_scanner` as needed |
| SETUP-005 | Load spatial extensions | Setup | Install and load `spatial` (and optional GDAL drivers) for geometry workflows | DuckDB connection | Spatial functions available | SQL | `templates/sql/setup/load_spatial_extensions.sql` | Enable PROJ/ GDAL options; configure S3 credentials for remote spatial reads |

---

## Ingestion

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| ING-001 | Ingest CSV | Ingestion | Load delimited text from local path or URL into the `raw` layer | `source` CSV / TSV | `raw.raw_*` table | Mixed | `notebooks/templates/01_ingest_csv.ipynb` | Custom delimiter; `read_csv` options; gzip URLs |
| ING-002 | Ingest Parquet | Ingestion | Load columnar Parquet files into `raw` | `source` Parquet file(s) | `raw.raw_*` table | Mixed | `notebooks/templates/01_ingest_parquet.ipynb` | Single file; multi-file `UNION ALL`; hive-style paths |
| ING-003 | Ingest Excel | Ingestion | Load spreadsheet sheets into `raw` | `source` `.xlsx` / `.xls` | `raw.raw_*` table | Mixed | `notebooks/templates/01_ingest_excel.ipynb` | Sheet name; header row offset; multiple sheets |
| ING-004 | Ingest JSON | Ingestion | Load JSON or NDJSON documents into `raw` | `source` JSON / NDJSON | `raw.raw_*` table | Mixed | `notebooks/templates/01_ingest_json.ipynb` | `read_json_auto`; nested column unnesting in staging |
| ING-005 | Ingest folder glob | Ingestion | Batch-read all matching files in a directory | `source` folder + glob pattern | `raw.raw_*` table | SQL | `templates/sql/ingestion/ingest_folder_glob.sql` | Recursive glob; filename metadata column; file-type mix guard |
| ING-006 | Ingest partitioned Parquet | Ingestion | Read hive-partitioned Parquet datasets | `source` partitioned Parquet tree | `raw.raw_*` table | SQL | `templates/sql/ingestion/ingest_partitioned_parquet.sql` | Partition pruning; register as view vs materialize |
| ING-007 | Ingest remote HTTP / S3 | Ingestion | Pull remote files via `httpfs` without local download | `source` HTTP / S3 URL | `raw.raw_*` table | Mixed | `notebooks/templates/01_ingest_remote_http_s3.ipynb` | Public URLs; signed S3; set `s3_region` / credentials |
| ING-008 | Ingest external database | Ingestion | Federate or snapshot tables from Postgres, SQLite, or similar | `source` external DB | `raw.raw_*` table | Mixed | `notebooks/templates/01_ingest_external_db.ipynb` | `postgres_scanner` attach; incremental watermark copy |

---

## Spatial Ingestion

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SING-001 | Ingest Shapefile | Spatial Ingestion | Load ESRI Shapefile into `raw` with geometry column | `source` `.shp` (+ sidecar files) | `raw.raw_*` with `GEOMETRY` | Mixed | `notebooks/templates/01_ingest_shapefile.ipynb` | Local zip; remote zip via `httpfs`; encoding fixes |
| SING-002 | Ingest GeoJSON | Spatial Ingestion | Load GeoJSON features into `raw` | `source` `.geojson` / URL | `raw.raw_*` with `GEOMETRY` | Mixed | `notebooks/templates/01_ingest_geojson.ipynb` | FeatureCollection; line vs polygon layers |
| SING-003 | Ingest GeoParquet | Spatial Ingestion | Load GeoParquet with native geometry types | `source` GeoParquet file(s) | `raw.raw_*` with `GEOMETRY` | Mixed | `notebooks/templates/01_ingest_geoparquet.ipynb` | Partitioned GeoParquet; mixed WKB columns |
| SING-004 | Ingest ESRI File Geodatabase | Spatial Ingestion | Read FileGDB layers via spatial extension / GDAL | `source` `.gdb` folder | `raw.raw_*` per layer | Mixed | `notebooks/templates/01_ingest_file_gdb.ipynb` | Single layer; multi-layer loop; domain-coded fields |
| SING-005 | Spatial layer inspection | Spatial Ingestion | List layers, geometry types, and CRS before full ingest | `source` spatial file / GDB | Layer inventory report | SQL | `templates/sql/ingestion/spatial_layer_inspection.sql` | `ST_Read` metadata; feature count preview; CRS summary |

---

## EDA

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| EDA-001 | Preview rows | EDA | Quick visual scan of sample records | `raw` or `staging` table | Sample result set | SQL | `templates/sql/eda/preview_rows.sql` | `LIMIT`; `USING SAMPLE`; stratified sample |
| EDA-002 | Schema inspection | EDA | List columns, types, and nullability | Table in any layer | Schema summary | SQL | `templates/sql/eda/schema_inspection.sql` | `DESCRIBE`; `information_schema` queries |
| EDA-003 | Row counts | EDA | Count total rows and optional group counts | Table in any layer | Count metrics | SQL | `templates/sql/eda/row_counts.sql` | Overall; by partition key; by ingest file |
| EDA-004 | Null profile | EDA | Percentage and count of nulls per column | Table in any layer | Null profile table | SQL | `templates/sql/eda/null_profile.sql` | Critical columns only; threshold flags |
| EDA-005 | Distinct profile | EDA | Cardinality and top distinct values per column | Table in any layer | Distinct count report | SQL | `templates/sql/eda/distinct_profile.sql` | High-cardinality warning; top-N values |
| EDA-006 | Duplicate check | EDA | Find duplicate rows or duplicate business keys | Table in any layer | Duplicate key listing | SQL | `templates/sql/eda/duplicate_check.sql` | Full-row duplicates; composite key; `HAVING COUNT(*) > 1` |
| EDA-007 | Numeric summary | EDA | Min, max, mean, stddev for numeric columns | Table in any layer | Summary statistics | SQL | `templates/sql/eda/numeric_summary.sql` | Per-group summaries; percentile approximations |
| EDA-008 | Categorical frequency | EDA | Value counts for low-cardinality columns | Table in any layer | Frequency table | SQL | `templates/sql/eda/categorical_frequency.sql` | Top-N; include null bucket; sorted bar-ready output |
| EDA-009 | Date range check | EDA | Min/max dates and out-of-range detection | Table with date/timestamp columns | Date range report | SQL | `templates/sql/eda/date_range_check.sql` | Future dates; pre-epoch dates; fiscal year bounds |
| EDA-010 | Outlier scan | EDA | Flag numeric outliers via IQR or z-score | Table in any layer | Outlier candidate rows | SQL | `templates/sql/eda/outlier_scan.sql` | Per-column IQR; modified z-score; domain caps |

---

## Spatial EDA

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SEDA-001 | Geometry type count | Spatial EDA | Count features by geometry type (Point, LineString, Polygon, etc.) | `raw` or `staging` spatial table | Geometry type summary | SQL | `templates/sql/eda_spatial/geometry_type_count.sql` | Multi-type collections; empty geometry bucket |
| SEDA-002 | Spatial extent | Spatial EDA | Compute bounding box and spatial extent of layer | Spatial table | Extent metrics / envelope | SQL | `templates/sql/eda_spatial/spatial_extent.sql` | Per-group extent; `ST_Extent`; map-ready bbox |
| SEDA-003 | Null geometry check | Spatial EDA | Find rows with missing or empty geometries | Spatial table | Null / empty geometry report | SQL | `templates/sql/eda_spatial/null_geometry_check.sql` | `NULL` geom; `ST_IsEmpty`; percent null |
| SEDA-004 | Invalid geometry check | Spatial EDA | Detect invalid geometries before transformation | Spatial table | Invalid geometry listing | SQL | `templates/sql/eda_spatial/invalid_geometry_check.sql` | `ST_IsValid`; `ST_IsValidReason`; repair candidates |
| SEDA-005 | CRS check | Spatial EDA | Inspect and validate coordinate reference system | Spatial table | CRS report | SQL | `templates/sql/eda_spatial/crs_check.sql` | Missing SRID; mixed CRS; target CRS recommendation |
| SEDA-006 | Area / length summary | Spatial EDA | Summarize polygon area and line length | Spatial table | Area / length statistics | SQL | `templates/sql/eda_spatial/area_length_summary.sql` | Reproject before measure; units conversion; per-category stats |

---

## Cleaning

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| CLN-001 | Text cleaning | Cleaning | Trim, case-normalize, and remove junk characters from text fields | `raw.raw_*` | `staging.stg_*` | SQL | `templates/sql/cleaning/text_cleaning.sql` | Regex replace; collapse whitespace; strip punctuation |
| CLN-002 | Safe casting | Cleaning | Cast columns with `TRY_CAST` to avoid pipeline failures | `raw.raw_*` | `staging.stg_*` typed columns | SQL | `templates/sql/cleaning/safe_casting.sql` | Log cast failures; default on failure; multi-type probe |
| CLN-003 | Date parsing | Cleaning | Parse heterogeneous date strings to `DATE` / `TIMESTAMP` | `raw.raw_*` | `staging.stg_*` | SQL | `templates/sql/cleaning/date_parsing.sql` | Multiple format masks; timezone normalization |
| CLN-004 | Missing value handling | Cleaning | Impute, flag, or drop rows with missing critical fields | `staging.stg_*` | `staging.stg_*` | SQL | `templates/sql/cleaning/missing_value_handling.sql` | Drop; sentinel value; domain-specific imputation |
| CLN-005 | Deduplication | Cleaning | Remove duplicate rows or keep latest by key | `staging.stg_*` | `staging.stg_*` deduped | SQL | `templates/sql/cleaning/deduplication.sql` | `ROW_NUMBER` keep-first; keep-latest by timestamp |
| CLN-006 | Column standardization | Cleaning | Rename columns to snake_case and apply standard vocab | `staging.stg_*` | `staging.stg_*` | SQL | `templates/sql/cleaning/column_standardization.sql` | Mapping table; reserved-word quoting; unit suffixes |

---

## Transformation

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| XFM-001 | CTE pipeline | Transformation | Build readable multi-step transforms with chained CTEs | `staging.stg_*` | `staging.stg_*` or `curated.cur_*` | SQL | `templates/sql/transformation/cte_pipeline.sql` | Intermediate audit CTEs; comment anchors per step |
| XFM-002 | Joins | Transformation | Combine staging tables with explicit join keys and grain | Multiple `staging.stg_*` | `staging.stg_*` or `curated.cur_*` | SQL | `templates/sql/transformation/joins.sql` | Left / inner / full; anti-join for gaps; dedupe after join |
| XFM-003 | Aggregations | Transformation | Roll up metrics to reporting grain | `staging.stg_*` | `curated.cur_*` | SQL | `templates/sql/transformation/aggregations.sql` | `GROUP BY ALL`; `GROUPING SETS`; filter before aggregate |
| XFM-004 | Window functions | Transformation | Rank, lag, lead, and running totals without losing row grain | `staging.stg_*` | `staging.stg_*` or `curated.cur_*` | SQL | `templates/sql/transformation/window_functions.sql` | `PARTITION BY`; rolling windows; `QUALIFY` |
| XFM-005 | Pivot / unpivot | Transformation | Reshape wide ↔ long for analysis-ready tables | `staging.stg_*` | `curated.cur_*` | SQL | `templates/sql/transformation/pivot_unpivot.sql` | `PIVOT` / `UNPIVOT`; manual `CASE` pivot |
| XFM-006 | Build dimension table | Transformation | Create conformed dimension with surrogate keys | `staging.stg_*` | `curated.cur_dim_*` | SQL | `templates/sql/transformation/build_dimension_table.sql` | Slowly changing attributes; natural key uniqueness |
| XFM-007 | Build fact table | Transformation | Create fact table at event/transaction grain | `staging.stg_*` + dimensions | `curated.cur_fact_*` | SQL | `templates/sql/transformation/build_fact_table.sql` | Additive vs semi-additive measures; orphan key check |

---

## Spatial Transformation

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SXFM-001 | Spatial join | Spatial Transformation | Join attributes by spatial relationship (intersects, within) | Two spatial `staging` / `curated` tables | `curated.cur_*` | SQL | `templates/sql/spatial_transform/spatial_join.sql` | Point-in-polygon; intersects; left join keep all targets |
| SXFM-002 | Buffer analysis | Spatial Transformation | Create buffer zones around features for proximity analysis | Spatial `staging` table | `curated.cur_*` buffers | SQL | `templates/sql/spatial_transform/buffer_analysis.sql` | Fixed distance; unit-aware; dissolve buffers |
| SXFM-003 | Nearest feature | Spatial Transformation | Find nearest neighbor feature per point | Point layer + candidate layer | `curated.cur_*` with nearest ID / distance | SQL | `templates/sql/spatial_transform/nearest_feature.sql` | K-nearest; max search radius; tie-break rules |
| SXFM-004 | Clip / intersection | Spatial Transformation | Clip features to boundary or compute intersections | Two spatial layers | `curated.cur_*` clipped / intersected | SQL | `templates/sql/spatial_transform/clip_intersection.sql` | `ST_Intersection`; `ST_Intersection` with area filter |
| SXFM-005 | Build curated spatial layer | Spatial Transformation | Publish analysis-ready spatial layer with standard schema | `staging.stg_*` spatial | `curated.cur_*` spatial | Mixed | `notebooks/templates/03_build_curated_spatial_layer.ipynb` | CRS reprojection; simplify geometry; drop slivers |

---

## Validation

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| VAL-001 | Row count reconciliation | Validation | Compare row counts across pipeline stages | `raw`, `staging`, `curated` tables | Pass/fail count report | SQL | `templates/sql/validation/row_count_reconciliation.sql` | Source vs raw; raw vs staging tolerance |
| VAL-002 | Primary key uniqueness | Validation | Assert business or surrogate key is unique | Table in any layer | Duplicate key listing | SQL | `templates/sql/validation/primary_key_uniqueness.sql` | Composite keys; soft-delete key scope |
| VAL-003 | Required field null check | Validation | Fail when required columns contain nulls | `staging` or `curated` table | Null violation report | SQL | `templates/sql/validation/required_field_null_check.sql` | Conditional requiredness; severity levels |
| VAL-004 | Referential integrity | Validation | Detect orphan foreign keys vs dimension table | Fact + dimension tables | Orphan key listing | SQL | `templates/sql/validation/referential_integrity.sql` | Optional vs mandatory relationships |
| VAL-005 | Value range check | Validation | Assert numeric and date columns fall within domain | `staging` or `curated` table | Out-of-range rows | SQL | `templates/sql/validation/value_range_check.sql` | Min/max config table; percentile bounds |
| VAL-006 | Category domain check | Validation | Assert categorical values belong to allowed set | `staging` or `curated` table | Invalid category listing | SQL | `templates/sql/validation/category_domain_check.sql` | Reference lookup table; case-insensitive match |
| VAL-007 | Aggregate reconciliation | Validation | Compare summed metrics between stages | Two pipeline tables | Metric delta report | SQL | `templates/sql/validation/aggregate_reconciliation.sql` | Sum / count / distinct count; tolerance threshold |
| VAL-008 | Spatial validity check | Validation | Assert all geometries are valid before export | `curated` spatial table | Invalid feature report | SQL | `templates/sql/validation/spatial_validity_check.sql` | CRS present; no empty geom; validity reason |

---

## Export

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| EXP-001 | Export CSV | Export | Deliver tabular output as CSV for spreadsheets and tools | `curated.cur_*` | `output/*.csv` | SQL | `templates/sql/export/export_csv.sql` | Header options; delimiter; single file vs per-partition |
| EXP-002 | Export Parquet | Export | Deliver columnar output for analytics consumers | `curated.cur_*` | `output/*.parquet` | SQL | `templates/sql/export/export_parquet.sql` | ZSTD compression; row group size; single file |
| EXP-003 | Export partitioned Parquet | Export | Write hive-partitioned Parquet for scalable downstream use | `curated.cur_*` | `output/partitioned/` | SQL | `templates/sql/export/export_partitioned_parquet.sql` | Partition by date / region; overwrite vs append |
| EXP-004 | Export GeoParquet | Export | Deliver spatial layer in GeoParquet format | `curated.cur_*` spatial | `output/*.parquet` | SQL | `templates/sql/export/export_geoparquet.sql` | CRS metadata; geometry column name convention |
| EXP-005 | Export GeoJSON | Export | Deliver spatial layer for web mapping and lightweight sharing | `curated.cur_*` spatial | `output/*.geojson` | SQL | `templates/sql/export/export_geojson.sql` | `COPY` GDAL driver; simplify for web; feature limit |
| EXP-006 | Export delivery package | Export | Bundle data, metadata, and validation summary for handoff | `curated` + validation results | `output/delivery_*/` folder | Mixed | `notebooks/templates/04_export_delivery_package.ipynb` | README manifest; checksum file; QA report attachment |

---

## Performance

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| PERF-001 | Explain query plan | Performance | Inspect logical and physical plan for a slow query | SQL statement | `EXPLAIN` / `EXPLAIN ANALYZE` output | SQL | `templates/sql/performance/explain_query_plan.sql` | `EXPLAIN ANALYZE`; compare before/after rewrite |
| PERF-002 | Profile notebook pipeline | Performance | Time each notebook stage and capture row counts | Multi-step notebook workflow | Stage timing log | Notebook | `notebooks/templates/99_profile_pipeline.ipynb` | Per-cell timing; memory snapshot |
| PERF-003 | Configure threads and memory | Performance | Set DuckDB resource limits for local and CI runs | DuckDB connection | Tuned session settings | SQL | `templates/sql/performance/configure_threads_memory.sql` | `threads`; `memory_limit`; `temp_directory` |
| PERF-004 | Pushdown-friendly ingest | Performance | Ingest with predicates and column pruning at read time | `source` file(s) | `raw.raw_*` subset | SQL | `templates/sql/performance/pushdown_friendly_ingest.sql` | Parquet column selection; filter pushdown on read |
| PERF-005 | Materialize vs view guidance | Performance | Choose when to persist intermediate results vs use views | Pipeline SQL | Decision checklist + examples | Mixed | `docs/07-performance.md` | Large joins; repeated downstream reads |

---

## Notebook Templates

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| NB-001 | Quickstart workflow | Notebook Templates | End-to-end mini pipeline: setup → ingest → validate → export | One online `source` dataset | `output` artifact + QA summary | Notebook | `notebooks/00_quickstart.ipynb` | Swap dataset URL; tabular-only path |
| NB-002 | Ingest online data | Notebook Templates | Register and ingest real-world remote datasets into `raw` | Public HTTP / S3 URLs | `raw.raw_*` tables | Notebook | `notebooks/01_ingest_online_data.ipynb` | CSV; GeoJSON; multi-file folder |
| NB-003 | Staging transformations | Notebook Templates | Clean, cast, and standardize `raw` into `staging` | `raw.raw_*` | `staging.stg_*` | Notebook | `notebooks/02_staging_transformations.ipynb` | Single-table clean; multi-table join prep |
| NB-004 | Validation checks | Notebook Templates | Run validation suite and summarize pass/fail | `staging` / `curated` tables | Validation report cells | Notebook | `notebooks/03_validation_checks.ipynb` | Threshold config; stop-on-fail toggle |
| NB-005 | Exports | Notebook Templates | Export `curated` models to consumer formats | `curated.cur_*` | `output/` files | Notebook | `notebooks/04_exports.ipynb` | Parquet + CSV bundle; dated output paths |
| NB-006 | Spatial workflows | Notebook Templates | Full spatial path: ingest → spatial EDA → transform → GeoParquet export | Spatial `source` files / URLs | `curated` + `output` spatial artifacts | Notebook | `notebooks/05_spatial_workflows.ipynb` | Shapefile; GeoJSON; FileGDB branch |
| NB-007 | Blank pipeline scaffold | Notebook Templates | Empty notebook with pre-wired sections per workflow layer | Project config | Runnable section skeleton | Notebook | `notebooks/templates/99_blank_pipeline_scaffold.ipynb` | Tabular-only; spatial add-on sections |

---

## Python Helper Modules

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| PY-001 | Connection factory | Python Helper Modules | Create configured DuckDB connections (memory or file) | Config dict / env vars | `duckdb.DuckDBPyConnection` | Python | `templates/python/connection.py` | Read-only; attach second DB |
| PY-002 | Project paths helper | Python Helper Modules | Resolve workflow layer directories consistently | Project root | Path objects for `data/*` | Python | `templates/python/paths.py` | Override via env; create-if-missing |
| PY-003 | Extension loader | Python Helper Modules | Install and load standard and spatial extensions | Connection | Side-effect: extensions loaded | Python | `templates/python/extensions.py` | Minimal vs full extension set |
| PY-004 | SQL file runner | Python Helper Modules | Execute `.sql` template files with parameter substitution | Connection + SQL path + params | Query results / no return | Python | `templates/python/sql_runner.py` | Jinja params; multi-statement scripts |
| PY-005 | Validation runner | Python Helper Modules | Run validation SQL templates and collect pass/fail DataFrame | Connection + table refs | Validation summary DataFrame | Python | `templates/python/validation_runner.py` | Fail-fast; export HTML report |
| PY-006 | Export helpers | Python Helper Modules | Wrap `COPY` exports with naming conventions and folders | Connection + curated table | Files under `output/` | Python | `templates/python/export_helpers.py` | Partitioned export; timestamp suffix |
| PY-007 | Spatial helpers | Python Helper Modules | Common spatial ingest and CRS utilities | Spatial file paths / URLs | `raw` or `staging` spatial tables | Python | `templates/python/spatial_helpers.py` | Reproject; layer list; bbox filter |

---

## SQL Template Files

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SQL-001 | Layer schema DDL | SQL Template Files | Create `raw`, `staging`, `curated` schemas and conventions | Database connection | Schemas created | SQL | `templates/sql/setup/create_layer_schemas.sql` | Add `output` views schema; grants |
| SQL-002 | Raw ingest snippets | SQL Template Files | Copy-paste `CREATE TABLE AS` patterns per file format | `source` paths / URLs | `raw.raw_*` DDL/DML | SQL | `templates/sql/ingestion/_snippets/` | One file per format (CSV, Parquet, JSON, spatial) |
| SQL-003 | Staging clean snippets | SQL Template Files | Modular cleaning statements for staging builds | `raw.raw_*` | `staging.stg_*` fragments | SQL | `templates/sql/cleaning/_snippets/` | Compose in notebook or master script |
| SQL-004 | Validation suite | SQL Template Files | Bundle of validation queries with consistent result shape | Pipeline tables | Uniform check result columns | SQL | `templates/sql/validation/_suite.sql` | Run all; selective subset |
| SQL-005 | Export snippets | SQL Template Files | `COPY` one-liners per output format | `curated.cur_*` | `output` files | SQL | `templates/sql/export/_snippets/` | Compression; GDAL driver options |
| SQL-006 | Spatial transform snippets | SQL Template Files | Reusable spatial SQL for joins, buffers, and clip | Spatial tables | Transform SQL fragments | SQL | `templates/sql/spatial_transform/_snippets/` | Parameterized table names in comments |

---

## Quick Reference by Workflow Layer

| Layer | Typical Templates |
|---|---|
| `source` | ING-*, SING-*, ING-007, ING-008 |
| `raw` | ING-*, SING-*, EDA-*, SEDA-* |
| `staging` | CLN-*, XFM-001–005, EDA-*, VAL-* |
| `curated` | XFM-*, SXFM-*, VAL-*, SEDA-* |
| `output` | EXP-*, NB-005, PY-006 |

---

## Suggested Starting Paths

| If you need to… | Start with |
|---|---|
| Run your first end-to-end example | NB-001, SETUP-001, ING-007 |
| Ingest local CSV or Parquet | SETUP-002, SETUP-004, ING-001 or ING-002 |
| Work with Shapefile or GeoJSON | SETUP-005, SING-001 or SING-002, SEDA-001 |
| Build a curated reporting table | CLN-*, XFM-003, XFM-006, XFM-007, VAL-* |
| Publish spatial outputs | SXFM-005, EXP-004, EXP-005 |
| Harden a pipeline before delivery | NB-004, VAL-*, EXP-006 |

---

## Related Documentation

- Repository overview and conventions: [`../README.md`](../README.md)
- DuckDB official docs: [https://duckdb.org/docs/current/](https://duckdb.org/docs/current/)
