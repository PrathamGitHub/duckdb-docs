# DuckDB Workflow Template Index

Central catalog of reusable DuckDB workflow templates for this repository.  
Templates follow the layered workflow convention:

```text
source → raw → staging → curated → output
```

Use this index to find a starting point by task, then copy the linked notebook, SQL file, or Python module into your project.  
Templates are designed for mixed audiences: analysts, data engineers, GIS users, Python users, and SQL users.

**Primary mode legend:** `Notebook` · `SQL` · `Python` · `Mixed`

**File locations:** Reusable SQL and Python assets live at the repository root in `sql/` and `python/` (not under `templates/`). Runnable notebooks are `notebooks/*_base.ipynb`. Paths marked **(planned)** are catalogued but not yet checked in; use the linked `docs/` page or nearest `*_base` notebook meanwhile.

---

## Setup

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SETUP-001 | Connect in-memory | Setup | Open a transient DuckDB session for exploration and unit-style checks | None | In-memory connection handle | Mixed | `docs/01_setup/in_memory_database.md` | `notebooks/templates/00_setup_connect_memory.ipynb` (planned) |
| SETUP-002 | Connect persistent database | Setup | Open or create a file-backed DuckDB database for repeatable pipelines | Database file path | Persistent `.duckdb` connection | Mixed | `docs/01_setup/local_database.md` | `notebooks/templates/00_setup_connect_persistent.ipynb` (planned) |
| SETUP-003 | Configure project paths | Setup | Standardize `data/raw`, `data/staging`, `data/curated`, and `data/output` paths across notebooks | Project root | Path variables / config dict | Python | `python/path_helpers.py` | Environment-variable overrides; per-run timestamp folders |
| SETUP-004 | Load common extensions | Setup | Install and load `httpfs`, `json`, and other frequently used extensions | DuckDB connection | Extensions ready to query | SQL | `sql/setup/load_common_extensions.sql` | Add `excel`, `postgres_scanner`, `sqlite_scanner` as needed |
| SETUP-005 | Load spatial extensions | Setup | Install and load `spatial` (and optional GDAL drivers) for geometry workflows | DuckDB connection | Spatial functions available | SQL | `sql/setup/load_spatial_extensions.sql` | Enable PROJ/ GDAL options; configure S3 credentials for remote spatial reads |

---

## Ingestion

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| ING-001 | Ingest CSV | Ingestion | Load delimited text from local path or URL into the `raw` layer | `source` CSV / TSV | `raw.raw_*` table | Mixed | `docs/02_ingestion/csv.md`, `sql/ingestion/ingest_csv.sql` | `notebooks/templates/01_ingest_csv.ipynb` (planned) |
| ING-002 | Ingest Parquet | Ingestion | Load columnar Parquet files into `raw` | `source` Parquet file(s) | `raw.raw_*` table | Mixed | `docs/02_ingestion/parquet.md`, `sql/ingestion/ingest_parquet.sql` | `notebooks/templates/01_ingest_parquet.ipynb` (planned) |
| ING-003 | Ingest Excel | Ingestion | Load spreadsheet sheets into `raw` | `source` `.xlsx` / `.xls` | `raw.raw_*` table | Mixed | `docs/02_ingestion/excel.md`, `sql/ingestion/ingest_excel.sql` | `notebooks/templates/01_ingest_excel.ipynb` (planned) |
| ING-004 | Ingest JSON | Ingestion | Load JSON or NDJSON documents into `raw` | `source` JSON / NDJSON | `raw.raw_*` table | Mixed | `docs/02_ingestion/json.md`, `sql/ingestion/ingest_json.sql` | `notebooks/templates/01_ingest_json.ipynb` (planned) |
| ING-005 | Ingest folder glob | Ingestion | Batch-read all matching files in a directory | `source` folder + glob pattern | `raw.raw_*` table | SQL | `docs/02_ingestion/folders_and_globs.md` | `sql/ingestion/ingest_folder_glob.sql` (planned) |
| ING-006 | Ingest partitioned Parquet | Ingestion | Read hive-partitioned Parquet datasets | `source` partitioned Parquet tree | `raw.raw_*` table | SQL | `sql/ingestion/ingest_partitioned_parquet.sql` | Partition pruning; register as view vs materialize |
| ING-007 | Ingest remote HTTP / S3 | Ingestion | Pull remote files via `httpfs` without local download | `source` HTTP / S3 URL | `raw.raw_*` table | Mixed | `docs/02_ingestion/remote_files_http_s3.md` | `notebooks/templates/01_ingest_remote_http_s3.ipynb` (planned); see `notebooks/01_etl_base.ipynb` |
| ING-008 | Ingest external database | Ingestion | Federate or snapshot tables from Postgres, SQLite, or similar | `source` external DB | `raw.raw_*` table | Mixed | `docs/02_ingestion/external_databases.md` | `notebooks/templates/01_ingest_external_db.ipynb` (planned) |

