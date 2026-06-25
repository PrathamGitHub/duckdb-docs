# Spatial Extent

Compute the bounding box of a spatial layer to verify geographic coverage, detect outliers, and confirm CRS plausibility before joins and export.

## Purpose

Return minimum and maximum coordinates (envelope) for `geom` so analysts and GIS users can confirm the layer covers the expected geography and aligns with sibling layers like `raw.raw_boundary`.

## When to Use

- After ingest on `raw.raw_parcels`, `raw.raw_roads`, or `raw.raw_boundary`
- Before spatial joins — extents should overlap in the same CRS
- When coordinates look wrong (zeros, swapped axes, wrong hemisphere)
- To produce a map viewport or `spatial_filter_box` for subset reads

## Required Extension

```sql
INSTALL spatial;
LOAD spatial;
```

## SQL Template

### Aggregate envelope (`ST_Extent`)

```sql
SELECT
  ST_Extent(geom) AS bbox
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);
```

### Explicit min/max axes (`ST_XMin`, `ST_YMin`, `ST_XMax`, `ST_YMax`)

```sql
SELECT
  ST_XMin(ST_Extent(geom)) AS xmin,
  ST_YMin(ST_Extent(geom)) AS ymin,
  ST_XMax(ST_Extent(geom)) AS xmax,
  ST_YMax(ST_Extent(geom)) AS ymax
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);
```

### Per-layer extent comparison

```sql
SELECT 'parcels' AS layer,
  ST_XMin(ST_Extent(geom)) AS xmin,
  ST_YMin(ST_Extent(geom)) AS ymin,
  ST_XMax(ST_Extent(geom)) AS xmax,
  ST_YMax(ST_Extent(geom)) AS ymax
FROM raw.raw_parcels
WHERE geom IS NOT NULL
UNION ALL
SELECT 'roads',
  ST_XMin(ST_Extent(geom)),
  ST_YMin(ST_Extent(geom)),
  ST_XMax(ST_Extent(geom)),
  ST_YMax(ST_Extent(geom))
FROM raw.raw_roads
WHERE geom IS NOT NULL
UNION ALL
SELECT 'boundary',
  ST_XMin(ST_Extent(geom)),
  ST_YMin(ST_Extent(geom)),
  ST_XMax(ST_Extent(geom)),
  ST_YMax(ST_Extent(geom))
FROM raw.raw_boundary
WHERE geom IS NOT NULL;
```

### Row-level envelope for outlier hunting

```sql
SELECT
  parcel_id,
  ST_XMin(geom) AS xmin,
  ST_YMin(geom) AS ymin,
  ST_XMax(geom) AS xmax,
  ST_YMax(geom) AS ymax
FROM raw.raw_parcels
WHERE geom IS NOT NULL
ORDER BY ST_XMax(geom) - ST_XMin(geom) DESC
LIMIT 20;
```

## Notebook Usage

```python
extent = con.sql("""
  SELECT
    ST_XMin(ST_Extent(geom)) AS xmin,
    ST_YMin(ST_Extent(geom)) AS ymin,
    ST_XMax(ST_Extent(geom)) AS xmax,
    ST_YMax(ST_Extent(geom)) AS ymax
  FROM raw.raw_boundary
  WHERE geom IS NOT NULL
""").df()
extent
```

```python
# Map-ready bbox list [xmin, ymin, xmax, ymax]
row = extent.iloc[0]
bbox = [row.xmin, row.ymin, row.xmax, row.ymax]
bbox
```

Practice dataset:

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_boundary AS
SELECT * FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.sql("""
  SELECT ST_Extent(geom) AS bbox FROM raw.raw_boundary
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_roads` | Layer to measure |
| `geom` | `geom` | Geometry column |
| Filter | `WHERE county = 'King'` | Scoped extent |
| ID column | `parcel_id` | Row-level outlier query |

## Expected Output

**Aggregate (WGS 84 boundary example):**

| xmin | ymin | xmax | ymax |
|------|------|------|------|
| -124.48 | 32.53 | -114.13 | 42.01 |

**`ST_Extent` string form:**

```text
BOX(-124.48 32.53,-114.13 42.01)
```

- **EPSG:4326 (lon/lat):** x ≈ -180..180, y ≈ -90..90
- **Web Mercator / local projected CRS:** large coordinate magnitudes (e.g., millions of meters)

## Interpretation Guidance

- **Extents overlap across layers** — good sign for [spatial join preview](spatial_join_preview.md); if not, check [CRS check](crs_check.md).
- **All zeros or tiny range** — likely missing CRS, null island, or failed ingest.
- **x and y swapped** — sometimes happens when CRS is undefined; y values look like longitudes.
- **One layer extends far beyond boundary** — stray features or wrong projection; use row-level min/max to find IDs.
- **Compare to known admin bounds** — e.g., California lon/lat envelope roughly `-124.5, 32.5, -114.0, 42.0`.

## Common Variations

### Extent by group

```sql
SELECT
  city_name,
  ST_XMin(ST_Extent(geom)) AS xmin,
  ST_YMin(ST_Extent(geom)) AS ymin,
  ST_XMax(ST_Extent(geom)) AS xmax,
  ST_YMax(ST_Extent(geom)) AS ymax
FROM raw.raw_parcels
WHERE geom IS NOT NULL
GROUP BY city_name;
```

### Extent after reprojection

```sql
SELECT ST_Extent(ST_Transform(geom, 'EPSG:4326')) AS bbox_wgs84
FROM raw.raw_parcels
WHERE geom IS NOT NULL;
```

### Read-time spatial filter (large source files)

```sql
SELECT COUNT(*) AS n
FROM ST_Read(
  'data/raw/parcels.shp',
  spatial_filter_box := ST_MakeEnvelope(-122.5, 37.7, -122.3, 37.9)
);
```

Use extent from `raw.raw_boundary` to derive the envelope.

## Known Limitations

- Extent is axis-aligned in the layer's **current** CRS — not equal-area or geodesic bounds.
- `ST_Extent` on geographic CRS is fine for EDA but not for precise distance or area work — reproject for analysis.
- Invalid geometries may still contribute coordinates — pair with [invalid geometry check](invalid_geometry_check.md).
- Empty geometries are excluded from aggregates; NULLs are skipped.

## Related Pages

- [CRS check](crs_check.md)
- [Spatial join preview](spatial_join_preview.md)
- [Layer inspection](../03_spatial_ingestion/layer_inspection.md)

Official reference: [ST_Extent](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_extent) · [ST_XMin](https://duckdb.org/docs/current/core_extensions/spatial/functions.html#st_xmin)
