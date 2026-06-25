# CRS Check

Inspect coordinate reference system (CRS) metadata and coordinate plausibility so layers like `raw.raw_parcels`, `raw.raw_roads`, and `raw.raw_boundary` can be joined and measured in a common projection.

## Purpose

Document whether each layer has a defined CRS, whether extents look consistent with that CRS, and whether sibling layers agree — before `ST_Transform` in `staging` or spatial overlays in `curated`.

## When to Use

- After ingest when `.prj`, GeoParquet metadata, or GDB layer CRS is unknown
- Before mixing layers from different vendors (parcels vs roads vs boundary)
- When [spatial extent](spatial_extent.md) shows implausible coordinates
- Before [area / length summary](area_length_summary.md) — units depend on CRS

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

Optional for online `source` files:

```sql
INSTALL httpfs;
LOAD httpfs;
```

## SQL Template

### CRS from file metadata (`ST_Read_Meta`)

Run against the **source path** (not always stored on the DuckDB table):

```sql
SELECT
  layers[1].name AS layer_name,
  layers[1].geometry_fields[1].crs.auth_name AS crs_auth,
  layers[1].geometry_fields[1].crs.auth_code AS epsg_code,
  layers[1].geometry_fields[1].crs.proj4text AS proj4
FROM ST_Read_Meta('data/raw/boundary.geojson');
```

Multi-layer FileGDB:

```sql
SELECT
  unnest(layers).name AS layer_name,
  unnest(layers).geometry_fields[1].crs.auth_name AS crs_auth,
  unnest(layers).geometry_fields[1].crs.auth_code AS epsg_code
FROM ST_Read_Meta('data/raw/project.gdb');
```

### SRID on ingested table (`ST_SRID`)

```sql
SELECT
  'raw_parcels' AS table_name,
  MIN(ST_SRID(geom)) AS min_srid,
  MAX(ST_SRID(geom)) AS max_srid,
  COUNT(DISTINCT ST_SRID(geom)) AS distinct_srid
FROM raw.raw_parcels
WHERE geom IS NOT NULL
UNION ALL
SELECT 'raw_roads', MIN(ST_SRID(geom)), MAX(ST_SRID(geom)), COUNT(DISTINCT ST_SRID(geom))
FROM raw.raw_roads
WHERE geom IS NOT NULL
UNION ALL
SELECT 'raw_boundary', MIN(ST_SRID(geom)), MAX(ST_SRID(geom)), COUNT(DISTINCT ST_SRID(geom))
FROM raw.raw_boundary
WHERE geom IS NOT NULL;
```

### Extent plausibility (lon/lat vs projected)

```sql
SELECT
  'raw_boundary' AS layer,
  ST_XMin(ST_Extent(geom)) AS xmin,
  ST_YMin(ST_Extent(geom)) AS ymin,
  ST_XMax(ST_Extent(geom)) AS xmax,
  ST_YMax(ST_Extent(geom)) AS ymax,
  CASE
    WHEN ST_XMin(ST_Extent(geom)) BETWEEN -180 AND 180
     AND ST_YMin(ST_Extent(geom)) BETWEEN -90 AND 90
     AND ST_XMax(ST_Extent(geom)) BETWEEN -180 AND 180
     AND ST_YMax(ST_Extent(geom)) BETWEEN -90 AND 90
    THEN 'likely_geographic_degrees'
    ELSE 'likely_projected_or_check_crs'
  END AS extent_hint
FROM raw.raw_boundary
WHERE geom IS NOT NULL;
```

### Transform smoke test (layers align after reprojection)

```sql
SELECT
  ST_XMin(ST_Extent(ST_Transform(p.geom, 'EPSG:4326'))) AS parcels_xmin,
  ST_YMin(ST_Extent(ST_Transform(p.geom, 'EPSG:4326'))) AS parcels_ymin,
  ST_XMax(ST_Extent(ST_Transform(p.geom, 'EPSG:4326'))) AS parcels_xmax,
  ST_YMax(ST_Extent(ST_Transform(p.geom, 'EPSG:4326'))) AS parcels_ymax,
  ST_XMin(ST_Extent(ST_Transform(b.geom, 'EPSG:4326'))) AS boundary_xmin,
  ST_YMin(ST_Extent(ST_Transform(b.geom, 'EPSG:4326'))) AS boundary_ymin,
  ST_XMax(ST_Extent(ST_Transform(b.geom, 'EPSG:4326'))) AS boundary_xmax,
  ST_YMax(ST_Extent(ST_Transform(b.geom, 'EPSG:4326'))) AS boundary_ymax
FROM raw.raw_parcels p
CROSS JOIN raw.raw_boundary b
WHERE p.geom IS NOT NULL AND b.geom IS NOT NULL;
```

