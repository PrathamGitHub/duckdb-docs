# GeoJSON Ingestion

Ingest GeoJSON and newline-delimited GeoJSON into the `raw` layer with `ST_Read`, preserving feature geometry and properties as SQL columns.

## Purpose

Load web-friendly vector data (boundaries, points of interest, API responses) into DuckDB for spatial SQL, joins with tabular layers, and export to GeoParquet.

## When to Use

- Open-data portals publish `.geojson` or `.json` FeatureCollections
- REST APIs return GeoJSON you mirror to `data/raw/`
- Lightweight polygon or point layers for maps and spatial EDA

For huge datasets or analytics at scale, convert `source` to GeoParquet and use [geoparquet.md](geoparquet.md).

## Required DuckDB Extension

```sql
INSTALL spatial;
LOAD spatial;
```

For HTTPS `source` URLs:

```sql
INSTALL httpfs;
LOAD httpfs;
```

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Structure | `FeatureCollection` or single `Feature`; nested properties flattened by GDAL |
| CRS | RFC 7946 assumes WGS 84 (`EPSG:4326`); older files may include a `crs` member |
| Path | File path or URL ending in `.geojson` / `.json` |
| Naming | e.g. `raw.raw_boundary_geojson`, `raw.raw_stops_geojson` |
| Size | Very large GeoJSON is slow — prefer GeoParquet for heavy analytics |

## Basic DuckDB SQL

Explore without persisting:

```sql
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read('data/raw/boundary.geojson')
LIMIT 20;
```

Real-world online sample (California boundaries):

```sql
INSTALL httpfs;
LOAD httpfs;
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
LIMIT 10;
```

## Create Raw Spatial Table Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.raw_boundary_geojson AS
SELECT *
FROM ST_Read('data/raw/boundary.geojson');
```

Remote practice table:

```sql
CREATE OR REPLACE TABLE raw.raw_ca_boundary_geojson AS
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
```

## Geometry Column Notes

- Geometry is exposed as `geom` (`GEOMETRY`) for most FeatureCollections.
- Some files nest attributes under a `properties` struct — unnest or alias in `staging`:

```sql
CREATE OR REPLACE TABLE staging.stg_boundary AS
SELECT
  properties.NAME AS name,
  ST_MakeValid(geom) AS geom
FROM raw.raw_boundary_geojson
WHERE geom IS NOT NULL;
```

- Mixed geometry types in one file are allowed; filter by `ST_GeometryType(geom)` in `staging` if you need homogeneous layers.

## CRS Notes

- Modern GeoJSON is WGS 84 lon/lat — verify extent with `ST_Extent(geom)` (expect roughly -180..180, -90..90).
- If coordinates look like meters (values in millions), the file may be mislabeled or use a non-standard CRS — inspect with `ST_Read_Meta`.
- Reproject when joining to projected parcels:

```sql
SELECT ST_Transform(geom, 'EPSG:3857') AS geom_web_mercator
FROM raw.raw_boundary_geojson;
```

## Common Variations

### Flatten nested GeoJSON properties

```sql
SELECT *
FROM ST_Read(
  'data/raw/boundary.geojson',
  open_options := ['FLATTEN_NESTED_ATTRIBUTES=YES']
);
```

### Newline-delimited GeoJSON (GeoJSONSeq)

```sql
CREATE OR REPLACE TABLE raw.raw_events_geojson AS
SELECT *
FROM ST_Read('data/raw/events.ndjson');
```

### Spatial filter at read time

```sql
SELECT *
FROM ST_Read(
  'data/raw/boundary.geojson',
  spatial_filter_box := ST_MakeEnvelope(-124.5, 32.5, -114.0, 42.0)
);
```

### Read properties-only via `json` extension (no geometry)

When you only need attributes from a FeatureCollection file:

```sql
INSTALL json;
LOAD json;

SELECT *
FROM read_json('data/raw/boundary.geojson', format := 'array')
LIMIT 10;
```

Prefer `ST_Read` when geometry is required.

### Notebook usage

```python
GEOJSON_URL = (
    "https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson"
)

con.execute("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial;")

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_ca_boundary_geojson AS
SELECT * FROM ST_Read('{GEOJSON_URL}');
""")

con.sql("""
SELECT ST_GeometryType(geom) AS t, COUNT(*) AS n
FROM raw.raw_ca_boundary_geojson
GROUP BY 1
""").df()
```

## Validation Checks After Ingestion

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_boundary_geojson;

-- Schema
DESCRIBE raw.raw_boundary_geojson;

-- Geometry summary
SELECT
  ST_GeometryType(geom) AS geom_type,
  COUNT(*) AS n
FROM raw.raw_boundary_geojson
GROUP BY 1;

-- Null geometry
SELECT COUNT(*) AS missing_geom
FROM raw.raw_boundary_geojson
WHERE geom IS NULL;

-- Validity
SELECT
  SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom
FROM raw.raw_boundary_geojson;

-- Extent
SELECT ST_Extent(geom) AS bbox FROM raw.raw_boundary_geojson;
```

## Known Limitations

- Large single-file GeoJSON loads entirely through GDAL — memory and speed can be painful; mirror to GeoParquet for repeat analytics.
- Deeply nested `properties` may need `FLATTEN_NESTED_ATTRIBUTES` or manual JSON parsing.
- 3D coordinates are preserved but many workflows flatten to 2D in `staging`.
- GeoJSON does not enforce unique feature IDs — dedupe in `staging` if required.
- Parsing GeoJSON as plain JSON does not produce queryable `GEOMETRY` columns.

## Related Pages

- [Spatial extension setup](spatial_extension_setup.md)
- [Layer inspection](layer_inspection.md)
- [GeoParquet](geoparquet.md)
- [JSON ingestion](../02_ingestion/json.md)
- [Remote files (HTTP / S3)](../02_ingestion/remote_files_http_s3.md)

Official reference: [ST_Read](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read)
