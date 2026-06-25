# Parquet Export

Export `curated` tables to Apache Parquet files under `data/output/` for analytics consumers, data lakes, and fast re-ingest.

## Purpose

Write columnar, typed Parquet artifacts from validated `curated` models using DuckDB `COPY`, preserving schema and enabling efficient downstream scans.

## When to Use

- Delivering datasets to BI tools, Python/R analysts, or other DuckDB pipelines
- Publishing fact and dimension tables after validation
- Default tabular export format when file size and read speed matter
- Intermediate handoff before optional [partitioned Parquet](partitioned_parquet_export.md) layout

Prefer CSV only when the consumer requires spreadsheets — see [CSV export](csv_export.md).

## SQL Template

Single file export:

```sql
COPY curated.fct_orders
TO 'data/output/fct_orders.parquet'
(FORMAT PARQUET);
```

Projected export with compression:

```sql
COPY (
  SELECT
    order_id,
    order_date,
    customer_id,
    customer_name,
    region,
    amount,
    quantity,
    order_status
  FROM curated.fct_orders
) TO 'data/output/fct_orders.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
```

Export from inline query (no persisted curated table):

```sql
COPY (
  SELECT
    l_orderkey AS order_id,
    CAST(l_shipdate AS DATE) AS order_date,
    l_extendedprice AS amount
  FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
  WHERE l_shipdate >= DATE '1995-01-01'
) TO 'data/output/fct_orders_sample.parquet'
(FORMAT PARQUET);
```

## Notebook Usage

```python
from pathlib import Path

output_dir = Path("data/output")
output_dir.mkdir(parents=True, exist_ok=True)

con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  l_orderkey AS order_id,
  CAST(l_shipdate AS DATE) AS order_date,
  l_extendedprice AS amount,
  l_quantity AS quantity
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate IS NOT NULL
LIMIT 100000;
""")

con.execute("""
COPY curated.fct_orders
TO 'data/output/fct_orders.parquet'
(FORMAT PARQUET);
""")

list(output_dir.glob("*.parquet"))
```

```python
# Round-trip validation
con.execute("""
CREATE OR REPLACE TABLE staging.stg_orders_roundtrip AS
SELECT * FROM read_parquet('data/output/fct_orders.parquet');
""")

con.sql("""
SELECT
  (SELECT COUNT(*) FROM curated.fct_orders) AS curated_n,
  (SELECT COUNT(*) FROM staging.stg_orders_roundtrip) AS file_n,
  (SELECT SUM(amount) FROM curated.fct_orders) AS curated_amount,
  (SELECT SUM(amount) FROM staging.stg_orders_roundtrip) AS file_amount
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.fct_orders` | Source table |
| `{output_path}` | `data/output/fct_orders.parquet` | Single `.parquet` file |
| `{compression}` | `ZSTD`, `SNAPPY`, `GZIP` | ZSTD balances size and speed |
| `{columns}` | `order_id, amount` | Project in subquery |
| `{where_clause}` | `order_date >= DATE '2024-01-01'` | Filter before write |

## Input Table / Query

```text
curated.fct_orders
```

| order_id | order_date | customer_id | amount | quantity |
|----------|------------|-------------|--------|----------|
| 1001 | 2024-03-15 | C-42 | 129.99 | 2 |
| 1002 | 2024-03-16 | C-17 | 45.00 | 1 |

Export from `curated` after validation. Use `COPY (SELECT ...)` for column pruning and filters.

## Output Path

```text
data/output/fct_orders.parquet
data/output/dim_customers.parquet
data/output/mart_monthly_sales.parquet
```

## Validation After Export

```sql
-- Row count reconciliation
SELECT
  (SELECT COUNT(*) FROM curated.fct_orders) AS curated_rows,
  (SELECT COUNT(*) FROM read_parquet('data/output/fct_orders.parquet')) AS file_rows;
```

```sql
-- Aggregate reconciliation
SELECT
  (SELECT SUM(amount) FROM curated.fct_orders) AS curated_sum,
  (SELECT SUM(amount) FROM read_parquet('data/output/fct_orders.parquet')) AS file_sum;
```

```sql
-- Schema comparison
DESCRIBE curated.fct_orders;
DESCRIBE SELECT * FROM read_parquet('data/output/fct_orders.parquet');
```

```python
# Notebook assert gate before delivery
qa = con.sql("""
  SELECT
    (SELECT COUNT(*) FROM curated.fct_orders) =
    (SELECT COUNT(*) FROM read_parquet('data/output/fct_orders.parquet')) AS rows_match
""").df()
assert qa.rows_match.iloc[0], "Row count mismatch after Parquet export"
```

## Common Variations

### ZSTD compression (recommended default)

```sql
COPY curated.fct_orders
TO 'data/output/fct_orders.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);
```

### Export multiple curated tables

```python
for table in ["curated.fct_orders", "curated.dim_customers"]:
    name = table.split(".")[-1]
    con.execute(f"""
      COPY {table}
      TO 'data/output/{name}.parquet'
      (FORMAT PARQUET, COMPRESSION ZSTD);
    """)
```

### Row group size tuning (large tables)

```sql
COPY curated.fct_orders
TO 'data/output/fct_orders.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 100000);
```

### Overwrite guard with dated path

```python
from datetime import date
path = f"data/output/delivery_{date.today().isoformat()}/data/fct_orders.parquet"
Path(path).parent.mkdir(parents=True, exist_ok=True)
con.execute(f"COPY curated.fct_orders TO '{path}' (FORMAT PARQUET);")
```

### Hive-partitioned layout

For partition-by-column exports, see [partitioned Parquet export](partitioned_parquet_export.md).

## Performance Notes

- Parquet is columnar — consumers reading few columns scan much less data than CSV.
- `COMPRESSION ZSTD` typically cuts file size 50–80% vs uncompressed with modest CPU cost.
- `COPY` from `curated` is a single sequential write — no need to materialize intermediate formats.
- Project columns in the subquery to reduce file size and write time.
- For tables over ~10M rows, consider [partitioned export](partitioned_parquet_export.md) for parallel downstream reads.

## Known Limitations

- Single-file Parquet does not scale as well as partitioned datasets for very large tables or selective partition reads.
- Geometry columns in plain `FORMAT PARQUET` may not carry full GeoParquet metadata — use [GeoParquet export](geoparquet_export.md) for spatial layers.
- `COPY` overwrites the destination file — use dated folders for version history.
- Schema changes between exports can break downstream consumers — document in `manifest.csv` (see [delivery package](delivery_package.md)).
- Encrypted Parquet is not supported by default DuckDB `COPY`.

## Related Pages

- [Partitioned Parquet export](partitioned_parquet_export.md)
- [CSV export](csv_export.md)
- [GeoParquet export](geoparquet_export.md)
- [Delivery package](delivery_package.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html) · [Parquet](https://duckdb.org/docs/current/data/parquet/overview.html)
