# JSON Ingestion

Ingest JSON documents and newline-delimited JSON (NDJSON) into the `raw` layer using DuckDB's `read_json` family and the `json` extension.

## Purpose

Load semi-structured API responses, event logs, configuration exports, and nested records into queryable `raw` tables while preserving structure for flattening in `staging`.

## When to Use

- REST API payloads saved as `.json` or `.jsonl`
- Event streams (`raw_events`) with variable or nested fields
- GeoJSON FeatureCollections (tabular attributes + geometry — or use `ST_Read` for spatial-first ingest)
- Intermediate format before normalizing to relational `staging` tables

Use CSV or Parquet when the data is already flat and typed.

## Input Assumptions

| Assumption | Notes |
|------------|-------|
| Extension | `INSTALL json; LOAD json;` |
| Shape | Single array, NDJSON lines, or nested objects — set `format` accordingly |
| Detection | `auto_detect=true` samples records; explicit `columns={...}` for production |
| Layer | File or URL is **source** |
| Naming | `raw_<topic>_json` — e.g. `raw.raw_events_json`, `raw.raw_api_json` |
| Nesting | Expect `STRUCT` / `LIST` columns until flattened in `staging` |

## Basic DuckDB SQL

```sql
INSTALL json;
LOAD json;

SELECT *
FROM read_json('data/raw/events.json', auto_detect = true)
LIMIT 10;
```

NDJSON (one JSON object per line):

```sql
SELECT *
FROM read_json('data/raw/events.jsonl', format = 'newline_delimited', auto_detect = true)
LIMIT 10;
```

Real-world practice dataset (movies JSON array):

```sql
INSTALL httpfs;
LOAD httpfs;
INSTALL json;
LOAD json;

SELECT title, year, "cast"
FROM read_json(
  'https://raw.githubusercontent.com/vega/vega/main/docs/data/movies.json',
  auto_detect = true
)
LIMIT 5;
```

Explicit schema (stable ingest):

```sql
SELECT *
FROM read_json(
  'data/raw/orders.json',
  format = 'array',
  columns = {
    order_id: 'VARCHAR',
    customer_id: 'VARCHAR',
    items: 'JSON',
    created_at: 'TIMESTAMP'
  }
);
```

## Create Raw View Pattern

```sql
CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE VIEW raw.raw_events_json AS
SELECT *
FROM read_json('data/raw/events.jsonl', format = 'newline_delimited', auto_detect = true);
```

Remote API-style file:

```sql
CREATE OR REPLACE VIEW raw.raw_movies_json AS
SELECT *
FROM read_json(
  'https://raw.githubusercontent.com/vega/vega/main/docs/data/movies.json',
  auto_detect = true
);
```

## Create Raw Table Pattern

```sql
CREATE OR REPLACE TABLE raw.raw_events_json AS
SELECT *
FROM read_json('data/raw/events.jsonl', format = 'newline_delimited', auto_detect = true);
```

```sql
CREATE OR REPLACE TABLE raw.raw_customers_json AS
SELECT *
FROM read_json('data/raw/customers.json', auto_detect = true);
```

## Notebook Usage Example

```python
MOVIES_URL = "https://raw.githubusercontent.com/vega/vega/main/docs/data/movies.json"

con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("INSTALL json; LOAD json;")

con.execute(f"""
CREATE OR REPLACE TABLE raw.raw_movies_json AS
SELECT * FROM read_json('{MOVIES_URL}', auto_detect = true);
""")

con.sql("""
SELECT year, COUNT(*) AS film_count
FROM raw.raw_movies_json
WHERE year IS NOT NULL
GROUP BY year
ORDER BY year DESC
LIMIT 10
""").df()
```

Flatten nested fields in a later cell (preview of `staging` work):

```python
con.sql("""
SELECT title, year, unnest("cast") AS actor
FROM raw.raw_movies_json
LIMIT 20
""").df()
```

## Common Variations

### `max_depth` for deeply nested API payloads

```sql
SELECT *
FROM read_json('data/raw/api_response.json', auto_detect = true, maximum_depth = 3);
```

### Records wrapper (`{"records": [...]}`)

```sql
CREATE OR REPLACE TABLE raw.raw_events_json AS
SELECT unnest(records) AS record
FROM read_json('data/raw/wrapped.json', auto_detect = true);
```

### Combine with `json_extract` in staging

```sql
CREATE OR REPLACE TABLE staging.stg_events AS
SELECT
  json_extract_string(record, '$.event_id') AS event_id,
  json_extract_string(record, '$.user_id') AS user_id,
  CAST(json_extract(record, '$.timestamp') AS TIMESTAMP) AS event_at
FROM raw.raw_events_json;
```

### GeoJSON as JSON (non-spatial path)

For geometry-aware ingest, prefer `ST_Read` — see [extensions](../01_setup/extensions.md). JSON path is useful for Feature properties only:

```sql
SELECT
  json_extract_string(feature, '$.properties.NAME') AS name
FROM read_json('data/raw/regions.geojson', auto_detect = true);
```

### Ingest from Python dict via Arrow

```python
import json
import pandas as pd

payload = json.loads((RAW_DIR / "sample.json").read_text())
df = pd.json_normalize(payload)
con.register("tmp_json", df)
con.execute("CREATE OR REPLACE TABLE raw.raw_orders_json AS SELECT * FROM tmp_json")
```

## Validation Checks After Ingestion

```sql
-- Row count
SELECT COUNT(*) AS row_count FROM raw.raw_movies_json;

-- Schema (note STRUCT/LIST types)
DESCRIBE raw.raw_movies_json;

-- Null rates on extracted keys
SELECT
  COUNT(*) AS total,
  COUNT(title) AS with_title,
  COUNT(year) AS with_year
FROM raw.raw_movies_json;

-- Duplicate logical keys after flattening
SELECT title, year, COUNT(*) AS n
FROM raw.raw_movies_json
GROUP BY 1, 2
HAVING COUNT(*) > 1;

-- Sample nested values
SELECT title, "cast" FROM raw.raw_movies_json LIMIT 3;
```

## Performance Notes

- `auto_detect` scans a sample — fast to start; pin `columns` for repeatable production ingests.
- NDJSON parallelizes well — prefer `.jsonl` for large event logs over one giant array file.
- Flatten nested lists in `staging` with `unnest`, not during every `raw` re-ingest.
- Large JSON strings as VARCHAR — extract early in `staging` to avoid repeated parse cost.
- For repeated queries, materialize a **table** in `raw`; views re-parse JSON files each time.

## Known Limitations

- Heterogeneous records (varying keys per row) produce sparse STRUCTs or type conflicts — unify in `staging` or enforce schema.
- Very large single JSON arrays do not stream as cleanly as NDJSON.
- GeoJSON complex curves and CRS handling are better via `spatial` / `ST_Read` than raw JSON parsing.
- `auto_detect` can miss rare keys — profile a full batch before trusting inferred schema.
- JSON from APIs may need authentication outside DuckDB — download to `data/raw/` in Python first.

## Related Pages

- [Remote files (HTTP / S3)](remote_files_http_s3.md)
- [Extensions](../01_setup/extensions.md)
- [CSV ingestion](csv.md) — flat alternative

Official reference: [DuckDB JSON](https://duckdb.org/docs/current/data/json/overview.html)
