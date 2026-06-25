# Spatial Performance

Speed up geometry workflows with bounding-box pre-filters, lean column sets, and staging GeoParquet before heavy joins.

## Purpose

Apply performance patterns to Shapefile, GeoJSON, GeoParquet, and ESRI File Geodatabase workflows — where spatial joins, buffers, and intersections dominate runtime.

## Why it matters

Exact spatial predicates (`ST_Intersects`, `ST_Intersection`) are expensive on large layers. A parcel × road join without a study-area filter can produce billions of candidate pairs. Bounding-box pre-filtering eliminates obviously disjoint features before exact tests and is the spatial equivalent of predicate pushdown.

GIS users, analysts, and engineers share the same goal: **reduce geometry work early**, keep layers in GeoParquet for repeat reads, and validate with `EXPLAIN ANALYZE` on representative subsets.

## Recommended pattern

1. Inspect extent with `ST_Extent` in spatial EDA before joins.
2. Define a study-area envelope (bbox) and filter at read or in `staging`.
3. Use `spatial_filter_box` on `ST_Read` when reading shapefiles and compatible sources.
4. Pre-filter with envelope intersection before exact `ST_Intersects`:

   ```sql
   WHERE ST_Intersects(ST_Envelope(a.geom), ST_Envelope(b.geom))
     AND ST_Intersects(a.geom, b.geom)
   ```

5. Keep attribute columns lean — always retain `geom` and join keys only.
6. Export `curated` spatial layers to GeoParquet in `output` for fast re-use.
7. Repair invalid geometry in `staging` before overlays.

```text
source → raw (full layer) → staging (bbox clip, valid geom) → curated (join/clip) → output GeoParquet
```

## Anti-pattern

```sql
-- Full national layer × full national layer
SELECT COUNT(*)
FROM staging.stg_parcels p
JOIN staging.stg_roads r ON ST_Intersects(p.geom, r.geom);

-- ST_Intersection without intersect pre-check
SELECT ST_Intersection(p.geom, r.geom)
FROM staging.stg_parcels p
CROSS JOIN staging.stg_roads r;

-- SELECT * from ST_Read on multi-GB shapefile every cell
SELECT * FROM ST_Read('data/raw/all_parcels.shp');

-- Heavy simplify/buffer on unfiltered national extent
SELECT ST_Buffer(geom, 500) FROM raw.raw_roads_shp;
```

## SQL example

### Bounding-box filter at read time

```sql
INSTALL spatial;
LOAD spatial;

SELECT name, geom
FROM ST_Read(
  'data/raw/ne_110m_admin_0_countries.shp',
  spatial_filter_box := ST_MakeEnvelope(-130, 24, -65, 50)  -- rough CONUS bbox
);
```

### Online GeoJSON — filter to Bay Area bbox in staging

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_ca_regions_bbox AS
SELECT
  properties.NAME AS region_name,
  geom
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
)
WHERE ST_Intersects(
  geom,
  ST_MakeEnvelope(-122.52, 37.70, -122.35, 37.84)
);
```

### Envelope pre-filter before spatial join

```sql
SELECT
  p.parcel_id,
  r.road_name
FROM staging.stg_parcels p
JOIN staging.stg_roads r
  ON ST_Intersects(ST_Envelope(p.geom), ST_Envelope(r.geom))
 AND ST_Intersects(p.geom, r.geom);
```

### Write staging GeoParquet for repeat analytics

```sql
COPY (
  SELECT region_name, geom
  FROM staging.stg_ca_regions_bbox
) TO 'data/staging/stg_ca_regions_bbox.parquet'
(FORMAT PARQUET);
```

### EXPLAIN on bbox-filtered read

```sql
EXPLAIN
SELECT region_name
FROM staging.stg_ca_regions_bbox;
```

### EXPLAIN ANALYZE on filtered spatial join (use sample in dev)

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM (
  SELECT geom FROM staging.stg_parcels USING SAMPLE 1%
) p
JOIN staging.stg_boundary b
  ON ST_Intersects(ST_Envelope(p.geom), ST_Envelope(b.geom))
 AND ST_Intersects(p.geom, b.geom);
```

## Notebook usage