## Notebook Usage

```python
# Metadata CRS from source file
meta = con.sql("""
  SELECT
    layers[1].geometry_fields[1].crs.auth_name AS crs_auth,
    layers[1].geometry_fields[1].crs.auth_code AS epsg_code
  FROM ST_Read_Meta('data/raw/parcels.shp')
""").df()
meta
```

```python
# SRID on loaded tables
display(con.sql("""
  SELECT 'parcels' AS layer, MIN(ST_SRID(geom)) AS srid FROM raw.raw_parcels
  UNION ALL SELECT 'roads', MIN(ST_SRID(geom)) FROM raw.raw_roads
  UNION ALL SELECT 'boundary', MIN(ST_SRID(geom)) FROM raw.raw_boundary
""").df())
```

Practice with online GeoJSON (typically WGS 84):

```python
URL = "https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson"

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_boundary AS
SELECT * FROM ST_Read('{URL}');
""")

con.sql(f"""
  SELECT layers[1].geometry_fields[1].crs.auth_code AS epsg
  FROM ST_Read_Meta('{URL}')
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Source path | `data/raw/parcels.shp` | For `ST_Read_Meta` |
| `{schema}.{table}` | `raw.raw_roads` | For `ST_SRID` / extent |
| Target CRS | `'EPSG:4326'`, `'EPSG:3857'` | Transform smoke tests |
| Layer name (GDB) | `'Parcels'` | Per-layer CRS in multi-layer files |

## Expected Output

**Metadata:**

| layer_name | crs_auth | epsg_code |
|------------|----------|-----------|
| boundary | EPSG | 4326 |

**SRID on table:**

| table_name | min_srid | max_srid | distinct_srid |
|------------|----------|----------|---------------|
| raw_parcels | 4326 | 4326 | 1 |
| raw_roads | 4326 | 4326 | 1 |
| raw_boundary | 4326 | 4326 | 1 |

**Red flags:** `distinct_srid > 1`, `min_srid = 0` or NULL SRID, metadata EPSG ≠ extent plausibility.

## Interpretation Guidance

- **Consistent EPSG across layers** — reproject only if business rules require a different analysis CRS.
- **SRID 0 or missing** — geometry may still plot "correctly" in some tools; set CRS in `staging` via `ST_SetSRID` after confirming with metadata and extent.
- **Geographic degrees on local parcel data** — often wrong — local government data is usually a state plane or UTM zone (projected meters).
- **Metadata vs table SRID mismatch** — trust file metadata and extent; re-ingest with `ST_Read` if WKB path dropped SRID.
- **Transform smoke test** — if extents overlap in `EPSG:4326` but not in native CRS, layers use different projections — standardize in `staging`.

## Common Variations

### Persist target CRS in staging

```sql
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT
  parcel_id,
  ST_Transform(geom, 'EPSG:4326') AS geom,
  4326 AS crs_epsg
FROM raw.raw_parcels
WHERE geom IS NOT NULL;
```

### Document CRS in a notebook column when ambiguous

```sql
ALTER TABLE staging.stg_parcels ADD COLUMN crs_epsg INTEGER DEFAULT 4326;
```

### Compare metadata CRS for all ingest paths

```python
sources = {
    "parcels": "data/raw/parcels.shp",
    "roads": "data/raw/roads.geoparquet",
    "boundary": "data/raw/boundary.geojson",
}
for name, path in sources.items():
    epsg = con.sql(f"""
      SELECT layers[1].geometry_fields[1].crs.auth_code AS epsg
      FROM ST_Read_Meta('{path}')
    """).df()
    print(name, epsg)
```

## Known Limitations

- CRS on DuckDB tables is not always persisted the same way as in GDAL files — always keep source path and `ST_Read_Meta` in the notebook.
- `ST_SRID` returns 0 when unset; does not replace full PROJ metadata.
- Assumed `EPSG:4326` for lon/lat extent is a **heuristic** — confirm with metadata and domain knowledge.
- Mixed CRS within one table is rare but possible — `COUNT(DISTINCT ST_SRID(geom))` surfaces it.
- Reprojection of invalid geometry can fail — run [invalid geometry check](invalid_geometry_check.md) first.

## Related Pages

- [Spatial extent](spatial_extent.md)
- [Layer inspection](../03_spatial_ingestion/layer_inspection.md)
- [Spatial extension setup](../03_spatial_ingestion/spatial_extension_setup.md)

Official reference: [ST_Read_Meta](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_read_meta) · [ST_Transform](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_transform) · [ST_SRID](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_srid)