---

## Spatial Ingestion

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SING-001 | Ingest Shapefile | Spatial Ingestion | Load ESRI Shapefile into `raw` with geometry column | `source` `.shp` (+ sidecar files) | `raw.raw_*` with `GEOMETRY` | Mixed | `docs/03_spatial_ingestion/shapefile.md`, `sql/spatial/ingest_shapefile.sql` | `examples/shapefile_to_geoparquet/` |
| SING-002 | Ingest GeoJSON | Spatial Ingestion | Load GeoJSON features into `raw` | `source` `.geojson` / URL | `raw.raw_*` with `GEOMETRY` | Mixed | `docs/03_spatial_ingestion/geojson.md`, `sql/spatial/ingest_geojson.sql` | `notebooks/templates/01_ingest_geojson.ipynb` (planned) |
| SING-003 | Ingest GeoParquet | Spatial Ingestion | Load GeoParquet with native geometry types | `source` GeoParquet file(s) | `raw.raw_*` with `GEOMETRY` | Mixed | `docs/03_spatial_ingestion/geoparquet.md`, `sql/spatial/ingest_geoparquet.sql` | `notebooks/templates/01_ingest_geoparquet.ipynb` (planned) |
| SING-004 | Ingest ESRI File Geodatabase | Spatial Ingestion | Read FileGDB layers via spatial extension / GDAL | `source` `.gdb` folder | `raw.raw_*` per layer | Mixed | `docs/03_spatial_ingestion/esri_file_geodatabase.md`, `sql/spatial/ingest_gdb.sql` | `notebooks/templates/01_ingest_file_gdb.ipynb` (planned) |
| SING-005 | Spatial layer inspection | Spatial Ingestion | List layers, geometry types, and CRS before full ingest | `source` spatial file / GDB | Layer inventory report | SQL | `docs/03_spatial_ingestion/layer_inspection.md` | `sql/ingestion/spatial_layer_inspection.sql` (planned) |

---

## EDA

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| EDA-001 | Preview rows | EDA | Quick visual scan of sample records | `raw` or `staging` table | Sample result set | SQL | `sql/eda/preview_rows.sql` | `LIMIT`; `USING SAMPLE`; stratified sample |
| EDA-002 | Schema inspection | EDA | List columns, types, and nullability | Table in any layer | Schema summary | SQL | `sql/eda/schema_inspection.sql` | `DESCRIBE`; `information_schema` queries |
| EDA-003 | Row counts | EDA | Count total rows and optional group counts | Table in any layer | Count metrics | SQL | `sql/eda/row_count.sql` | Overall; by partition key; by ingest file |
| EDA-004 | Null profile | EDA | Percentage and count of nulls per column | Table in any layer | Null profile table | SQL | `sql/eda/null_profile.sql` | Critical columns only; threshold flags |
| EDA-005 | Distinct profile | EDA | Cardinality and top distinct values per column | Table in any layer | Distinct count report | SQL | `docs/04_eda/distinct_profile.md` | `sql/eda/distinct_profile.sql` (planned) |
| EDA-006 | Duplicate check | EDA | Find duplicate rows or duplicate business keys | Table in any layer | Duplicate key listing | SQL | `sql/eda/duplicate_check.sql` | Full-row duplicates; composite key; `HAVING COUNT(*) > 1` |
| EDA-007 | Numeric summary | EDA | Min, max, mean, stddev for numeric columns | Table in any layer | Summary statistics | SQL | `sql/eda/numeric_summary.sql` | Per-group summaries; percentile approximations |
| EDA-008 | Categorical frequency | EDA | Value counts for low-cardinality columns | Table in any layer | Frequency table | SQL | `sql/eda/categorical_frequency.sql` | Top-N; include null bucket; sorted bar-ready output |
| EDA-009 | Date range check | EDA | Min/max dates and out-of-range detection | Table with date/timestamp columns | Date range report | SQL | `sql/eda/date_range_check.sql` | Future dates; pre-epoch dates; fiscal year bounds |
| EDA-010 | Outlier scan | EDA | Flag numeric outliers via IQR or z-score | Table in any layer | Outlier candidate rows | SQL | `docs/04_eda/outlier_scan.md` | `sql/eda/outlier_scan.sql` (planned) |

