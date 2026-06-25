# Delivery Package

Bundle `curated` exports, validation results, and metadata into a versioned handoff folder under `data/output/` for stakeholders and downstream systems.

## Purpose

Standardize the `curated → output` delivery step so every handoff includes data files, QA evidence, a human-readable README, and a machine-readable manifest — not loose Parquet/CSV drops.

## When to Use

- Publishing recurring reports to business teams or external partners
- Archiving a pipeline run with reproducible validation artifacts
- GIS + tabular combined deliveries (GeoParquet + Excel CSV + QA summary)
- Sign-off gate after [validation](../09_validation/row_count_reconciliation.md) passes

## SQL Template

Export curated tables into the package `data/` folder:

```sql
-- Tabular
COPY curated.fct_orders
TO 'data/output/delivery_2024-06-25/data/fct_orders.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

COPY curated.fct_orders
TO 'data/output/delivery_2024-06-25/data/fct_orders.csv'
WITH (HEADER, DELIMITER ',');

-- Spatial
INSTALL spatial;
LOAD spatial;

COPY (
  SELECT parcel_id, owner_name, zoning_code, area_sqm, geom
  FROM curated.geo_parcels
  WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
) TO 'data/output/delivery_2024-06-25/data/geo_parcels.parquet'
(FORMAT PARQUET);
```

Write validation summary to `validation/`:

```sql
COPY (
  SELECT
    'fct_orders' AS dataset,
    'row_count' AS check_name,
    CAST(COUNT(*) AS VARCHAR) AS result_value,
    'PASS' AS status
  FROM curated.fct_orders
  UNION ALL
  SELECT
    'fct_orders',
    'sum_amount',
    CAST(ROUND(SUM(amount), 2) AS VARCHAR),
    CASE WHEN SUM(amount) > 0 THEN 'PASS' ELSE 'FAIL' END
  FROM curated.fct_orders
  UNION ALL
  SELECT
    'geo_parcels',
    'invalid_geom',
    CAST(SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) AS VARCHAR),
    CASE WHEN SUM(CASE WHEN NOT ST_IsValid(geom) THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
  FROM curated.geo_parcels
) TO 'data/output/delivery_2024-06-25/validation/summary.csv'
WITH (HEADER, DELIMITER ',');
```

Build `manifest.csv`:

```sql
COPY (
  SELECT
    'fct_orders.parquet' AS file_name,
    'data/fct_orders.parquet' AS relative_path,
    'parquet' AS format,
    'curated.fct_orders' AS source_table,
    CAST(COUNT(*) AS BIGINT) AS row_count
  FROM curated.fct_orders
  UNION ALL
  SELECT
    'geo_parcels.parquet',
    'data/geo_parcels.parquet',
    'geoparquet',
    'curated.geo_parcels',
    COUNT(*)
  FROM curated.geo_parcels
) TO 'data/output/delivery_2024-06-25/manifest.csv'
WITH (HEADER, DELIMITER ',');
```

## Package Structure

```text
data/output/delivery_2024-06-25/
├── data/
│   ├── fct_orders.parquet
│   ├── fct_orders.csv
│   └── geo_parcels.parquet
├── validation/
│   ├── summary.csv
│   └── row_count_reconciliation.csv
├── README.md
└── manifest.csv
```

| Path | Purpose |
|------|---------|
| `data/` | Consumer-facing exports (Parquet, CSV, GeoJSON, GeoParquet) |
| `validation/` | QA results proving the run passed checks |
| `README.md` | Human summary: what, when, who, how to open files |
| `manifest.csv` | Machine index: file name, path, format, source table, row count |

## Notebook Usage

```python
from datetime import date
from pathlib import Path

delivery_date = date.today().isoformat()
pkg = Path(f"data/output/delivery_{delivery_date}")
(pkg / "data").mkdir(parents=True, exist_ok=True)
(pkg / "validation").mkdir(parents=True, exist_ok=True)

con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("""
CREATE OR REPLACE TABLE curated.fct_orders AS
SELECT
  l_orderkey AS order_id,
  CAST(l_shipdate AS DATE) AS order_date,
  l_extendedprice AS amount
FROM read_parquet('https://blobs.duckdb.org/data/lineitem.parquet')
WHERE l_shipdate IS NOT NULL
LIMIT 50000;
""")
```

```python
# Export data files
data_dir = pkg / "data"
con.execute(f"""
  COPY curated.fct_orders
  TO '{data_dir / "fct_orders.parquet"}'
  (FORMAT PARQUET, COMPRESSION ZSTD);
""")
con.execute(f"""
  COPY curated.fct_orders
  TO '{data_dir / "fct_orders.csv"}'
  WITH (HEADER, DELIMITER ',');
""")
```

```python
# Validation summary
val_dir = pkg / "validation"
con.execute(f"""
  COPY (
    SELECT 'fct_orders' AS dataset, COUNT(*) AS row_count,
           SUM(amount) AS total_amount
    FROM curated.fct_orders
  ) TO '{val_dir / "summary.csv"}'
  WITH (HEADER, DELIMITER ',');
""")

# Manifest
con.execute(f"""
  COPY (
    SELECT
      'fct_orders.parquet' AS file_name,
      'data/fct_orders.parquet' AS relative_path,
      'parquet' AS format,
      'curated.fct_orders' AS source_table,
      COUNT(*) AS row_count
    FROM curated.fct_orders
  ) TO '{pkg / "manifest.csv"}'
  WITH (HEADER, DELIMITER ',');
""")
```

