# DuckDB Workflow Documentation

A notebook-first documentation and template library for common DuckDB workflows involving exploratory data analysis, ETL, validation, exports, and spatial data processing.

This repository is designed to help mixed users — analysts, engineers, data scientists, GIS users, and Python/SQL users — work with DuckDB in a consistent and reusable way.

---

## Purpose

DuckDB is highly effective for local analytics, file-based data processing, lightweight ETL, and notebook-driven exploration.

This documentation provides reusable templates for the workflows that occur most often:

- Loading data from common file formats
- Performing exploratory data analysis
- Cleaning and standardizing data
- Transforming raw data into curated outputs
- Validating data quality
- Exporting final datasets
- Working with spatial formats such as Shapefiles, GeoParquet, GeoJSON, and ESRI File Geodatabases

The goal is to standardize common workflows while keeping the templates flexible enough for project-specific adaptation.

---

## Target Users

This repository is intended for mixed users, including:

- Data analysts
- Data engineers
- GIS analysts
- Python users
- SQL users
- Project teams preparing repeatable data workflows
- Engineers and technical specialists working with tabular or spatial datasets

The templates are notebook-first, but most SQL and Python blocks can be reused in scripts or production pipelines.

---

## Workflow Philosophy

The recommended workflow follows a lightweight layered approach:

```text
source → raw → staging → curated → output
