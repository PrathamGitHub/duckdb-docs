# Spatial Layer Inspection

Inspect spatial files **before** full ingest: list layers, geometry types, CRS, field names, and row counts. Use this step to avoid loading the wrong feature class or mixing incompatible projections.

## Purpose

Produce a layer inventory report for Shapefile, GeoJSON, GeoParquet, and FileGDB `source` files so notebook workflows can target the correct `layer` argument and `raw.raw_*` table names.

## When to Use

- First contact with an unfamiliar `.gdb` or multi-layer `.gpkg`
- Vendor delivers many layers — only some belong in `raw`
- CRS is undocumented or suspicious
- You need a quick feature count before a heavy `CREATE TABLE`

Run inspection in the **source → raw** notebook section, immediately after [spatial extension setup](spatial_extension_setup.md).

## Required DuckDB Extension

```sql
INSTALL spatial;
LOAD spatial;
```

Optional for remote files:

```sql
INSTALL httpfs;
LOAD httpfs;
```

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| File readable | GDAL driver available — check `ST_Drivers()` |
| Path | Local `data/raw/...` or HTTPS URL |
| FileGDB | Folder path `data/raw/project.gdb` |
| Output | Inventory stays in notebook / temp views — not a workflow layer |

## Basic DuckDB SQL

### Available GDAL drivers

```sql
SELECT short_name, long_name, can_open, can_create
FROM ST_Drivers()
ORDER BY short_name;
```

### File metadata (`ST_Read_Meta`)

```sql
SELECT *
FROM ST_Read_Meta('data/raw/project.gdb');
```

Unnest layer names from a multi-layer file:

```sql
SELECT
  unnest(layers).name AS layer_name,
  unnest(layers).feature_count AS feature_count,
  unnest(layers).geometry_fields[1].type AS geom_type
FROM ST_Read_Meta('data/raw/project.gdb');
```

### CRS for first geometry field

```sql
SELECT
  layers[1].name AS layer_name,
  layers[1].geometry_fields[1].crs.auth_name AS crs_auth,
  layers[1].geometry_fields[1].crs.auth_code AS epsg_code
FROM ST_Read_Meta('data/raw/boundary.geojson');
```

### Preview features (small sample)

```sql
SELECT *
FROM ST_Read('data/raw/parcels.shp')
LIMIT 5;
```

```sql
SELECT *
FROM ST_Read('data/raw/project.gdb', layer := 'Parcels')
LIMIT 5;
```

## Create Raw Spatial Table Pattern

Inspection does **not** replace `raw` ingest — it informs it. After choosing a layer:

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_parcels_gdb AS
SELECT *
FROM ST_Read('data/raw/project.gdb', layer := 'Parcels');
```

Optional: persist inventory as a scratch table for the notebook session:

```sql
CREATE OR REPLACE TABLE staging.stg_spatial_inventory AS
SELECT
  'data/raw/project.gdb' AS source_path,
  unnest(layers).name AS layer_name,
  unnest(layers).feature_count AS feature_count,
  unnest(layers).geometry_fields[1].type AS geom_type,
  unnest(layers).geometry_fields[1].crs.auth_name AS crs_auth,
  unnest(layers).geometry_fields[1].crs.auth_code AS epsg_code
FROM ST_Read_Meta('data/raw/project.gdb');
```

## Geometry Column Notes

- `ST_Read_Meta` reports geometry field names and types per layer — compare to `DESCRIBE` after preview.
- Preview with `LIMIT` to confirm `geom` is populated and not empty (`ST_IsEmpty`).
- For GeoParquet opened via `read_parquet`, geometry may be WKB — check `typeof(geometry)` before spatial predicates.

## CRS Notes

- Prefer metadata CRS over guessing from coordinate magnitude.
- When `auth_code` is present, use `EPSG:{code}` in `ST_Transform`.
- Missing CRS in metadata + lon/lat-like extent → treat as `EPSG:4326` only after manual confirmation.
- Mixed CRS across layers in one `.gdb` is common — inspect **per layer**, not per file.

## Common Variations

### Shapefile (single layer)

```sql
SELECT
  layers[1].name AS layer_name,
  layers[1].feature_count,
  layers[1].geometry_fields[1].type AS geom_type
FROM ST_Read_Meta('data/raw/parcels.shp');
```

### GeoJSON

```sql
SELECT
  layers[1].feature_count,
  ST_GeometryType(geom) AS geom_type,
  COUNT(*) AS n
FROM ST_Read('data/raw/boundary.geojson')
GROUP BY 1, 2;
```

### GeoParquet — schema vs spatial metadata

```sql
-- Column names and types
DESCRIBE SELECT * FROM read_parquet('data/raw/roads.geoparquet');

-- GeoParquet CRS
SELECT
  layers[1].geometry_fields[1].crs.auth_name,
  layers[1].geometry_fields[1].crs.auth_code
FROM ST_Read_Meta('data/raw/roads.geoparquet');
```

### FileGDB — try layer index

Layer name or zero-based index:

```sql
SELECT * FROM ST_Read('data/raw/project.gdb', layer := '0') LIMIT 5;
```

### Online GeoJSON practice

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT layers
FROM ST_Read_Meta(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
```

### External inventory when `ST_Read_Meta` fails (FileGDB)

Use system GDAL:

```bash
ogrinfo -al -so data/raw/project.gdb
```

JSON layer list:

```bash
ogrinfo -q -json data/raw/project.gdb | head -80
```

Document the chosen layer name in the notebook before `CREATE TABLE raw.raw_*`.

### Notebook helper pattern

```python
def inspect_spatial(path: str) -> None:
    meta = con.sql("SELECT * FROM ST_Read_Meta(?)", params=[path]).df()
    preview = con.sql("SELECT * FROM ST_Read(?) LIMIT 3", params=[path]).df()
    display(meta)
    display(preview)

inspect_spatial("data/raw/boundary.geojson")
```

## Validation Checks After Inspection

Before promoting to full `raw` load:

```sql
-- Expected layer exists (GDB)
SELECT COUNT(*) AS layer_found
FROM (
  SELECT unnest(layers).name AS layer_name
  FROM ST_Read_Meta('data/raw/project.gdb')
) WHERE layer_name = 'Parcels';

-- Preview row count order-of-magnitude
SELECT COUNT(*) AS preview_count
FROM ST_Read('data/raw/project.gdb', layer := 'Parcels')
LIMIT 1000000;

-- Geometry type singleton check
SELECT ST_GeometryType(geom) AS t, COUNT(*) AS n
FROM ST_Read('data/raw/parcels.shp')
GROUP BY 1;

-- CRS sanity via extent
SELECT ST_Extent(geom) AS bbox
FROM ST_Read('data/raw/boundary.geojson');
```

## Known Limitations

- `ST_Read_Meta` structures are nested — use `UNNEST` or notebook display for readability.
- Feature counts in metadata may be approximate for some drivers — confirm with `COUNT(*)` on small layers.
- Failed metadata on corrupt or unsupported GDB — fall back to `ogrinfo`.
- `read_parquet` metadata alone does not list "layers" — GeoParquet is single-table.
- Inspection queries still invoke GDAL — huge files need `LIMIT` or `spatial_filter_box` on preview.

## Related Pages

- [Spatial extension setup](spatial_extension_setup.md)
- [ESRI File Geodatabase](esri_file_geodatabase.md)
- [Shapefile](shapefile.md)
- [GeoJSON](geojson.md)
- [GeoParquet](geoparquet.md)

Official reference: [ST_Read_Meta](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read_meta) · [ST_Drivers](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_drivers)