---

## Spatial EDA

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SEDA-001 | Geometry type count | Spatial EDA | Count features by geometry type (Point, LineString, Polygon, etc.) | `raw` or `staging` spatial table | Geometry type summary | SQL | `sql/spatial/geometry_type_count.sql` | `notebooks/02_spatial_eda_base.ipynb` |
| SEDA-002 | Spatial extent | Spatial EDA | Compute bounding box and spatial extent of layer | Spatial table | Extent metrics / envelope | SQL | `sql/spatial/spatial_extent.sql` | Per-group extent; `ST_Extent`; map-ready bbox |
| SEDA-003 | Null geometry check | Spatial EDA | Find rows with missing or empty geometries | Spatial table | Null / empty geometry report | SQL | `docs/05_spatial_eda/null_geometry_check.md` | `sql/spatial/null_geometry_check.sql` (planned) |
| SEDA-004 | Invalid geometry check | Spatial EDA | Detect invalid geometries before transformation | Spatial table | Invalid geometry listing | SQL | `docs/05_spatial_eda/invalid_geometry_check.md` | `sql/spatial/invalid_geometry_check.sql` (planned) |
| SEDA-005 | CRS check | Spatial EDA | Inspect and validate coordinate reference system | Spatial table | CRS report | SQL | `docs/05_spatial_eda/crs_check.md` | `sql/spatial/crs_check.sql` (planned) |
| SEDA-006 | Area / length summary | Spatial EDA | Summarize polygon area and line length | Spatial table | Area / length statistics | SQL | `docs/05_spatial_eda/area_length_summary.md` | `sql/spatial/area_length_summary.sql` (planned) |
| SEDA-007 | Spatial join preview | Spatial EDA | Estimate join cardinality before spatial overlay | Two spatial tables | Join count / sample pairs | SQL | `docs/05_spatial_eda/spatial_join_preview.md` | Run before SXFM-001 |

---

## Cleaning

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| CLN-001 | Text cleaning | Cleaning | Trim, case-normalize, and remove junk characters from text fields | `raw.raw_*` | `staging.stg_*` | SQL | `sql/cleaning/text_cleaning.sql` | Regex replace; collapse whitespace; strip punctuation |
| CLN-002 | Safe casting | Cleaning | Cast columns with `TRY_CAST` to avoid pipeline failures | `raw.raw_*` | `staging.stg_*` typed columns | SQL | `sql/cleaning/safe_casting.sql` | Log cast failures; default on failure; multi-type probe |
| CLN-003 | Date parsing | Cleaning | Parse heterogeneous date strings to `DATE` / `TIMESTAMP` | `raw.raw_*` | `staging.stg_*` | SQL | `docs/06_cleaning/date_parsing.md` | `sql/cleaning/date_parsing.sql` (planned) |
| CLN-004 | Missing value handling | Cleaning | Impute, flag, or drop rows with missing critical fields | `staging.stg_*` | `staging.stg_*` | SQL | `sql/cleaning/missing_values.sql` | Drop; sentinel value; domain-specific imputation |
| CLN-005 | Deduplication | Cleaning | Remove duplicate rows or keep latest by key | `staging.stg_*` | `staging.stg_*` deduped | SQL | `sql/cleaning/deduplication.sql` | `ROW_NUMBER` keep-first; keep-latest by timestamp |
| CLN-006 | Column standardization | Cleaning | Rename columns to snake_case and apply standard vocab | `staging.stg_*` | `staging.stg_*` | SQL | `docs/06_cleaning/column_standardization.md` | `sql/cleaning/column_standardization.sql` (planned) |

