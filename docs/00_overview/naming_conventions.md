# Naming Conventions

Consistent names make notebooks, SQL templates, and exports easy to search and reuse across tabular and spatial workflows.

Convention for layers:

```text
source → raw → staging → curated → output
```

## Schemas (DuckDB)

| Schema | Layer | Purpose |
|--------|-------|---------|
| `raw` | raw | As-ingested tables |
| `staging` | staging | Cleaned, typed, join-ready |
| `curated` | curated | Business-ready models |

```sql
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;
```

Fully qualified names are preferred in templates and exports:

```sql
SELECT * FROM staging.stg_population;
```

## Table Prefixes

| Prefix | Schema | Example | Meaning |
|--------|--------|---------|---------|
| `raw_` | `raw` | `raw.raw_population_csv` | Ingested from a specific source |
| `stg_` | `staging` | `staging.stg_population` | Cleaned staging table |
| `cur_` | `curated` | `curated.cur_population_by_region` | General curated model |
| `fct_` | `curated` | `curated.fct_orders` | Fact table at event/transaction grain |
| `dim_` | `curated` | `curated.dim_customers` | Dimension / lookup table |
| `geo_` | `curated` | `curated.geo_parcels` | Spatial curated layer |
| `cur_dim_` | `curated` | `curated.cur_dim_store` | Dimension table (`cur_` style) |
| `cur_fact_` | `curated` | `curated.cur_fact_sales` | Fact table (`cur_` style) |

### Raw table names

Include **source hint** (format or system):

```text
raw_<topic>_<format_or_source>
```

Examples:

- `raw.raw_population_csv` — CSV from population dataset
- `raw.raw_orders` — orders CSV when format is obvious from context
- `raw.raw_parcels` or `raw.raw_parcels_shp` — Shapefile ingest
- `raw.raw_zoning_gdb` — FileGDB layer
- `raw.raw_stops_geojson` — GeoJSON from API
- `raw.raw_boundaries_geoparquet` — GeoParquet file

### Staging table names

Drop format suffix; use business entity:

- `staging.stg_population`
- `staging.stg_parcels`
- `staging.stg_zoning`
- `staging.stg_bus_stops`

Intermediate staging tables: add a short qualifier:

- `staging.stg_population_recent`
- `staging.stg_parcels_repaired`

### Curated table names

Name by **grain** and **use case**:

- `curated.cur_population_by_country` — one row per country per year (`cur_` style)
- `curated.fct_orders` — transactional fact at order grain
- `curated.dim_customers` — one row per customer
- `curated.geo_parcels` — spatial parcels ready for export
- `curated.cur_parcels_by_zone` — parcels with zoning attributes (`cur_` style)

## Columns

- **snake_case** for all columns: `country_name`, `tract_id`, `effective_date`
- **Booleans:** `is_active`, `has_geometry`, `was_imputed`
- **Dates:** suffix `_date` or `_at` — `order_date`, `created_at`
- **Keys:** `<entity>_id` — `store_id`, `parcel_id`
- **Geometry:** default name `geom` (or `geometry` if matching source); one primary geometry column per table

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT
  parcel_id,
  owner_name,
  ST_MakeValid(geom) AS geom
FROM raw.raw_parcels_shp;
```

## Files and Paths

### Data directories

```text
data/source/     # optional local mirrors
data/raw/
data/staging/
data/curated/
data/output/     # published files
```

### Output files

Pattern: `<topic>_<grain_or_variant>.<ext>`

Examples:

- `data/output/population_by_country.parquet`
- `data/output/sales_2026_06.parquet` — date-partitioned when useful
- `data/output/parcels_by_zone.geoparquet`
- `data/output/service_areas.geojson`

Use **lowercase** and **underscores**; avoid spaces in paths.

### Database file

- `work.duckdb` at project root, or `data/work.duckdb` if you prefer data colocation

## Notebooks

| Pattern | Example |
|---------|---------|
| Base workflow notebooks | `00_eda_base.ipynb`, `01_etl_base.ipynb`, `02_spatial_eda_base.ipynb` |
| Single-task starters | `notebooks/templates/01_ingest_csv.ipynb` **(planned)** |
| Spatial EDA / export | `02_spatial_eda_base.ipynb`, `04_export_base.ipynb` |

## SQL Templates

Group by task under `sql/`:

```text
sql/ingestion/ingest_csv.sql
sql/validation/primary_key_uniqueness.sql
sql/export/export_geoparquet.sql
sql/spatial/ingest_shapefile.sql
```

File names: **verb + object**, snake_case, no layer prefix in filename (layer is inside the SQL).

## Tabular vs. Spatial Naming

Same rules apply; spatial tables often include format in `raw_` only:

| Stage | Tabular | Spatial |
|-------|---------|---------|
| raw | `raw.raw_sales_csv` | `raw.raw_tracts_geoparquet` |
| staging | `staging.stg_sales` | `staging.stg_tracts` |
| curated | `curated.cur_sales_by_region` | `curated.geo_tracts_by_county` |
| output | `sales_by_region.parquet` | `tracts_by_county.geoparquet` |

## Quick Reference

```sql
-- Ingest
CREATE TABLE raw.raw_<source> AS SELECT * FROM read_csv_auto('...');

-- Stage
CREATE TABLE staging.stg_<entity> AS SELECT ... FROM raw.raw_<source>;

-- Curate
CREATE TABLE curated.cur_<entity>_<grain> AS SELECT ... FROM staging.stg_<entity>;

-- Export
COPY (SELECT * FROM curated.cur_<name>) TO 'data/output/<name>.parquet' (FORMAT PARQUET);
```

## Anti-Patterns to Avoid

| Avoid | Prefer |
|-------|--------|
| `RawData`, `STAGING_TABLE` | `raw.raw_population_csv`, `staging.stg_population` |
| Mixing cleaned data in `raw` | New table in `staging` |
| `final_final_v2` table names | `curated.cur_<grain>` with version in git |
| Spaces in file paths | `data/output/my_export.parquet` |

## Related Pages

- [Workflow layers](workflow_layers.md)
- [Project structure](project_structure.md)
