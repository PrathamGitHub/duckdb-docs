# Partitioned Parquet Export

Export `curated` tables to hive-style partitioned Parquet directories under `data/output/` for scalable downstream reads and partition pruning.

## Purpose

Write columnar datasets partitioned by date, region, or category so consumers can read only the slices they need without scanning the full table.

## When to Use

- `curated.fct_orders` is large and consumers filter by `order_month` or `region`
- Publishing data lake-style drops for Spark, Polars, or DuckDB `hive_partitioning`
- Replacing many manual per-slice CSV exports with one partitioned tree
- Spatial layers partitioned by `boundary_name` or `zoning_code`

Use single-file [Parquet export](parquet_export.md) for small tables or simple handoffs.

## SQL Template

Partition by month:

```sql
COPY (
  SELECT
    order_id,
    order_date,
    DATE_TRUNC('month', order_date) AS order_month,
    customer_id,
    region,
    amount
  FROM curated.fct_orders
) TO 'data/output/fct_orders'
(FORMAT PARQUET, PARTITION_BY (order_month), COMPRESSION ZSTD);
```

Partition by region and month:

```sql
COPY (
  SELECT *
  FROM curated.fct_orders
) TO 'data/output/fct_orders_by_region'
(FORMAT PARQUET, PARTITION_BY (region, order_month), COMPRESSION ZSTD);
```

Spatial partition by attribute:

```sql
COPY (
  SELECT parcel_id, owner_name, boundary_name, area_sqm, geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels'
(FORMAT PARQUET, PARTITION_BY (boundary_name), COMPRESSION ZSTD);
```

Resulting layout:

```text
data/output/fct_orders/
├── order_month=2024-01-01/
│   └── data_0.parquet
├── order_month=2024-02-01/
│   └── data_0.parquet
└── ...
```

## Notebook Usage

```python
from pathlib import Path

output_root = Path("data/output/fct_orders")
output_root.mkdir(parents=True, exist_ok=True)

con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  l_orderkey AS order_id,
  CAST(l_shipdate AS DATE) AS order_date,
  DATE_TRUNC('month', CAST(l_shipdate AS DATE)) AS order_month,
  l_extendedprice AS amount,
  CASE WHEN l_orderkey % 3 = 0 THEN 'East'
       WHEN l_orderkey % 3 = 1 THEN 'West'
       ELSE 'Central' END AS region
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate IS NOT NULL
LIMIT 200000;
""")

con.execute("""
COPY (
  SELECT order_id, order_date, order_month, region, amount
  FROM curated.fct_orders
) TO 'data/output/fct_orders'
(FORMAT PARQUET, PARTITION_BY (order_month), COMPRESSION ZSTD);
""")

# List partition folders
sorted(p.name for p in output_root.iterdir() if p.is_dir())
```

```python
# Read back with partition pruning
subset = con.sql("""
SELECT COUNT(*) AS n, SUM(amount) AS total
FROM read_parquet('data/output/fct_orders/**', hive_partitioning = true)
WHERE order_month = DATE '1995-03-01'
""").df()
subset
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.fct_orders` | Source table |
| `{output_dir}` | `data/output/fct_orders` | Directory, not `.parquet` file |
| `{partition_columns}` | `order_month`, `region` | Must appear in `SELECT` |
| `{compression}` | `ZSTD` | Applied per data file |
| `{where_clause}` | Pre-filter in subquery | Reduces partition count |

## Input Table / Query

```text
curated.fct_orders
```

| order_id | order_date | order_month | region | amount |
|----------|------------|-------------|--------|--------|
| 1001 | 2024-03-15 | 2024-03-01 | East | 129.99 |
| 1002 | 2024-03-16 | 2024-03-01 | West | 45.00 |

Partition columns must be included in the `COPY (SELECT ...)` list. High-cardinality partition keys (e.g. `order_id`) create too many small files — avoid.

## Output Path

```text
data/output/fct_orders/                    -- hive layout root
data/output/fct_orders_by_region/          -- multi-column partitions
data/output/geo_parcels/                   -- spatial + attribute partition
```