---

## Transformation

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| XFM-001 | CTE pipeline | Transformation | Build readable multi-step transforms with chained CTEs | `staging.stg_*` | `staging.stg_*` or `curated.cur_*` | SQL | `sql/transformation/cte_pipeline.sql` | Intermediate audit CTEs; comment anchors per step |
| XFM-002 | Joins | Transformation | Combine staging tables with explicit join keys and grain | Multiple `staging.stg_*` | `staging.stg_*` or `curated.*` | SQL | `sql/transformation/join_template.sql` | Left / inner / full; anti-join for gaps; dedupe after join |
| XFM-003 | Aggregations | Transformation | Roll up metrics to reporting grain | `staging.stg_*` | `curated.*` | SQL | `sql/transformation/aggregation_template.sql` | `GROUP BY ALL`; `GROUPING SETS`; filter before aggregate |
| XFM-004 | Window functions | Transformation | Rank, lag, lead, and running totals without losing row grain | `staging.stg_*` | `staging.stg_*` or `curated.*` | SQL | `sql/transformation/window_function_template.sql` | `PARTITION BY`; rolling windows; `QUALIFY` |
| XFM-005 | Pivot / unpivot | Transformation | Reshape wide ↔ long for analysis-ready tables | `staging.stg_*` | `curated.*` | SQL | `docs/07_transformation/pivot_unpivot.md` | `sql/transformation/pivot_unpivot.sql` (planned) |
| XFM-006 | Build dimension table | Transformation | Create conformed dimension with surrogate keys | `staging.stg_*` | `curated.dim_*` | SQL | `sql/transformation/build_dimension_table.sql` | Slowly changing attributes; natural key uniqueness |
| XFM-007 | Build fact table | Transformation | Create fact table at event/transaction grain | `staging.stg_*` + dimensions | `curated.fct_*` | SQL | `sql/transformation/build_fact_table.sql` | Additive vs semi-additive measures; orphan key check |

---

## Spatial Transformation

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SXFM-001 | Spatial join | Spatial Transformation | Join attributes by spatial relationship (intersects, within) | Two spatial `staging` / `curated` tables | `curated.geo_*` or `curated.cur_*` | SQL | `sql/spatial/spatial_join.sql` | Point-in-polygon; intersects; left join keep all targets |
| SXFM-002 | Buffer analysis | Spatial Transformation | Create buffer zones around features for proximity analysis | Spatial `staging` table | `curated.*` buffers | SQL | `sql/spatial/buffer_analysis.sql` | Fixed distance; unit-aware; dissolve buffers |
| SXFM-003 | Nearest feature | Spatial Transformation | Find nearest neighbor feature per point | Point layer + candidate layer | `curated.*` with nearest ID / distance | SQL | `docs/08_spatial_transformation/nearest_feature.md` | `sql/spatial/nearest_feature.sql` (planned) |
| SXFM-004 | Clip / intersection | Spatial Transformation | Clip features to boundary or compute intersections | Two spatial layers | `curated.*` clipped / intersected | SQL | `docs/08_spatial_transformation/clip_intersection.md` | `sql/spatial/clip_intersection.sql` (planned) |
| SXFM-005 | Build curated spatial layer | Spatial Transformation | Publish analysis-ready spatial layer with standard schema | `staging.stg_*` spatial | `curated.geo_*` or `curated.cur_*` | Mixed | `docs/08_spatial_transformation/build_curated_spatial_layer.md` | `notebooks/templates/03_build_curated_spatial_layer.ipynb` (planned) |

---