```python
con.execute("INSTALL spatial; LOAD spatial;")
con.execute("INSTALL httpfs; LOAD httpfs;")

BAY_AREA = "ST_MakeEnvelope(-122.52, 37.70, -122.35, 37.84)"
GEOJSON_URL = (
  "https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson"
)

# raw ingest (full layer for audit)
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_ca_regions_geojson AS
SELECT * FROM ST_Read('{GEOJSON_URL}');
""")

# staging with bbox pre-filter
con.execute(f"""
CREATE OR REPLACE TABLE staging.stg_ca_regions_bbox AS
SELECT
  properties.NAME AS region_name,
  geom
FROM raw.raw_ca_regions_geojson
WHERE ST_Intersects(geom, {BAY_AREA});
""")

# Extent check
con.sql("""
SELECT
  COUNT(*) AS features,
  ST_Extent(geom) AS bbox
FROM staging.stg_ca_regions_bbox
""").df()

# Optional: persist staging GeoParquet
con.execute("""
COPY staging.stg_ca_regions_bbox
TO 'data/staging/stg_ca_regions_bbox.parquet'
(FORMAT PARQUET);
""")
```

Download Natural Earth countries for local bbox practice:

```python
import urllib.request

url = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"
dest = RAW_DIR / "ne_110m_countries.zip"
if not dest.exists():
    urllib.request.urlretrieve(url, dest)

con.execute(f"""
CREATE OR REPLACE TABLE staging.stg_countries_us AS
SELECT NAME, geom
FROM ST_Read('{dest.as_posix()}')
WHERE ST_Intersects(geom, ST_MakeEnvelope(-130, 24, -65, 50));
""")
```

## Common variations

### `ST_Read` with `spatial_filter_box` on local shapefile

```sql
SELECT parcel_id, geom
FROM ST_Read(
  'data/raw/parcels.shp',
  spatial_filter_box := ST_MakeEnvelope(-122.52, 37.70, -122.35, 37.84)
);
```

### Clip to single boundary polygon (study area)

```sql
SELECT
  p.parcel_id,
  ST_Intersection(p.geom, b.geom) AS geom
FROM staging.stg_parcels p
JOIN staging.stg_boundary b
  ON ST_Intersects(ST_Envelope(p.geom), ST_Envelope(b.geom))
 AND ST_Intersects(p.geom, b.geom);
```

### GeoParquet ingest (preferred for repeat reads)

```sql
CREATE TABLE staging.stg_roads AS
SELECT road_id, road_name, geom
FROM ST_Read('data/staging/stg_roads.parquet');
```

### FileGDB layer with attribute filter + bbox

```sql
SELECT *
FROM ST_Read(
  'data/raw/city.gdb',
  layer := 'Parcels',
  spatial_filter_box := ST_MakeEnvelope(500000, 4000000, 600000, 4100000)
)
WHERE zoning = 'R1';
```

### Simplify before web export (reduce vertex load)

```sql
SELECT
  region_name,
  ST_SimplifyPreserveTopology(geom, 0.01) AS geom
FROM staging.stg_ca_regions_bbox;
```

## Practical notes

- **CRS matters:** Bbox coordinates must match geometry CRS — reproject with `ST_Transform` when mixing WGS 84 and projected units.
- **Envelope is conservative:** `ST_Intersects(envelope, envelope)` may admit false positives; always follow with exact predicate when correctness requires it.
- **EDA first:** Run [spatial extent](../05_spatial_eda/spatial_extent.md) before choosing a bbox.
- **Many-to-many joins:** Parcel × road intersections explode row counts — use `LIMIT`, samples, or `max_search_radius` patterns in EDA.
- **Format choice:** GeoParquet in `staging`/`output` beats re-reading Shapefile or GeoJSON for repeated analytics.
- **Pair with tabular patterns:** Combine bbox filters with [column selection](column_selection.md) and [memory management](memory_management.md).

## Known limitations

- `spatial_filter_box` support depends on GDAL driver and file format — verify on your layer with a small `EXPLAIN ANALYZE` or row-count check.
- GeoJSON and single-file formats may still decode more data than ideal — prefer GeoParquet for large repeat workloads.
- Envelope pre-filter does not replace spatial indexes for national-scale many-to-many joins — consider tiling or pre-clipping to study area tables.
- `ST_Intersection` output can be invalid or empty for edge cases — validate in [spatial validity check](../09_validation/spatial_validity_check.md).
- Remote spatial URLs re-download on each ingest — cache to `data/raw/` for practice runs.

## Related Pages

- [Shapefile ingestion](../03_spatial_ingestion/shapefile.md) — `spatial_filter_box`
- [GeoParquet ingestion](../03_spatial_ingestion/geoparquet.md)
- [Spatial join](../08_spatial_transformation/spatial_join.md)
- [Clip / intersection](../08_spatial_transformation/clip_intersection.md)
- [Predicate pushdown](predicate_pushdown.md)

Official reference: [DuckDB spatial extension](https://duckdb.org/docs/current/core_extensions/spatial/overview.html)
