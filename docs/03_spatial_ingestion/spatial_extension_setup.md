# Spatial Extension Setup

Load DuckDB's `spatial` extension before ingesting Shapefile, GeoJSON, GeoParquet, or ESRI File Geodatabase data. This page is the prerequisite for every file in `docs/03_spatial_ingestion/`.

## Purpose

Enable geometry types, GDAL-based vector I/O (`ST_Read`, `COPY ... FORMAT GDAL`), and spatial SQL (`ST_Intersects`, `ST_Transform`, buffers, overlays) in notebook-first workflows.

## When to Use

- Any ingest or export of vector spatial formats in this repository
- Spatial joins, clipping, buffering, or CRS reprojection in `staging` or `curated`
- Inspecting layers and CRS before full load — see [layer inspection](layer_inspection.md)

Skip for pure tabular CSV/Parquet notebooks that never touch geometry.

## Required DuckDB Extension

```sql
INSTALL spatial;
LOAD spatial;
```

Remote `source` URLs also need `httpfs`:

```sql
INSTALL httpfs;
LOAD httpfs;
```

Optional for nested JSON attributes alongside geometry:

```sql
INSTALL json;
LOAD json;
```

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| DuckDB version | 1.x with community `spatial` extension available |
| GDAL drivers | Bundled with the extension — not identical to a system GDAL install |
| File paths | Resolve from project root; local mirrors under `data/raw/` |
| Workflow layer | Files on disk are **source**; DuckDB tables live in schema `raw` |
| Geometry column | GDAL ingest typically exposes `geom` (rename in `staging` if needed) |

## Basic DuckDB SQL

Verify the extension is active:

```sql
SELECT extension_name, loaded, installed
FROM duckdb_extensions()
WHERE extension_name = 'spatial';
```

List GDAL drivers available in **your** session (FileGDB support depends on this):

```sql
SELECT short_name, long_name, can_open
FROM ST_Drivers()
WHERE can_open
ORDER BY short_name;
```

Quick smoke test with a public GeoJSON URL:

```sql
INSTALL httpfs;
LOAD httpfs;
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
LIMIT 5;
```

## Create Raw Spatial Table Pattern

After setup, register a local file into `raw` (example — Shapefile):

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_parcels_shp AS
SELECT *
FROM ST_Read('data/raw/parcels.shp');
```

Same pattern applies to GeoJSON, GeoParquet, and FileGDB — see the format-specific pages.

## Geometry Column Notes

- `ST_Read` returns a `GEOMETRY` column (commonly named `geom`) plus attribute columns from the source.
- Use `keep_wkb := true` on `ST_Read` when you need raw WKB for exotic subtypes not yet mapped to `GEOMETRY`.
- Standardize names in `staging`: `ST_MakeValid(geom) AS geom` per [naming conventions](../00_overview/naming_conventions.md).
- One primary geometry column per table in `staging` and `curated`.

## CRS Notes

- CRS may be embedded in the file (`.prj`, GeoJSON `crs`, GeoParquet metadata) or absent.
- Inspect before assuming WGS 84: use `ST_Read_Meta` — see [layer inspection](layer_inspection.md).
- Reproject in `staging` when mixing layers: `ST_Transform(geom, 'EPSG:4326')`.
- Store the intended CRS in notebook comments or a `crs_epsg` column when the source is ambiguous.

## Common Variations

### Notebook bootstrap (recommended first cell)

```python
from pathlib import Path
import duckdb

ROOT = Path.cwd()
while not (ROOT / "pyproject.toml").exists() and ROOT != ROOT.parent:
    ROOT = ROOT.parent

RAW_DIR = ROOT / "data" / "raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(ROOT / "work.duckdb"))

for ext in ("httpfs", "spatial"):
    con.execute(f"INSTALL {ext}; LOAD {ext};")

con.execute("""
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;
""")
```

### Load only what you need

```python
# Tabular + remote only
for ext in ("httpfs", "json"):
    con.execute(f"INSTALL {ext}; LOAD {ext};")

# Full spatial ingest notebook
for ext in ("httpfs", "spatial", "json"):
    con.execute(f"INSTALL {ext}; LOAD {ext};")
```

### Restrict GDAL driver (troubleshooting)

```sql
SELECT *
FROM ST_Read(
  'data/raw/project.gdb',
  layer := 'Parcels',
  allowed_drivers := ['OpenFileGDB']
);
```

### Spatial filter at read time (large files)

```sql
SELECT *
FROM ST_Read(
  'data/raw/parcels.shp',
  spatial_filter_box := ST_MakeEnvelope(-122.5, 37.7, -122.3, 37.9)
);
```

## Validation Checks After Setup

```sql
-- Extension loaded
SELECT loaded FROM duckdb_extensions() WHERE extension_name = 'spatial';

-- OpenFileGDB available (required for .gdb)
SELECT COUNT(*) AS openfile_gdb_available
FROM ST_Drivers()
WHERE short_name = 'OpenFileGDB' AND can_open;

-- ESRI Shapefile available
SELECT COUNT(*) AS shapefile_available
FROM ST_Drivers()
WHERE short_name = 'ESRI Shapefile' AND can_open;

-- Read test: row count > 0
SELECT COUNT(*) AS n
FROM ST_Read('data/raw/boundary.geojson');
```

## Known Limitations

- The extension bundles its own GDAL build — driver list and format quirks may differ from `ogrinfo` on your OS.
- `ST_Read` is largely **single-threaded** through GDAL; large ingests can be slower than native `read_parquet` on flat GeoParquet.
- **Raster** formats are not supported — vector only.
- Some proprietary or newer GDB versions may fail with bundled `OpenFileGDB`; use [ogr2ogr fallback](esri_file_geodatabase.md).
- `INSTALL` downloads artifacts once; after a kernel restart you must `LOAD spatial` again.
- Remote reads depend on network stability — mirror critical `source` files to `data/raw/`.

## Related Pages

- [Shapefile](shapefile.md)
- [GeoJSON](geojson.md)
- [GeoParquet](geoparquet.md)
- [ESRI File Geodatabase](esri_file_geodatabase.md)
- [Layer inspection](layer_inspection.md)
- [Extensions](../01_setup/extensions.md)
- [Notebook setup cell](../01_setup/notebook_setup_cell.md)

Official reference: [DuckDB spatial extension](https://duckdb.org/docs/current/core_extensions/spatial/overview.html)