## Validation

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| VAL-001 | Row count reconciliation | Validation | Compare row counts across pipeline stages | `raw`, `staging`, `curated` tables | Pass/fail count report | SQL | `sql/validation/row_count_reconciliation.sql` | Source vs raw; raw vs staging tolerance |
| VAL-002 | Primary key uniqueness | Validation | Assert business or surrogate key is unique | Table in any layer | Duplicate key listing | SQL | `sql/validation/primary_key_uniqueness.sql` | Composite keys; soft-delete key scope |
| VAL-003 | Required field null check | Validation | Fail when required columns contain nulls | `staging` or `curated` table | Null violation report | SQL | `sql/validation/required_field_null_check.sql` | Conditional requiredness; severity levels |
| VAL-004 | Referential integrity | Validation | Detect orphan foreign keys vs dimension table | Fact + dimension tables | Orphan key listing | SQL | `sql/validation/referential_integrity.sql` | Optional vs mandatory relationships |
| VAL-005 | Value range check | Validation | Assert numeric and date columns fall within domain | `staging` or `curated` table | Out-of-range rows | SQL | `docs/09_validation/value_range_check.md` | `sql/validation/value_range_check.sql` (planned) |
| VAL-006 | Category domain check | Validation | Assert categorical values belong to allowed set | `staging` or `curated` table | Invalid category listing | SQL | `docs/09_validation/category_domain_check.md` | `sql/validation/category_domain_check.sql` (planned) |
| VAL-007 | Date range validation | Validation | Assert dates fall within expected bounds | `staging` or `curated` table | Out-of-range date rows | SQL | `docs/09_validation/date_range_validation.md` | `notebooks/03_validation_base.ipynb` |
| VAL-008 | Aggregate reconciliation | Validation | Compare summed metrics between stages | Two pipeline tables | Metric delta report | SQL | `sql/validation/aggregate_reconciliation.sql` | Sum / count / distinct count; tolerance threshold |
| VAL-009 | Spatial validity check | Validation | Assert all geometries are valid before export | `curated` spatial table | Invalid feature report | SQL | `docs/09_validation/spatial_validity_check.md` | `sql/validation/spatial_validity_check.sql` (planned) |

---

## Export

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| EXP-001 | Export CSV | Export | Deliver tabular output as CSV for spreadsheets and tools | `curated.cur_*` | `output/*.csv` | SQL | `sql/export/export_csv.sql` | Header options; delimiter; single file vs per-partition |
| EXP-002 | Export Parquet | Export | Deliver columnar output for analytics consumers | `curated.cur_*` | `output/*.parquet` | SQL | `sql/export/export_parquet.sql` | ZSTD compression; row group size; single file |
| EXP-003 | Export partitioned Parquet | Export | Write hive-partitioned Parquet for scalable downstream use | `curated.cur_*` | `output/partitioned/` | SQL | `sql/export/export_partitioned_parquet.sql` | Partition by date / region; overwrite vs append |
| EXP-004 | Export GeoParquet | Export | Deliver spatial layer in GeoParquet format | `curated.cur_*` spatial | `output/*.parquet` | SQL | `sql/export/export_geoparquet.sql` | CRS metadata; geometry column name convention |
| EXP-005 | Export GeoJSON | Export | Deliver spatial layer for web mapping and lightweight sharing | `curated.*` spatial | `output/*.geojson` | SQL | `docs/10_export/geojson_export.md` | `sql/export/export_geojson.sql` (planned) |
| EXP-006 | Export delivery package | Export | Bundle data, metadata, and validation summary for handoff | `curated` + validation results | `output/delivery_*/` folder | Mixed | `docs/10_export/delivery_package.md` | `notebooks/templates/04_export_delivery_package.ipynb` (planned) |

---

