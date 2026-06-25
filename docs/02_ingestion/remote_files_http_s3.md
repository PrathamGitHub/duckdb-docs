# Remote Files (HTTP / S3)

Ingest files directly from HTTPS URLs and cloud object storage into `raw` without a separate download step, using the `httpfs` extension.

## Purpose

Query `source` files in place over HTTP/S3, then snapshot into `raw_<dataset_name>` tables for auditable pipelines and offline practice mirrors under `data/raw/`.

## When to Use

- Public open-data URLs (CSV, Parquet, JSON, GeoJSON)
- S3-compatible buckets you can read with credentials
- Quick notebook EDA before committing to a local mirror
- Federating remote Parquet in a lakehouse layout

Mirror unstable or large files to `data/raw/` for repeatability — see [project paths](../01_setup/project_paths.md).

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Extension | `INSTALL httpfs; LOAD httpfs;` |
| HTTP | Public URLs or authenticated headers (advanced) |
| S3 | `s3://bucket/key` paths; credentials via `SET` or environment |
| Network | Notebook environment must reach the host |
| Naming | `raw_<topic>_<format>` — e.g. `raw.raw_population_csv`, `raw.raw_lineitem_parquet` |
| Secrets | Never commit keys — use environment variables |

## Basic DuckDB SQL

HTTPS CSV:

```sql
INSTALL httpfs;
LOAD httpfs;

SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
)
LIMIT 10;
```

HTTPS Parquet:

```sql
SELECT *
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
LIMIT 10;
```

S3 Parquet (credentials required):

```sql
SET s3_region = 'us-east-1';
-- Prefer environment-based credential chain in production notebooks

SELECT *
FROM read_parquet('s3://bucket-name/path/events.parquet')
LIMIT 10;
```

GeoJSON over HTTP (`spatial`):

```sql
INSTALL spatial;
LOAD spatial;

SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
```

## Create Raw View Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

```sql
CREATE OR REPLACE VIEW raw.raw_lineitem_parquet AS
SELECT *
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet');
```

## Create Raw Table Pattern

```sql
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT *
FROM read_csv_auto(
  'https://raw.githubusercontent.com/datasets/population/master/data/population.csv'
);
```

```sql
CREATE OR REPLACE TABLE raw.raw_regions_geojson AS
SELECT *
FROM ST_Read(
  'https://raw.githubusercontent.com/glynnbird/usstatesgeojson/master/california.geojson'
);
```

## Notebook Usage Example

```python
import os
import urllib.request

POPULATION_URL = (
    "https://raw.githubusercontent.com/datasets/population/master/data/population.csv"
)
local_copy = RAW_DIR / "population.csv"

con.execute("INSTALL httpfs; LOAD httpfs;")

# Remote-first ingest
con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_population_csv AS
SELECT * FROM read_csv_auto('{POPULATION_URL}');
""")

# Mirror to data/raw/ for offline practice
if not local_copy.exists():
    urllib.request.urlretrieve(POPULATION_URL, local_copy)

con.sql("SELECT COUNT(*) AS n FROM raw.raw_population_csv").df()
```

S3 with environment credentials:

```python
import os

for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_DEFAULT_REGION"):
    if os.environ.get(key):
        con.execute(f"SET s3_{key.lower().replace('aws_', '').replace('_default', '')} = '{os.environ[key]}';")

# Or use credential chain without embedding secrets in the notebook
con.execute("""
CREATE OR REPLACE TABLE raw.raw_events_parquet AS
SELECT * FROM read_parquet('s3://your-bucket/raw/events/*.parquet');
""")
```

## Common Variations

### HTTP glob (when server supports listing — often prefer explicit URLs)

```sql
SELECT *
FROM read_parquet([
  'https://blobs.duckdb.org/data/lineitem.parquet',
  'https://blobs.duckdb.org/data/orders.parquet'
]);
```

### S3 glob

```sql
CREATE OR REPLACE TABLE raw.raw_orders_parquet AS
SELECT *
FROM read_parquet('s3://bucket/raw/orders/**/*.parquet');
```

### Custom HTTP endpoint (Parquet)

```sql
SELECT *
FROM read_parquet('https://example.com/api/export.parquet');
```

### `enable_server_cert_verification` for strict TLS environments

```sql
SET enable_server_cert_verification = true;
```

### Spatial remote Shapefile (zip URL)

```sql
CREATE OR REPLACE TABLE raw.raw_parcels_shp AS
SELECT *
FROM ST_Read('https://example.com/data/parcels.zip');
```

### Switch remote → local without changing downstream SQL

```python
USE_LOCAL = local_copy.exists()
path = local_copy.as_posix() if USE_LOCAL else POPULATION_URL
con.execute(f"""
CREATE OR REPLACE VIEW raw.raw_population_csv AS
SELECT * FROM read_csv_auto('{path}');
""")
```

## Validation Checks After Ingestion

```sql
-- Confirm data landed
SELECT COUNT(*) AS row_count FROM raw.raw_population_csv;

-- Schema
DESCRIBE raw.raw_population_csv;

-- Remote vs local row count (after mirror)
SELECT COUNT(*) FROM read_csv_auto('data/raw/population.csv');

-- Spot check values
SELECT * FROM raw.raw_population_csv LIMIT 5;

-- Spatial remote ingest
SELECT
  COUNT(*) AS features,
  ST_GeometryType(geom) AS geom_type
FROM raw.raw_regions_geojson
GROUP BY 2;
```

Log ingest metadata in a notebook cell:

```python
meta = con.sql("""
SELECT
  'raw_population_csv' AS table_name,
  COUNT(*) AS rows,
  current_timestamp AS ingested_at
FROM raw.raw_population_csv
""").df()
meta
```

## Performance Notes

- First remote read pays network latency — mirror to `data/raw/` for iterative notebook work.
- Parquet over HTTP supports range requests — column pruning still helps.
- S3 parallel reads scale well with `httpfs`; reuse a materialized `raw` table for many passes.
- Prefer regional buckets/colocated compute to reduce egress.
- Views over remote paths re-fetch on each query — tables snapshot once.

## Known Limitations

- No network in some CI or air-gapped environments — require local mirrors.
- URLs can change, rate-limit, or require auth — not a stable `source` without mirroring.
- S3 credentials in notebooks are a security risk — use env vars or instance roles.
- Very large remote files without local disk cache can exhaust bandwidth on repeated EDA.
- Not all hosts support byte-range reads — some CSV URLs must be fully downloaded.
- GeoJSON URLs may be large FeatureCollections — consider GeoParquet for production spatial `source`.

## Related Pages

- [CSV ingestion](csv.md)
- [Parquet ingestion](parquet.md)
- [JSON ingestion](json.md)
- [Extensions](../01_setup/extensions.md)
- [Project paths](../01_setup/project_paths.md)

Official reference: [DuckDB httpfs](https://duckdb.org/docs/current/extensions/httpfs/overview.html)
