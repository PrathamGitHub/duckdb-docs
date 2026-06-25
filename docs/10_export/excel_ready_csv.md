# Excel-Ready CSV Export

Export `curated` tables to CSV files formatted for reliable opening in Microsoft Excel, LibreOffice Calc, and regional locale settings.

## Purpose

Produce spreadsheet-friendly delimited files from `curated` models with headers, encoding, delimiter, and date formatting choices that minimize "columns merged into one" and mojibake issues in Excel.

## When to Use

- Business users open exports directly in Excel without import wizards
- European locales expect semicolon delimiters and comma decimal separators
- UTF-8 text with accented characters must display correctly
- Final `curated → output` handoff for non-technical stakeholders

For analytics pipelines, prefer [Parquet export](parquet_export.md). For generic CSV, see [CSV export](csv_export.md).

## SQL Template

Standard comma-separated (US / UK Excel — import via Data → From Text/CSV):

```sql
COPY (
  SELECT
    order_id,
    order_date,
    customer_name,
    region,
    amount,
    quantity
  FROM curated.fct_orders
) TO 'data/output/fct_orders_excel.csv'
WITH (HEADER, DELIMITER ',');
```

Semicolon delimiter (common EU Excel double-click open):

```sql
COPY (
  SELECT
    order_id,
    order_date,
    customer_name,
    region,
    amount,
    quantity
  FROM curated.fct_orders
) TO 'data/output/fct_orders_excel.csv'
WITH (HEADER, DELIMITER ';');
```

Cast dates to ISO strings for predictable Excel parsing:

```sql
COPY (
  SELECT
    order_id,
    strftime(order_date, '%Y-%m-%d') AS order_date,
    customer_name,
    ROUND(amount, 2) AS amount,
    quantity
  FROM curated.fct_orders
) TO 'data/output/fct_orders_excel.csv'
WITH (HEADER, DELIMITER ',');
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
  'Customer ' || CAST(l_orderkey % 1000 AS VARCHAR) AS customer_name,
  l_extendedprice AS amount,
  l_quantity AS quantity
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate IS NOT NULL
LIMIT 10000;
""")

# DuckDB COPY — comma-delimited with header
con.execute("""
COPY (
  SELECT
    order_id,
    strftime(order_date, '%Y-%m-%d') AS order_date,
    customer_name,
    ROUND(amount, 2) AS amount,
    quantity
  FROM curated.fct_orders
) TO 'data/output/fct_orders_excel.csv'
WITH (HEADER, DELIMITER ',');
""")
```

```python
# Add UTF-8 BOM for Excel on Windows (open by double-click)
import pandas as pd

df = con.sql("""
  SELECT
    order_id,
    strftime(order_date, '%Y-%m-%d') AS order_date,
    customer_name,
    ROUND(amount, 2) AS amount,
    quantity
  FROM curated.fct_orders
""").df()

bom_path = output_dir / "fct_orders_excel_bom.csv"
df.to_csv(bom_path, index=False, encoding="utf-8-sig")
bom_path
```

```python
# Validation: row count and sample
import pandas as pd

curated_n = con.sql("SELECT COUNT(*) AS n FROM curated.fct_orders").df().n.iloc[0]
excel_df = pd.read_csv("data/output/fct_orders_excel.csv")
assert len(excel_df) == curated_n
excel_df.head()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{curated_table}` | `curated.fct_orders` | Source table |
| `{output_path}` | `data/output/fct_orders_excel.csv` | Destination file |
| `{delimiter}` | `,` or `;` | Match user locale |
| `{date_format}` | `'%Y-%m-%d'` | ISO 8601 recommended |
| `{decimal_places}` | `ROUND(amount, 2)` | Avoid float noise in Excel |
| `{encoding}` | `utf-8-sig` (via pandas BOM) | Windows Excel UTF-8 |

## Input Table / Query

```text
curated.fct_orders
```

| order_id | order_date | customer_name | amount | quantity |
|----------|------------|---------------|--------|----------|
| 1001 | 2024-03-15 | Acme Corp | 129.99 | 2 |
| 1002 | 2024-03-16 | Beta LLC | 45.00 | 1 |

