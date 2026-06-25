# ESRI File Geodatabase Ingestion

Ingest ESRI File Geodatabase (`.gdb` folder) layers into the `raw` schema using DuckDB's `spatial` extension and GDAL's **OpenFileGDB** driver.

## Purpose

Read multi-layer enterprise GIS drops (zoning, utilities, parcels, annotation) into SQL tables for notebook-first ETL without ArcGIS desktop automation.

## When to Use

- City, county, or utility vendors deliver `.gdb` directories
- One `source` contains many feature classes you ingest layer by layer
- Attributes include domain-coded fields you will decode in `staging`

Convert to GeoParquet in `output` when downstream consumers do not use FileGDB.

## Required DuckDB Extension

```sql
INSTALL spatial;
LOAD spatial;
```

**Driver dependency:** FileGDB support depends on GDAL drivers bundled with your DuckDB `spatial` extension environment. Confirm before planning ingest:

```sql
SELECT short_name, long_name, can_open
FROM ST_Drivers()
WHERE short_name IN ('OpenFileGDB', 'FileGDB');
```

`OpenFileGDB` is the usual read driver in bundled GDAL. Esri's proprietary **FileGDB** driver (write-heavy, SDK-based) may not be present.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Path | Pass the **folder** path ending in `.gdb`, not an internal `.gdbtable` file |
| Multi-layer | One `raw` table per feature class; use `layer := 'LayerName'` |
| Layer names | Case-sensitive; inspect with `ST_Read_Meta` or `ogrinfo` first |
| Domains | Coded value domains appear as integers in `raw` — decode in `staging` |
| Naming | e.g. `raw.raw_parcels_gdb`, `raw.raw_zoning_gdb` |

## Basic DuckDB SQL

List layers and CRS before loading — see [layer inspection](layer_inspection.md).

Explore one layer without persisting:

```sql
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read('data/raw/project.gdb', layer := 'Parcels')
LIMIT 20;
```

Default first layer (when unnamed):

```sql
SELECT *
FROM ST_Read('data/raw/project.gdb')
LIMIT 10;
```

## Create Raw Spatial Table Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_parcels_gdb AS
SELECT *
FROM ST_Read('data/raw/project.gdb', layer := 'Parcels');
```

Ingest multiple layers in a notebook loop:

```python
layers = ["Parcels", "Zoning", "RoadCenterlines"]

for layer in layers:
    table = f"raw.raw_{layer.lower()}_gdb"
    con.execute(f"""
    CREATE OR REPLACE TABLE {table} AS
    SELECT * FROM ST_Read('data/raw/project.gdb', layer := ?);
    """, [layer])
```

## Geometry Column Notes

- Each feature class yields `geom` plus attribute columns.
- Mixed geometry types per class are rare but possible — group by `ST_GeometryType(geom)` in validation.
- Annotation and relationship classes may not read as expected vector layers — inspect metadata first.
- Repair in `staging`: `ST_MakeValid(geom) AS geom`.

## CRS Notes

- CRS is stored per feature class in GDB metadata.
- Inspect before joining other layers:

```sql
SELECT
  layers[1].name AS layer_name,
  layers[1].geometry_fields[1].crs.auth_name AS auth,
  layers[1].geometry_fields[1].crs.auth_code AS epsg
FROM ST_Read_Meta('data/raw/project.gdb');
```

- Reproject in `staging` when mixing state-plane GDB data with WGS 84 boundaries.

## Common Variations

### Restrict to OpenFileGDB driver

```sql
SELECT *
FROM ST_Read(
  'data/raw/project.gdb',
  layer := 'Parcels',
  allowed_drivers := ['OpenFileGDB']
);
```

### Sequential layer scan (some drivers)

```sql
SELECT *
FROM ST_Read(
  'data/raw/project.gdb',
  layer := 'Parcels',
  sequential_layer_scan := true
);
```

### Spatial filter while reading

```sql
SELECT *
FROM ST_Read(
  'data/raw/project.gdb',
  layer := 'Parcels',
  spatial_filter_box := ST_MakeEnvelope(500000, 4000000, 600000, 4100000)
);
```

Adjust envelope to layer CRS.

### Practice data

Many open-data portals publish FileGDB downloads (city parcels, zoning). Download the `.gdb` folder into `data/raw/project.gdb` — the directory must keep Esri's internal structure intact.

```text
data/raw/project.gdb/
  ├── gdb/ ...
  └── *.gdbtable / *.gdbtablx / ...
```

Do not zip-unzip in ways that strip subfolders.

## Fallback: `ogrinfo` and `ogr2ogr`

When `ST_Read` fails (unsupported GDB version, missing driver, or corporate `.gdb` created with newer ArcGIS), use system **GDAL/OGR** tools and land a friendlier format in `data/raw/`.

### Inspect layers and CRS

```bash
ogrinfo -al -so data/raw/project.gdb
```

List layer names only:

```bash
ogrinfo -q -json data/raw/project.gdb
```

### Convert one layer to GeoParquet for DuckDB

```bash
ogr2ogr -f Parquet data/raw/parcels_from_gdb.parquet \
  data/raw/project.gdb Parcels \
  -lco GEOMETRY_NAME=geom
```

Then ingest in DuckDB:

```sql
INSTALL spatial;
LOAD spatial;

CREATE OR REPLACE TABLE raw.raw_parcels_gdb AS
SELECT * FROM ST_Read('data/raw/parcels_from_gdb.parquet');
```

### Convert to GeoJSON (smaller layers)

```bash
ogr2ogr -f GeoJSON data/raw/zoning_from_gdb.geojson \
  data/raw/project.gdb Zoning
```

### Convert entire GDB to Shapefile (per layer)

```bash
mkdir -p data/raw/gdb_export
ogr2ogr -f "ESRI Shapefile" data/raw/gdb_export data/raw/project.gdb
```

**Workflow convention:** `ogr2ogr` output is a new **source** file under `data/raw/` → ingest to `raw` with `ST_Read` → continue `staging` → `curated` → `output`.

## Validation Checks After Ingestion

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_parcels_gdb;

-- Schema
DESCRIBE raw.raw_parcels_gdb;

-- Geometry types
SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM raw.raw_parcels_gdb
GROUP BY 1;

-- Null / invalid geometry
SELECT
  COUNT(*) AS total,
  COUNT(geom) AS with_geom,
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM raw.raw_parcels_gdb;

-- Extent
SELECT ST_Extent(geom) AS bbox FROM raw.raw_parcels_gdb;

-- Compare to ogrinfo feature count (manual check)
```

## Known Limitations

- **Driver availability** — bundled `OpenFileGDB` may not support every ArcGIS Pro version; newer geodatabases may require `ogr2ogr` with a newer system GDAL or Esri SDK driver.
- **Read-only** — DuckDB ingests; writing back to FileGDB via GDAL is limited and not the focus of this repo.
- **Large GDBs** — full layer scans can be slow and memory-heavy; use spatial filters or pre-export with `ogr2ogr`.
- **Domains and subtypes** — appear as raw codes in DuckDB; decode with lookup tables in `staging`.
- **Relationship classes / attachments** — not imported as relational tables by `ST_Read`.
- **Network paths** — prefer copying `.gdb` to local `data/raw/` before ingest.

## Related Pages

- [Spatial extension setup](spatial_extension_setup.md)
- [Layer inspection](layer_inspection.md)
- [GeoParquet](geoparquet.md)
- [Shapefile](shapefile.md)

Official reference: [GDAL OpenFileGDB](https://gdal.org/en/stable/drivers/vector/openfilegdb.html) · [ST_Read](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
