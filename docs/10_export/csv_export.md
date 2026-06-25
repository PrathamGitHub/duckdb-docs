# CSV Export

Export `curated` tables to comma-separated text files under `data/output/` for spreadsheets, email attachments, and tools that do not read Parquet.

## Purpose

Write validated `curated.fct_*` and `curated.dim_*` tables to portable CSV files using DuckDB `COPY`, preserving headers and delimiter options for downstream consumers.

## When to Use

- Handing tabular results to analysts who work in Excel or Google Sheets
- Integrating with legacy tools that only accept delimited text
- Publishing small attribute extracts alongside spatial exports
- Final `curated → output` step after validation passes

Skip CSV for large analytics datasets — prefer [Parquet export](parquet_export.md).

## SQL Template

Single curated table:

```sql
COPY curated.fct_orders
TO 'data/output/fct_orders.csv'
WITH (HEADER, DELIMITER ',');
```

Export a filtered projection (recommended):

```sql
COPY (
  SELECT
    order_id,
    order_date,
    customer_id,
    customer_name,
    region,
    amount,
    quantity
  FROM curated.fct_orders
  WHERE order_date >= DATE '2024-01-01'
) TO 'data/output/fct_orders_2024.csv'
WITH (HEADER, DELIMITER ',');
```

Tab-separated variant:

```sql
COPY curated.dim_customers
TO 'data/output/dim_customers.tsv'
WITH (HEADER, DELIMITER E'\t');
```

## Notebook Usage

```python
from pathlib import Path

output_dir = Path("data/output")
output_dir.mkdir(parents=True, exist_ok=True)

# Build curated table from online practice data (DuckDB lineitem demo)
con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  l_orderkey AS order_id,
  CAST(l_shipdate AS DATE) AS order_date,
  l_extendedprice AS amount,
  l_quantity AS quantity,
  l_returnflag AS order_status
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate IS NOT NULL
LIMIT 50000;
""")

con.execute("""
COPY (
  SELECT order_id, order_date, amount, quantity, order_status
  FROM curated.fct_orders
) TO 'data/output/fct_orders.csv'
WITH (HEADER, DELIMITER ',');
""")

list(output_dir.glob("fct_orders*.csv"))
```

```python
# Round-trip validation: read exported CSV back
import pandas as pd

exported = pd.read_csv("data/output/fct_orders.csv")
curated_n = con.sql("SELECT COUNT(*) AS n FROM curated.fct_orders").df().n.iloc[0]
assert len(exported) == curated_n, f"Row mismatch: {len(exported)} vs {curated_n}"
exported.head()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.fct_orders` | Source table or subquery |
| `{output_path}` | `data/output/fct_orders.csv` | Destination file path |
| `{delimiter}` | `,`, `E'\t'`, `;` | Match consumer locale |
| `{header}` | `HEADER` | Include column names in row 1 |
| `{where_clause}` | `order_date >= DATE '2024-01-01'` | Filter before export |
| `{columns}` | `order_id, amount` | Project only needed fields |

## Input Table / Query

```text
curated.fct_orders
```

| order_id | order_date | customer_id | amount | quantity | order_status |
|----------|------------|-------------|--------|----------|--------------|
| 1001 | 2024-03-15 | C-42 | 129.99 | 2 | F |
| 1002 | 2024-03-16 | C-17 | 45.00 | 1 | O |

Export reads from `curated` — not `staging` or `raw`. Use a `COPY (SELECT ...)` subquery when you need filters or column selection.

## Output Path

```text
data/output/fct_orders.csv
data/output/dim_customers.csv
data/output/fct_orders_2024.csv          -- filtered slice
```

For delivery bundles, place files under `data/output/delivery_YYYY-MM-DD/data/` — see [delivery package](delivery_package.md).

## Validation After Export

```sql
-- Row count: curated vs exported (notebook reads CSV via read_csv)
SELECT COUNT(*) AS curated_rows FROM curated.fct_orders;
```

```python
import pandas as pd

curated_n = con.sql("SELECT COUNT(*) AS n FROM curated.fct_orders").df().n.iloc[0]
file_n = len(pd.read_csv("data/output/fct_orders.csv"))
assert file_n == curated_n
```

```sql
-- Aggregate reconciliation (amounts should match)
SELECT
  COUNT(*) AS row_count,
  SUM(amount) AS total_amount,
  MIN(order_date) AS min_date,
  MAX(order_date) AS max_date
FROM curated.fct_orders;
```

```python
# Compare sums after export
curated_sum = con.sql("SELECT SUM(amount) AS s FROM curated.fct_orders").df().s.iloc[0]
exported_sum = pd.read_csv("data/output/fct_orders.csv")["amount"].sum()
assert abs(curated_sum - exported_sum) < 0.01
```

```sql
-- Schema spot-check via DuckDB read
SELECT * FROM read_csv('data/output/fct_orders.csv', header = true) LIMIT 5;
```

## Common Variations

### Quote and escape options

```sql
COPY curated.fct_orders
TO 'data/output/fct_orders.csv'
WITH (HEADER, DELIMITER ',', QUOTE '"', ESCAPE '"');
```

### Export multiple tables in a notebook loop

```python
tables = ["curated.fct_orders", "curated.dim_customers"]
for table in tables:
    name = table.split(".")[-1]
    con.execute(f"""
      COPY {table}
      TO 'data/output/{name}.csv'
      WITH (HEADER, DELIMITER ',');
    """)
```

### Dated output folder

```python
from datetime import date
out = Path(f"data/output/delivery_{date.today().isoformat()}/data")
out.mkdir(parents=True, exist_ok=True)
con.execute(f"""
  COPY curated.fct_orders
  TO '{out / "fct_orders.csv"}'
  WITH (HEADER, DELIMITER ',');
""")
```

### Excel-friendly CSV

For locale-specific Excel opens, see [Excel-ready CSV](excel_ready_csv.md) (UTF-8 BOM, semicolon delimiter).

### Attribute-only export from spatial table

```sql
COPY (
  SELECT parcel_id, owner_name, zoning_code, area_sqm
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_attributes.csv'
WITH (HEADER, DELIMITER ',');
```

## Performance Notes

- CSV is row-oriented and uncompressed — slow and large compared to Parquet for wide or million-row tables.
- Project columns in `COPY (SELECT ...)` to reduce file size and write time.
- Filter before export when consumers only need a slice.
- DuckDB writes CSV in a single pass — adequate for tables up to low millions of rows on typical laptops.
- For repeated reads of the same export, consumers should convert to Parquet upstream.

## Known Limitations

- No native data types in CSV — dates and decimals are serialized as text; consumers must parse.
- Special characters in text fields require correct `QUOTE` / `ESCAPE` settings.
- Very large exports can produce multi-GB files that Excel cannot open (row limit ~1,048,576).
- Geometry columns export as WKT strings — not useful for GIS; use [GeoParquet](geoparquet_export.md) or [GeoJSON](geojson_export.md).
- `COPY` overwrites the target file — version output paths for audit trails.
- Null values appear as empty fields — distinguish from empty strings in downstream tools.

## Related Pages

- [Parquet export](parquet_export.md)
- [Excel-ready CSV](excel_ready_csv.md)
- [Delivery package](delivery_package.md)
- [Build fact table](../07_transformation/build_fact_table.md)
- [Row count reconciliation](../09_validation/row_count_reconciliation.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html)