Pre-format dates and round numerics in the `SELECT` before `COPY` for best Excel behavior.

## Output Path

```text
data/output/fct_orders_excel.csv
data/output/fct_orders_excel_bom.csv       -- UTF-8 with BOM (pandas)
data/output/dim_customers_excel.csv
```

Include in [delivery package](delivery_package.md) under `data/` with README notes on delimiter and encoding.

## Validation After Export

```sql
SELECT COUNT(*) AS curated_rows FROM curated.fct_orders;
```

```python
import pandas as pd

curated = con.sql("SELECT COUNT(*), SUM(amount) FROM curated.fct_orders").df()
exported = pd.read_csv("data/output/fct_orders_excel.csv")
assert len(exported) == curated.iloc[0, 0]
assert abs(exported["amount"].sum() - curated.iloc[0, 1]) < 0.1
```

```sql
-- Spot-check via DuckDB read
SELECT * FROM read_csv('data/output/fct_orders_excel.csv', header = true) LIMIT 5;
```

Manual check: open the file in Excel and confirm column split, date format, and accented characters.

## Common Variations

### UTF-8 BOM for Windows Excel

```python
df.to_csv("data/output/fct_orders_excel.csv", index=False, encoding="utf-8-sig")
```

### Semicolon for EU locale

```sql
COPY (...) TO 'data/output/fct_orders_excel.csv'
WITH (HEADER, DELIMITER ';');
```

### Tab-separated (.tsv) for paste-friendly workflows

```sql
COPY (...) TO 'data/output/fct_orders_excel.tsv'
WITH (HEADER, DELIMITER E'\t');
```

### Integer IDs without scientific notation

```sql
COPY (
  SELECT
    CAST(order_id AS VARCHAR) AS order_id,
    strftime(order_date, '%Y-%m-%d') AS order_date,
    amount
  FROM curated.fct_orders
) TO 'data/output/fct_orders_excel.csv'
WITH (HEADER, DELIMITER ',');
```

### Multiple sheets workaround

Excel does not read multiple sheets from CSV — export separate files or use [Excel ingestion](../02_ingestion/excel.md) patterns in reverse via pandas:

```python
with pd.ExcelWriter("data/output/report.xlsx", engine="openpyxl") as writer:
    con.sql("SELECT * FROM curated.fct_orders").df().to_excel(writer, sheet_name="Orders", index=False)
    con.sql("SELECT * FROM curated.dim_customers").df().to_excel(writer, sheet_name="Customers", index=False)
```

### Attribute export from spatial layer (no geometry)

```sql
COPY (
  SELECT
    parcel_id,
    owner_name,
    ROUND(area_sqm, 1) AS area_sqm
  FROM curated.geo_parcels
) TO 'data/output/geo_parcels_excel.csv'
WITH (HEADER, DELIMITER ',');
```

## Performance Notes

- Excel-ready formatting (casts, rounding) adds negligible overhead vs plain `COPY`.
- UTF-8 BOM via pandas requires a Python round-trip — fine for tables under ~1M rows.
- For very large tables, deliver Parquet to engineers and a filtered Excel CSV slice to business users.
- Round numerics before export to avoid `129.989999999` display artifacts.

## Known Limitations

- Excel row limit is 1,048,576 — split or aggregate larger exports.
- Excel may misinterpret long numeric IDs as scientific notation — cast to `VARCHAR`.
- DuckDB `COPY` does not write UTF-8 BOM natively — use pandas `utf-8-sig` when needed.
- Locale decimal separators (comma vs period) are not auto-detected — document in README.
- Geometry columns are not Excel-friendly — export attributes only or pair with [GeoJSON](geojson_export.md).
- CSV cannot carry multiple sheets — use `.xlsx` via pandas/openpyxl for workbook delivery.

## Related Pages

- [CSV export](csv_export.md)
- [Delivery package](delivery_package.md)
- [Excel ingestion](../02_ingestion/excel.md)

Official reference: [COPY](https://duckdb.org/docs/current/sql/statements/copy.html)