Place delivery bundles under `data/output/delivery_YYYY-MM-DD/data/` — see [delivery package](delivery_package.md).

## Validation After Export

```sql
-- Total row count: curated vs all partition files
SELECT
  (SELECT COUNT(*) FROM curated.fct_orders) AS curated_rows,
  (SELECT COUNT(*) FROM read_parquet('data/output/fct_orders/**', hive_partitioning = true)) AS file_rows;
```

```sql
-- Per-partition counts
SELECT order_month, COUNT(*) AS n, SUM(amount) AS total_amount
FROM read_parquet('data/output/fct_orders/**', hive_partitioning = true)
GROUP BY 1
ORDER BY 1;
```

```sql
-- Reconcile partition sum to curated
SELECT
  (SELECT SUM(amount) FROM curated.fct_orders) AS curated_sum,
  (SELECT SUM(amount) FROM read_parquet('data/output/fct_orders/**', hive_partitioning = true)) AS file_sum;
```

```python
# Notebook: list partitions and file sizes
from pathlib import Path

for part_dir in sorted(Path("data/output/fct_orders").iterdir()):
    if part_dir.is_dir():
        size_mb = sum(f.stat().st_size for f in part_dir.rglob("*.parquet")) / 1e6
        print(f"{part_dir.name}: {size_mb:.2f} MB")
```

## Common Variations

### Single partition column (date)

```sql
COPY (SELECT *, DATE_TRUNC('day', order_date) AS order_day FROM curated.fct_orders)
TO 'data/output/fct_orders_daily'
(FORMAT PARQUET, PARTITION_BY (order_day));
```

### Filter before partition write

```sql
COPY (
  SELECT * FROM curated.fct_orders
  WHERE order_date >= DATE '2024-01-01'
) TO 'data/output/fct_orders_2024'
(FORMAT PARQUET, PARTITION_BY (order_month));
```

### Export for DuckDB re-ingest (mirror ingest pattern)

```sql
-- Write partitioned
COPY (SELECT * FROM curated.fct_orders)
TO 'data/output/fct_orders'
(FORMAT PARQUET, PARTITION_BY (order_month));

-- Read back (ingest symmetry)
CREATE OR REPLACE VIEW raw.raw_orders_parquet AS
SELECT * FROM read_parquet('data/output/fct_orders/**', hive_partitioning = true);
```

### Spatial partitioned GeoParquet

```sql
INSTALL spatial;
LOAD spatial;

COPY (
  SELECT parcel_id, boundary_name, zoning_code, geom
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels'
(FORMAT PARQUET, PARTITION_BY (boundary_name));
```

For full GeoParquet metadata, see [GeoParquet export](geoparquet_export.md).

## Performance Notes

- Partition pruning lets consumers read `WHERE order_month = ...` without scanning other months.
- Target partition sizes of 100 MB–1 GB per folder when possible — avoid millions of tiny partitions.
- Low-cardinality partition keys (`region`, `order_month`) outperform high-cardinality keys (`order_id`).
- `COMPRESSION ZSTD` reduces total tree size significantly on repetitive partition columns.
- Re-exporting overwrites the output directory — use dated delivery folders for history.

## Known Limitations

- Too many partitions (high-cardinality keys) degrade filesystem performance and metadata overhead.
- `PARTITION_BY` columns are stored in directory names — changing partition strategy requires full re-export.
- Plain `FORMAT PARQUET` partitioned spatial exports may lack full GeoParquet metadata.
- Empty partitions are omitted — a missing folder may mean zero rows, not a failed export.
- Downstream tools must support hive-style layouts (`hive_partitioning = true` in DuckDB).
- `COPY` to an existing directory may overwrite — confirm path before production runs.

## Related Pages

- [Parquet export](parquet_export.md)
- [Partitioned Parquet ingestion](../02_ingestion/partitioned_parquet.md)
- [GeoParquet export](geoparquet_export.md)
- [Delivery package](delivery_package.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html) · [Hive partitioning](https://duckdb.org/docs/current/data/parquet/overview.html)