## Performance

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| PERF-001 | Explain query plan | Performance | Inspect logical and physical plan for a slow query | SQL statement | `EXPLAIN` / `EXPLAIN ANALYZE` output | SQL | `docs/11_performance/explain_analyze.md` | `sql/performance/explain_query_plan.sql` (planned) |
| PERF-002 | Profile notebook pipeline | Performance | Time each notebook stage and capture row counts | Multi-step notebook workflow | Stage timing log | Notebook | `notebooks/templates/99_profile_pipeline.ipynb` (planned) | Per-cell timing; memory snapshot |
| PERF-003 | Configure threads and memory | Performance | Set DuckDB resource limits for local and CI runs | DuckDB connection | Tuned session settings | SQL | `docs/11_performance/memory_management.md` | `sql/performance/configure_threads_memory.sql` (planned) |
| PERF-004 | Pushdown-friendly ingest | Performance | Ingest with predicates and column pruning at read time | `source` file(s) | `raw.raw_*` subset | SQL | `docs/11_performance/predicate_pushdown.md` | `sql/performance/pushdown_friendly_ingest.sql` (planned) |
| PERF-005 | Materialize vs view guidance | Performance | Choose when to persist intermediate results vs use views | Pipeline SQL | Decision checklist + examples | Mixed | `docs/11_performance/large_file_patterns.md` | Large joins; repeated downstream reads |

---

## Notebook Templates

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| NB-001 | EDA base | Notebook Templates | Profile a table in `raw`, `staging`, or `curated` before cleaning or validation | One pipeline table | EDA summary + next actions | Notebook | `notebooks/00_eda_base.ipynb` | Tabular or spatial columns; duplicate and null checks |
| NB-002 | ETL base | Notebook Templates | End-to-end `source` → `raw` → `staging` → `curated` → `output` with validation | Online or local `source` | `curated` table + `output` file | Notebook | `notebooks/01_etl_base.ipynb` | TPC-H Parquet default; swap `SOURCE_FORMAT` |
| NB-003 | Spatial EDA base | Notebook Templates | Spatial profiling: geometry types, extent, CRS, validity | Spatial `raw` or `staging` table | Spatial QA summary | Notebook | `notebooks/02_spatial_eda_base.ipynb` | Shapefile, GeoJSON, GeoParquet, FileGDB |
| NB-004 | Validation base | Notebook Templates | Run validation suite and summarize pass/fail | `raw`, `staging`, `curated` tables | Validation summary DataFrame | Notebook | `notebooks/03_validation_base.ipynb` | VAL-001–VAL-009 checks; stop-on-fail toggle |
| NB-005 | Export base | Notebook Templates | Export `curated` models to consumer formats | `curated.*` table | `data/output/` files | Notebook | `notebooks/04_export_base.ipynb` | Parquet, CSV, partitioned Parquet |
| NB-006 | Single-task notebook starters | Notebook Templates | Focused ingest, setup, and delivery notebooks | Varies | Varies | Notebook | `notebooks/templates/` **(planned)** | See ING-*, SING-*, SETUP-001/002, EXP-006 |

---

## Python Helper Modules

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| PY-001 | Connection factory | Python Helper Modules | Create configured DuckDB connections (memory or file) | Config dict / env vars | `duckdb.DuckDBPyConnection` | Python | `python/duckdb_helpers.py` | Read-only; attach second DB |
| PY-002 | Project paths helper | Python Helper Modules | Resolve workflow layer directories consistently | Project root | Path objects for `data/*` | Python | `python/path_helpers.py` | Override via env; create-if-missing |
| PY-003 | Extension loader | Python Helper Modules | Install and load standard and spatial extensions | Connection | Side-effect: extensions loaded | Python | `python/duckdb_helpers.py` | Minimal vs full extension set |
| PY-004 | SQL file runner | Python Helper Modules | Execute `.sql` template files with parameter substitution | Connection + SQL path + params | Query results / no return | Python | `python/duckdb_helpers.py` | Jinja params; multi-statement scripts |
| PY-005 | Validation runner | Python Helper Modules | Run validation SQL templates and collect pass/fail DataFrame | Connection + table refs | Validation summary DataFrame | Python | `python/validation_helpers.py` | Fail-fast; export HTML report |
| PY-006 | Export helpers | Python Helper Modules | Wrap `COPY` exports with naming conventions and folders | Connection + curated table | Files under `output/` | Python | `python/export_helpers.py (planned)` | Partitioned export; timestamp suffix |
| PY-007 | Spatial helpers | Python Helper Modules | Common spatial ingest and CRS utilities | Spatial file paths / URLs | `raw` or `staging` spatial tables | Python | `python/spatial_helpers.py` | Reproject; layer list; bbox filter |

