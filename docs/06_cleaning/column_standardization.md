# Column Standardization

Rename, reorder, and alias columns from `raw` to a consistent `staging` schema for joins and exports.

## Purpose

Map vendor-specific column names (`OWNER_NM`, `Shape_Area`, `POP2010`) to project conventions (`owner_name`, `shape_area_sqft`, `population_2010`) so SQL templates and notebooks stay readable across datasets.

## When to Use

- After ingest when source headers differ from [naming conventions](../00_overview/naming_conventions.md)
- Before joining tabular and spatial tables on aligned key names
- When building reusable `staging` models consumed by multiple `curated` tables
- After [text cleaning](text_cleaning.md) and [safe casting](safe_casting.md) on renamed columns

## SQL Template

Explicit aliases to snake_case business names:

```sql
CREATE SCHEMA IF NOT EXISTS staging;

CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  LOWER(TRIM(country_code)) AS country_code,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv;
```

Spatial attribute rename with geometry alias:

```sql
CREATE OR REPLACE TABLE staging.stg_ca_regions AS
SELECT
  properties.NAME AS region_name,
  properties.REGION_TYPE AS region_type,
  geom AS geom
FROM raw.raw_ca_regions_geojson;
```

Select subset and standard keys for downstream joins:

```sql
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  order_id,
  customer_id,
  TRY_CAST(order_date AS DATE) AS order_date,
  TRY_CAST(amount AS DOUBLE) AS amount,
  COALESCE(NULLIF(TRIM(order_status), ''), 'unknown') AS order_status
FROM raw.raw_orders;
```

## Notebook Usage

```python
# Inspect raw column names before renaming
con.sql("""
  SELECT column_name, data_type
  FROM information_schema.columns
  WHERE table_schema = 'raw' AND table_name = 'raw_population_csv'
  ORDER BY ordinal_position
""").df()
```

```python
con.execute("""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_population AS
SELECT
  TRIM(country_name) AS country_name,
  TRY_CAST(year AS INTEGER) AS year,
  TRY_CAST(value AS DOUBLE) AS population
FROM raw.raw_population_csv;
""")
```

GeoJSON ingest with property flattening:

```python
con.execute("INSTALL spatial; LOAD spatial;")
con.execute("""
CREATE OR REPLACE TABLE raw.raw_ca_regions_geojson AS
SELECT * FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
""")

con.execute("""
CREATE OR REPLACE TABLE staging.stg_ca_regions AS
SELECT
  "properties.NAME" AS region_name,
  geom
FROM raw.raw_ca_regions_geojson
WHERE geom IS NOT NULL;
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{raw_table}` | `raw.raw_population_csv` | Source with vendor names |
| `{stg_table}` | `staging.stg_population` | Standardized output |
| Source column | `value`, `OWNER_NM` | Original name (quote if needed) |
| Target alias | `population`, `owner_name` | snake_case per conventions |
| Geometry column | `geom` | Keep `geom` unless source requires mapping |

## Input Table Pattern

```text
raw.raw_<topic>_<format>
```

Example: `raw.raw_population_csv` — source column names preserved from file.

| Country Name | Year | Value |
|--------------|------|-------|
| United States | 2020 | 331002651 |

Or spatial raw with nested properties:

| properties.NAME | geom |
|-----------------|------|
| California | POLYGON(...) |

## Output Table Pattern

```text
staging.stg_<entity>
```

Example: `staging.stg_population` — snake_case, typed, join-ready.

| country_name | year | population |
|--------------|------|------------|
| United States | 2020 | 331002651.0 |

Standard alias reference:

| Source style | Staging alias | Notes |
|--------------|---------------|-------|
| `Value`, `POP2010` | `population`, `population_2010` | Measure columns |
| `OWNER_NM`, `OwnerName` | `owner_name` | snake_case |
| `Shape_Area` | `shape_area_sqm` | Document units in name |
| `geometry`, `wkb_geometry` | `geom` | Primary geometry |
| `ID`, `FID` | `parcel_id`, `feature_id` | Entity prefix + `_id` |

## Validation Checks

```sql
-- Expected columns exist in staging
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'staging' AND table_name = 'stg_population'
ORDER BY ordinal_position;
```

```sql
-- No accidental duplicate alias names (should return zero rows)
SELECT column_name, COUNT(*) AS n
FROM information_schema.columns
WHERE table_schema = 'staging' AND table_name = 'stg_population'
GROUP BY 1
HAVING COUNT(*) > 1;
```

```sql
-- Row count unchanged from raw (renaming should not drop rows)
SELECT
  (SELECT COUNT(*) FROM raw.raw_population_csv) AS raw_rows,
  (SELECT COUNT(*) FROM staging.stg_population) AS stg_rows;
```

```sql
-- Key column non-null after rename
SELECT COUNT(*) AS null_country_name
FROM staging.stg_population
WHERE country_name IS NULL;
```

## Common Variations

### Quote reserved or dotted column names

```sql
SELECT "properties.ZIP" AS zip_code FROM raw.raw_zoning_geojson;
```

### Rename via `COLUMNS()` expression (wide tables)

```sql
SELECT COLUMNS(c -> c ILIKE '%area%')
FROM raw.raw_parcels_shp;
```

Inspect first; then replace with explicit aliases for production `staging`.

### Add surrogate key while standardizing

```sql
SELECT
  ROW_NUMBER() OVER (ORDER BY parcel_id) AS surrogate_id,
  parcel_id,
  owner_name,
  geom
FROM raw.raw_parcels_shp;
```

### Column mapping table in notebook

```python
COLUMN_MAP = {
    "OWNER_NM": "owner_name",
    "Shape_Area": "shape_area_sqm",
    "APN": "parcel_id",
}
select_list = ", ".join(f'"{src}" AS {dst}' for src, dst in COLUMN_MAP.items())
con.execute(f"""
CREATE OR REPLACE TABLE staging.stg_parcels AS
SELECT {select_list}, geom
FROM raw.raw_parcels_shp
""")
```

## Known Limitations

- Renaming does not change types — pair with [safe casting](safe_casting.md).
- GeoJSON / FileGDB property names may include dots and spaces — quote identifiers.
- `COLUMNS()` shortcuts are harder to version-control than explicit `SELECT` lists.
- Renaming geometry to something other than `geom` breaks shared spatial templates — prefer `geom` unless integrating with a fixed downstream contract.

## Related Pages

- [Naming conventions](../00_overview/naming_conventions.md)
- [Text cleaning](text_cleaning.md)
- [Safe casting](safe_casting.md)
- [Schema inspection](../04_eda/schema_inspection.md)

Official reference: [SELECT list / aliases](https://duckdb.org/docs/current/sql/query_syntax/select.html)
