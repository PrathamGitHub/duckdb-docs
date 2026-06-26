# DuckDB Workflow Docs

Notebook-first DuckDB workflows for EDA, ETL, validation, export, and spatial analytics.

This site documents reusable patterns for building layered data workflows in DuckDB:

```text
source → raw → staging → curated → output
```

## Start here

- [What is DuckDB?](00_overview/what_is_duckdb.md) — in-process analytics and spatial SQL in notebooks
- [Workflow layers](00_overview/workflow_layers.md) — how each layer fits together
- [Project structure](00_overview/project_structure.md) — folders, schemas, and naming
- [Template index](template_index.md) — catalog of SQL and notebook templates

## Common tasks

| Task | Start with |
|------|------------|
| Set up a local database | [Local database](01_setup/local_database.md) |
| Ingest CSV or Parquet | [CSV](02_ingestion/csv.md) · [Parquet](02_ingestion/parquet.md) |
| Load spatial data | [Spatial extension setup](03_spatial_ingestion/spatial_extension_setup.md) |
| Profile a table | [Preview rows](04_eda/preview_rows.md) · [Null profile](04_eda/null_profile.md) |
| Validate before export | [Validation summary table](09_validation/validation_summary_table.md) |
| Export results | [Parquet export](10_export/parquet_export.md) · [GeoJSON export](10_export/geojson_export.md) |

## Repository

Source code, notebooks, and SQL templates live in the [GitHub repository](https://github.com/PrathamGitHub/duckeb-docs).