---

## SQL Template Files

| Template ID | Template Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| SQL-001 | Layer schema DDL | SQL Template Files | Create `raw`, `staging`, `curated` schemas and conventions | Database connection | Schemas created | SQL | `docs/01_setup/extensions.md` | `sql/setup/create_layer_schemas.sql` (planned) |
| SQL-002 | Raw ingest snippets | SQL Template Files | Copy-paste `CREATE TABLE AS` patterns per file format | `source` paths / URLs | `raw.raw_*` DDL/DML | SQL | `sql/ingestion/` | CSV, Parquet, JSON, Excel, spatial under `sql/spatial/` |
| SQL-003 | Staging clean snippets | SQL Template Files | Modular cleaning statements for staging builds | `raw.raw_*` | `staging.stg_*` fragments | SQL | `sql/cleaning/` | Compose in notebook or master script |
| SQL-004 | Validation suite | SQL Template Files | Bundle of validation queries with consistent result shape | Pipeline tables | Uniform check result columns | SQL | `docs/09_validation/validation_summary_table.md` | `sql/validation/_suite.sql` (planned) |
| SQL-005 | Export snippets | SQL Template Files | `COPY` one-liners per output format | `curated.*` | `output` files | SQL | `sql/export/` | Compression; GDAL driver options |
| SQL-006 | Spatial transform snippets | SQL Template Files | Reusable spatial SQL for joins, buffers, and clip | Spatial tables | Transform SQL fragments | SQL | `sql/spatial/` | Parameterized table names in comments |

---

## Quick Reference by Workflow Layer

| Layer | Typical Templates |
|---|---|
| `source` | ING-*, SING-*, ING-007, ING-008 |
| `raw` | ING-*, SING-*, EDA-*, SEDA-* |
| `staging` | CLN-*, XFM-001–005, EDA-*, VAL-* |
| `curated` | XFM-*, SXFM-*, VAL-*, SEDA-* |
| `output` | EXP-*, NB-005, EX-* |

---

## Worked Examples

| Template ID | Example Name | Category | Purpose | Input | Output | Primary Mode | File Location | Common Variations |
|---|---|---|---|---|---|---|---|---|
| EX-001 | CSV to Parquet | Worked Examples | Tabular shortcut: `source` → `raw` → `staging` → `output` | `data/raw/orders.csv` | `data/output/orders.parquet` | Mixed | `examples/csv_to_parquet/` | Promote to `curated.fct_*` via `notebooks/01_etl_base.ipynb` |
| EX-002 | Shapefile to GeoParquet | Worked Examples | Spatial shortcut: `source` → `raw` → `curated` → `output` | `data/raw/parcels.shp` | `data/output/geo_parcels.parquet` | Mixed | `examples/shapefile_to_geoparquet/` | Add `staging.stg_parcels` per `docs/06_cleaning/spatial_geometry_cleaning.md` |

---

## Suggested Starting Paths

| If you need to… | Start with |
|---|---|
| Run your first end-to-end example | NB-002 (`01_etl_base.ipynb`), EX-001, SETUP-004 |
| Profile data before cleaning | NB-001, EDA-001–EDA-004 |
| Ingest local CSV or Parquet | SETUP-004, ING-001 or ING-002, EX-001 |
| Work with Shapefile or GeoJSON | SETUP-005, SING-001 or SING-002, NB-003, EX-002 |
| Build a curated reporting table | CLN-*, XFM-003, XFM-006, XFM-007, VAL-* |
| Publish spatial outputs | SXFM-005, EXP-004, EXP-005, EX-002 |
| Harden a pipeline before delivery | NB-004, VAL-*, EXP-006 |

---

## Related Documentation

- Repository overview and conventions: [`README.md`](../README.md)
- DuckDB official docs: [https://duckdb.org/docs/current/](https://duckdb.org/docs/current/)