```python
# README
readme = f"""# Delivery Package — {delivery_date}

## Contents
- `data/fct_orders.parquet` — primary analytics format (ZSTD compressed)
- `data/fct_orders.csv` — spreadsheet-friendly copy
- `validation/summary.csv` — row counts and amount totals
- `manifest.csv` — file index with row counts

## Source
Built from `curated.fct_orders` via DuckDB workflow template EXP-006.

## Open instructions
- **Parquet**: DuckDB, pandas (`pd.read_parquet`), Polars
- **CSV**: Excel (Data → From Text/CSV) or any spreadsheet tool

## Validation
All checks in `validation/` passed before publish.
"""
(pkg / "README.md").write_text(readme)
```

```python
# Final inventory
for p in sorted(pkg.rglob("*")):
    if p.is_file():
        print(f"{p.relative_to(pkg)}  ({p.stat().st_size:,} bytes)")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{delivery_date}` | `2024-06-25` | ISO date in folder name |
| `{package_root}` | `data/output/delivery_2024-06-25` | Top-level handoff path |
| `{curated_tables}` | `fct_orders`, `geo_parcels` | Tables to export |
| `{formats}` | `parquet`, `csv`, `geojson` | Per-consumer files |
| `{validation_checks}` | row count, sums, spatial validity | Written to `validation/` |
| `{recipient}` | Team or partner name | Document in README |

## Input Table / Query

Typical inputs from the `curated` schema:

```text
curated.fct_orders
curated.dim_customers
curated.mart_monthly_sales
curated.geo_parcels
curated.geo_roads_in_boundary
```

Validation inputs from `validation/` templates — see [validation summary table](../09_validation/validation_summary_table.md).

## Output Path

```text
data/output/delivery_{YYYY-MM-DD}/
data/output/delivery_{YYYY-MM-DD}/data/
data/output/delivery_{YYYY-MM-DD}/validation/
data/output/delivery_{YYYY-MM-DD}/README.md
data/output/delivery_{YYYY-MM-DD}/manifest.csv
```

## Validation After Export

```python
import pandas as pd

manifest = pd.read_csv(pkg / "manifest.csv")
for _, row in manifest.iterrows():
    file_path = pkg / row["relative_path"]
    assert file_path.exists(), f"Missing: {row['relative_path']}"
    if row["format"] == "parquet":
        n = con.sql(f"SELECT COUNT(*) AS n FROM read_parquet('{file_path}')").df().n.iloc[0]
        assert n == row["row_count"], f"Row mismatch for {row['file_name']}"
```

```sql
-- Reconcile manifest row counts to curated
SELECT
  m.file_name,
  m.row_count AS manifest_rows,
  (SELECT COUNT(*) FROM curated.fct_orders) AS curated_rows
FROM read_csv('data/output/delivery_2024-06-25/manifest.csv', header = true) m
WHERE m.source_table = 'curated.fct_orders';
```

```python
# Fail delivery if any validation check failed
val = pd.read_csv(pkg / "validation" / "summary.csv")
if "status" in val.columns:
    assert (val["status"] == "PASS").all(), "Validation failures — do not publish"
```

Manual checklist:

1. Every file in `manifest.csv` exists on disk
2. Row counts in manifest match `read_parquet` / `read_csv` counts
3. `validation/summary.csv` shows PASS for all checks
4. README describes formats and open instructions
5. Spatial files round-trip via `ST_Read` without invalid geometry

## Common Variations

### Spatial + tabular combined package

```text
data/
├── fct_orders.parquet
├── geo_parcels.parquet
├── geo_parcels.geojson          -- web team
└── geo_parcels_attributes.csv   -- Excel users
```

### Checksum file (optional)

```python
import hashlib

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

checksums = []
for f in sorted((pkg / "data").glob("*")):
    checksums.append({"file_name": f.name, "sha256": sha256(f)})

pd.DataFrame(checksums).to_csv(pkg / "validation" / "checksums.csv", index=False)
```

### Attach full validation suite output

```python
# Attach validation summary from the notebook run (write CSV first if needed)
summary_path = val_dir / "validation_summary.csv"
con.execute(f"""
  COPY (
    SELECT * FROM read_csv('{summary_path.as_posix()}')
  ) TO '{(val_dir / "full_suite.csv").as_posix()}'
  WITH (HEADER, DELIMITER ',');
""")
```

### Zip for email / SFTP

```python
import shutil
shutil.make_archive(str(pkg), "zip", pkg.parent, pkg.name)
# Creates data/output/delivery_2024-06-25.zip
```

### Versioned re-delivery

Use a new dated folder per run — never overwrite a published `delivery_*` folder:

```python
pkg = Path(f"data/output/delivery_{date.today().isoformat()}_v2")
```

## Performance Notes

- Build the package in one notebook session after all validation passes — avoid partial publishes.
- Export Parquet first (primary format), then CSV derivatives from the same curated tables.
- ZSTD Parquet keeps multi-file packages small for SFTP transfer.
- Generate manifest last so row counts reflect final exports.
- Checksum large files once — SHA-256 over `data/` is I/O bound, not CPU bound.

## Known Limitations

- DuckDB does not create README or folder structure automatically — use notebook scaffolding.
- `manifest.csv` row counts are point-in-time — document if curated tables change after export.
- Zip archives may exceed email size limits — use object storage links for large spatial packages.
- Validation CSV is evidence, not a substitute for automated CI gates in production pipelines.
- GeoJSON in packages can dominate zip size — include only when the consumer requires it.
- Re-publishing the same date folder overwrites files — use `_v2` suffix or new dates for audit trails.

## Related Pages

- [CSV export](csv_export.md)
- [Parquet export](parquet_export.md)
- [GeoParquet export](geoparquet_export.md)
- [GeoJSON export](geojson_export.md)
- [Excel-ready CSV](excel_ready_csv.md)
- [Validation summary table](../09_validation/validation_summary_table.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Template reference: EXP-006 in [`template_index.md`](../template_index.md)
