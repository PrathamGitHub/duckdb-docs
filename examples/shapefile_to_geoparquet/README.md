# Shapefile to GeoParquet — Worked Example

Load a Shapefile from `data/raw/`, land it in the **raw** layer, profile geometry quality, build a **curated** spatial table, and export GeoParquet under `data/output/`.

## Workflow

```text
source (parcels.shp) → raw.raw_parcels → curated.geo_parcels → output (geo_parcels.parquet)
```

| Layer   | Object                 | Location / notes                              |
|---------|------------------------|-----------------------------------------------|
| source  | `parcels.shp`          | `data/raw/parcels.shp` (+ `.shx`, `.dbf`, `.prj`) |
| raw     | `raw.raw_parcels`      | As-ingested snapshot from `ST_Read`           |
| curated | `curated.geo_parcels`  | Validated geometry, typed attributes, measures |
| output  | `geo_parcels.parquet`  | `data/output/geo_parcels.parquet`             |

## Prerequisites

- [DuckDB](https://duckdb.org/docs/installation/) 1.0+ with the `spatial` extension (CLI or Python package)
- Python 3.10+ with `duckdb` if you run the Python script:

```bash
pip install duckdb
```

Run commands from the **repository root** (`duckeb-docs/`), not from this folder.

## Setup

### 1. Create workflow folders

```bash
mkdir -p data/raw data/output
```

### 2. Place the source Shapefile

Put the Shapefile basename at `data/raw/parcels.shp`. GDAL requires the sidecar files in the same folder:

| File            | Required | Notes                          |
|-----------------|----------|--------------------------------|
| `parcels.shp`   | Yes      | Geometry index                 |
| `parcels.shx`   | Yes      | Shape index                    |
| `parcels.dbf`   | Yes      | Attribute table                |
| `parcels.prj`   | Strongly recommended | CRS definition         |
| `parcels.cpg`   | Optional | DBF text encoding              |

**Option A — seed from a real public dataset (recommended for practice)**

The Python script can download [Natural Earth 110m admin boundaries](https://www.naturalearthdata.com/), extract the Shapefile, and write `data/raw/parcels.*` when those files are missing. The seed layer is polygon practice data — replace it with jurisdiction parcel exports for production work.

**Option B — provide your own file**

Copy vendor or open-data parcel Shapefiles into `data/raw/` using the `parcels` basename. Adjust the curated `SELECT` in `shapefile_to_geoparquet.sql` / `shapefile_to_geoparquet.py` if your attribute column names differ.

### 3. Open a DuckDB database (optional but recommended)

Both runners create `work.duckdb` at the repo root and ensure `raw`, `staging`, and `curated` schemas exist.

## What each step does

### Spatial extension setup

Install and load `spatial` before any `ST_Read` or geometry function:

```sql
INSTALL spatial;
LOAD spatial;
```

### Ingestion

Register `data/raw/parcels.shp` as `raw.raw_parcels` using `ST_Read()`.

### Spatial EDA

Profile the raw layer before building curated:

- Geometry type counts (`ST_GeometryType`)
- Null and empty geometry counts
- Invalid geometry counts (`ST_IsValid`)
- Spatial extent (`ST_Extent`)

### Curated spatial layer

Build `curated.geo_parcels` with:

- `ST_MakeValid(geom)` for repairable polygons
- Rows dropped when geometry is null or empty
- Derived `area_sqm` in a planar CRS (`EPSG:3857`)
- Conformed attribute columns: `parcel_id`, `owner_name`, `zoning_code`, `boundary_name`

The SQL maps Natural Earth seed columns (`NAME`, `ISO_A3`, `CONTINENT`) to parcel-like names. Swap the mapping when your source already has parcel fields.

### Export

`COPY curated.geo_parcels` to `data/output/geo_parcels.parquet` with ZSTD compression, then verify row count via `read_parquet` round-trip.

## How to run

### SQL (DuckDB CLI)

From the repository root, after `data/raw/parcels.shp` and sidecars exist:

```bash
duckdb work.duckdb < examples/shapefile_to_geoparquet/shapefile_to_geoparquet.sql
```

Interactive:

```bash
duckdb work.duckdb
```

```sql
.read examples/shapefile_to_geoparquet/shapefile_to_geoparquet.sql
```

### Python

From the repository root:

```bash
python examples/shapefile_to_geoparquet/shapefile_to_geoparquet.py
```

The script will:

1. Create `data/raw/` and `data/output/` if needed
2. Seed `data/raw/parcels.shp` from Natural Earth when the file is absent
3. Run extension setup → ingest → spatial EDA → curated build → export
4. Print EDA summaries and the output path

### Verify the GeoParquet file

```bash
duckdb -c "INSTALL spatial; LOAD spatial; SELECT COUNT(*) AS n, ST_Extent(geom) AS bbox FROM read_parquet('data/output/geo_parcels.parquet');"
```

Or in Python:

```python
import duckdb

duckdb.execute("INSTALL spatial; LOAD spatial;")
duckdb.sql(
    "SELECT * FROM read_parquet('data/output/geo_parcels.parquet') LIMIT 5"
).show()
```

## Files in this example

| File                          | Purpose                                           |
|-------------------------------|---------------------------------------------------|
| `README.md`                   | This guide                                        |
| `shapefile_to_geoparquet.sql` | Standalone SQL workflow                           |
| `shapefile_to_geoparquet.py`  | Same workflow with optional Shapefile seeding     |

## Known limitations

- **Shapefile format**: 10-character DBF field names, ~2 GB per component, sidecar files must stay together.
- **CRS**: Missing `.prj` means unknown CRS — confirm units before interpreting `area_sqm` or joining other layers.
- **Invalid geometry**: `ST_MakeValid` repairs many issues but can change topology; inspect invalid counts in raw before trusting curated output.
- **Read performance**: `ST_Read` through GDAL is not fully parallel — large Shapefiles are slow; convert `source` to GeoParquet once for repeat analytics.
- **GeoParquet read path**: `COPY ... FORMAT PARQUET` writes native DuckDB Parquet with geometry — verify with `read_parquet`, not `ST_Read` (GDAL path). Use QGIS or GeoPandas when you need full GeoParquet metadata checks.
- **Seed data**: Natural Earth countries are not real parcels — use local parcel exports for production pipelines.

## Next steps

- Add a `staging.stg_parcels` cleaning step before curated — see `docs/06_cleaning/spatial_geometry_cleaning.md`
- Run full validation gates — see `notebooks/03_validation_base.ipynb`
- Profile layers interactively — see `notebooks/02_spatial_eda_base.ipynb`

## Related docs

- [Shapefile ingestion](../../docs/03_spatial_ingestion/shapefile.md)
- [Spatial extension setup](../../docs/03_spatial_ingestion/spatial_extension_setup.md)
- [GeoParquet export](../../docs/10_export/geoparquet_export.md)
- [Build curated spatial layer](../../docs/08_spatial_transformation/build_curated_spatial_layer.md)
