# Shapefile Ingestion

Ingest ESRI Shapefile (`.shp` plus sidecar files) into the `raw` layer using the `spatial` extension and GDAL's Shapefile driver.

## Purpose

Load polygon, line, or point features from the most common GIS exchange format into DuckDB for SQL-based cleaning, spatial joins, and export to GeoParquet or GeoJSON.

## When to Use

- Vendor or government data ships as `.shp` (parcels, zoning, roads, utilities)
- You have a local mirror under `data/raw/` or a zip URL from open data
- You need the full attribute table (`.dbf`) alongside geometry

Prefer **GeoParquet** for large analytics-only pipelines; use Shapefile when that is what the `source` provides.

## Required DuckDB Extension

```sql
INSTALL spatial;
LOAD spatial;
```

For zip or HTTPS sources:

```sql
INSTALL httpfs;
LOAD httpfs;
```

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Sidecar files | `.shx` and `.dbf` required; `.prj` strongly recommended for CRS |
| Encoding | `.cpg` may define DBF text encoding — garbled text lands in `raw`, fix in `staging` |
| Path | Point `ST_Read` at the `.shp` file, not the folder |
| Layer | Single layer per basename — one `.shp` = one layer |
| Naming | e.g. `raw.raw_parcels_shp`, `raw.raw_roads_shp` |

## Basic DuckDB SQL

Explore without persisting:

```sql
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read('data/raw/parcels.shp')
LIMIT 20;
```

Real-world online sample (Natural Earth countries, zipped Shapefile):

```sql
INSTALL httpfs;
LOAD httpfs;
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read(
  'https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip'
)
LIMIT 10;
```

## Create Raw Spatial Table Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_parcels_shp AS
SELECT *
FROM ST_Read('data/raw/parcels.shp');
```

Snapshot online data for repeatable practice notebooks:

```sql
CREATE OR REPLACE TABLE raw.raw_countries_shp AS
SELECT *
FROM ST_Read(
  'https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip'
);
```

## Geometry Column Notes

- GDAL exposes geometry as `geom` (`GEOMETRY` type) unless `keep_wkb := true`.
- Geometry type follows the Shapefile (point / line / polygon / multipolygon).
- Invalid or self-intersecting polygons are common — repair in `staging` with `ST_MakeValid(geom)`.
- Z/M values may be present; use `ST_Force2D(geom)` when you only need 2D analysis.

## CRS Notes

- CRS usually comes from the companion `.prj` file beside the `.shp`.
- Missing `.prj` means unknown CRS — do not spatial-join until you confirm units and projection.
- Inspect CRS before ingest: [layer inspection](layer_inspection.md).
- Reproject in `staging` when combining with WGS 84 web data:

```sql
SELECT ST_Transform(geom, 'EPSG:4326') AS geom
FROM raw.raw_parcels_shp;
```

## Common Variations

### Glob multiple Shapefiles

```sql
CREATE OR REPLACE TABLE raw.raw_parcels_shp AS
SELECT *, filename AS source_file
FROM ST_Read('data/raw/parcels/*.shp');
```

All sidecar files must exist for each basename in the folder.

### Read from zip (local or URL)

```sql
CREATE OR REPLACE TABLE raw.raw_counties_shp AS
SELECT *
FROM ST_Read('data/raw/counties.zip');
```

### Bounding-box filter at read time

```sql
SELECT *
FROM ST_Read(
  'data/raw/parcels.shp',
  spatial_filter_box := ST_MakeEnvelope(-122.52, 37.70, -122.35, 37.84)
);
```

### Native Shapefile reader (no GDAL)

For simple `.shp` without full GDAL stack, DuckDB also offers `ST_ReadSHP` — fewer format options, no zip:

```sql
SELECT * FROM ST_ReadSHP('data/raw/parcels.shp') LIMIT 10;
```

Prefer `ST_Read` for zip, mixed folders, and consistent behavior with other formats.

### Notebook: download then ingest

```python
import urllib.request

url = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
dest = RAW_DIR / "ne_110m_countries.zip"
if not dest.exists():
    urllib.request.urlretrieve(url, dest)

con.execute("""
CREATE OR REPLACE TABLE raw.raw_countries_shp AS
SELECT * FROM ST_Read(?);
""", [dest.as_posix()])
```

## Validation Checks After Ingestion

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_parcels_shp;

-- Schema
DESCRIBE raw.raw_parcels_shp;

-- Geometry types
SELECT ST_GeometryType(geom) AS geom_type, COUNT(*) AS n
FROM raw.raw_parcels_shp
GROUP BY 1;

-- Null / empty geometry
SELECT
  COUNT(*) AS total,
  COUNT(geom) AS with_geom,
  SUM(CASE WHEN ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS empty_geom
FROM raw.raw_parcels_shp;

-- Validity
SELECT
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM raw.raw_parcels_shp;

-- Extent (sanity check for CRS/units)
SELECT ST_Extent(geom) AS bbox FROM raw.raw_parcels_shp;
```

## Known Limitations

- **10-character field name limit** in DBF — truncated columns arrive in `raw`; rename in `staging`.
- **2 GB size limit** per Shapefile component — large datasets need GeoParquet or FileGDB upstream.
- Broken sidecar pairs (missing `.shx` or `.dbf`) cause read failures.
- Multipatch and some curve types may not round-trip cleanly.
- `ST_Read` through GDAL is not fully parallel — very large shapefiles can be slow; consider converting `source` to GeoParquet once.
- Character encoding issues require `.cpg` or manual encoding fixes in `staging`.

## Related Pages

- [Spatial extension setup](spatial_extension_setup.md)
- [Layer inspection](layer_inspection.md)
- [GeoParquet](geoparquet.md) — preferred for large analytics
- [Folders and globs](../02_ingestion/folders_and_globs.md)

Official reference: [ST_Read](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
