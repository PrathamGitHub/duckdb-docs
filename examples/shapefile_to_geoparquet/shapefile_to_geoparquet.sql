-- shapefile_to_geoparquet.sql
-- Workflow: source → raw → curated → output
-- Run from repository root:
--   duckdb work.duckdb < examples/shapefile_to_geoparquet/shapefile_to_geoparquet.sql

-- =============================================================================
-- Setup
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;

-- Paths are relative to the repository root (current working directory).
-- Input:  data/raw/parcels.shp  (+ .shx, .dbf, .prj sidecars)
-- Output: data/output/geo_parcels.parquet

-- =============================================================================
-- Spatial extension setup
-- =============================================================================

INSTALL spatial;
LOAD spatial;

-- =============================================================================
-- Ingestion — land Shapefile in raw.raw_parcels
-- =============================================================================

CREATE OR REPLACE TABLE raw.raw_parcels AS
SELECT *
FROM ST_Read('data/raw/parcels.shp');

-- =============================================================================
-- Spatial EDA — profile raw geometry before curated build
-- =============================================================================

-- Preview attributes and geometry
SELECT *
FROM raw.raw_parcels
LIMIT 10;

-- Schema
DESCRIBE raw.raw_parcels;

-- Row count
SELECT COUNT(*) AS raw_row_count
FROM raw.raw_parcels;

-- Geometry type distribution
SELECT
  ST_GeometryType(geom) AS geom_type,
  COUNT(*) AS row_count
FROM raw.raw_parcels
GROUP BY 1
ORDER BY row_count DESC;

-- Null and empty geometry check
SELECT
  COUNT(*) AS total_rows,
  COUNT(geom) AS with_geom,
  COUNT(*) - COUNT(geom) AS null_geom,
  SUM(CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END) AS empty_geom
FROM raw.raw_parcels;

-- Invalid geometry check
SELECT
  SUM(CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS invalid_geom,
  SUM(CASE WHEN geom IS NOT NULL AND ST_IsValid(geom) THEN 1 ELSE 0 END) AS valid_geom
FROM raw.raw_parcels;

-- Spatial extent (sanity check for CRS and units)
SELECT ST_Extent(geom) AS bbox
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);

-- =============================================================================
-- Curated spatial layer — repair, measure, conform schema
-- =============================================================================
-- Maps Natural Earth seed columns (OGC_FID, NAME, ISO_A3, CONTINENT) to parcel-like
-- fields. Replace the SELECT list when your Shapefile already has parcel_id,
-- owner_name, zoning_code, and boundary_name.

CREATE OR REPLACE TABLE curated.geo_parcels AS
SELECT
  CAST(OGC_FID AS VARCHAR) AS parcel_id,
  COALESCE(
    NULLIF(TRIM(NAME), ''),
    NULLIF(TRIM(ADMIN), ''),
    'unknown'
  ) AS owner_name,
  COALESCE(NULLIF(TRIM(ISO_A3), ''), 'UNK') AS zoning_code,
  COALESCE(
    NULLIF(TRIM(CONTINENT), ''),
    NULLIF(TRIM(REGION_UN), ''),
    'unknown'
  ) AS boundary_name,
  ST_Area(
    ST_Transform(ST_MakeValid(geom), 'EPSG:4326', 'EPSG:3857')
  ) AS area_sqm,
  ST_MakeValid(geom) AS geom
FROM raw.raw_parcels
WHERE geom IS NOT NULL
  AND NOT ST_IsEmpty(geom);

-- Real parcel Shapefile mapping (replace the CREATE above when your source has
-- parcel attributes):
--
-- CREATE OR REPLACE TABLE curated.geo_parcels AS
-- SELECT
--   CAST(parcel_id AS VARCHAR) AS parcel_id,
--   TRIM(owner_name) AS owner_name,
--   TRIM(zoning_code) AS zoning_code,
--   TRIM(boundary_name) AS boundary_name,
--   ST_Area(ST_Transform(ST_MakeValid(geom), 'EPSG:4326', 'EPSG:3857')) AS area_sqm,
--   ST_MakeValid(geom) AS geom
-- FROM raw.raw_parcels
-- WHERE geom IS NOT NULL
--   AND NOT ST_IsEmpty(geom);

-- =============================================================================
-- Curated QA — block export when checks fail
-- =============================================================================

-- Curated must not be empty
SELECT
  CASE
    WHEN COUNT(*) > 0 THEN 'PASS'
    ELSE 'FAIL'
  END AS curated_not_empty
FROM curated.geo_parcels;

-- No null or empty geometry in curated
SELECT
  COUNT(*) AS rows_with_bad_geom
FROM curated.geo_parcels
WHERE geom IS NULL
   OR ST_IsEmpty(geom);

-- Invalid geometry in curated (0 = pass)
SELECT
  COUNT(*) AS invalid_geom_rows
FROM curated.geo_parcels
WHERE NOT ST_IsValid(geom);

-- Primary key uniqueness (0 duplicate groups = pass)
SELECT
  parcel_id,
  COUNT(*) AS duplicate_count
FROM curated.geo_parcels
GROUP BY parcel_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- Curated extent
SELECT ST_Extent(geom) AS curated_bbox
FROM curated.geo_parcels;

-- Row count reconciliation (curated <= raw; drops expected for null/empty geom)
SELECT
  (SELECT COUNT(*) FROM raw.raw_parcels) AS raw_n,
  (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_n,
  (SELECT COUNT(*) FROM raw.raw_parcels)
    - (SELECT COUNT(*) FROM curated.geo_parcels) AS dropped_rows;

-- =============================================================================
-- Export — write validated curated table to GeoParquet
-- =============================================================================

COPY (
  SELECT
    parcel_id,
    owner_name,
    zoning_code,
    boundary_name,
    area_sqm,
    geom
  FROM curated.geo_parcels
  WHERE geom IS NOT NULL
    AND NOT ST_IsEmpty(geom)
    AND ST_IsValid(geom)
)
TO 'data/output/geo_parcels.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

-- Post-export verification (native Parquet export uses read_parquet)
SELECT
  (SELECT COUNT(*) FROM curated.geo_parcels) AS curated_n,
  (SELECT COUNT(*) FROM read_parquet('data/output/geo_parcels.parquet')) AS parquet_n;

-- Geometry types after round-trip
SELECT DISTINCT ST_GeometryType(geom) AS geom_type
FROM read_parquet('data/output/geo_parcels.parquet');
