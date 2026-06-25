# CSV to Parquet — Worked Example

Load a CSV from `data/raw/`, land it in the **raw** layer, clean and type it in **staging**, validate, and export to Parquet under `data/output/`.

## Workflow

```text
source (orders.csv) → raw.raw_orders → staging.stg_orders → output (orders.parquet)
```

| Layer   | Object              | Location / notes                          |
|---------|---------------------|-------------------------------------------|
| source  | `orders.csv`        | `data/raw/orders.csv`                     |
| raw     | `raw.raw_orders`    | As-ingested snapshot from CSV             |
| staging | `staging.stg_orders`| Typed, trimmed, filtered rows             |
| output  | `orders.parquet`    | `data/output/orders.parquet`              |

## Prerequisites

- [DuckDB](https://duckdb.org/docs/installation/) 1.0+ (CLI or Python package)
- Python 3.10+ with `duckdb` if you run the Python script:

```bash
pip install duckdb
```

Run commands from the **repository root** (`duckeb-docs/`), not from this folder.

## Setup

### 1. Create workflow folders

```bash
mkdir -p data/raw data/output
```

### 2. Place the source CSV

Put `orders.csv` at `data/raw/orders.csv` with these columns (header row required):

| Column         | Example        | Notes                          |
|----------------|----------------|--------------------------------|
| `order_id`     | `1001`         | Business key                     |
| `customer_id`  | `42`           | Foreign key to customers         |
| `order_date`   | `2024-03-15`   | ISO date string in source file   |
| `amount`       | `129.99`       | Order total                      |
| `quantity`     | `3`            | Line quantity                    |
| `order_status` | `shipped`      | `pending`, `shipped`, `cancelled`|

**Option A — seed from a real public dataset (recommended for practice)**

The Python script can download TPC-H `lineitem` rows, aggregate them to one row per `order_id`, and write `data/raw/orders.csv` when the file is missing. See [How to run](#how-to-run).

**Option B — provide your own file**

Use any vendor or open-data export; adjust the staging `SELECT` in `csv_to_parquet.sql` / `csv_to_parquet.py` if column names differ.

### 3. Open a DuckDB database (optional but recommended)

Both runners create `work.duckdb` at the repo root and ensure `raw`, `staging`, and `curated` schemas exist.

## What each step does

### Ingestion

Register `data/raw/orders.csv` as `raw.raw_orders` using `read_csv_auto()` with `sample_size = -1` so types are inferred from the full file.

### Basic EDA

Preview rows, describe the schema, and summarize row counts and nulls before transforming.

### Staging transformation

Build `staging.stg_orders` with:

- `TRY_CAST` for dates and numerics
- `TRIM` on text fields
- Normalized `order_status` values
- Rows dropped when `order_id` is null

### Validation

Checks before export (zero failing rows = pass):

- Staging row count is not zero
- No nulls in required fields: `order_id`, `customer_id`, `order_date`, `amount`
- No duplicate `order_id` values in staging
- Row count reconciliation: staging ≤ raw (drops are expected when filtering bad keys)

### Export

`COPY staging.stg_orders` to `data/output/orders.parquet` with ZSTD compression, then verify the file row count matches staging.

## How to run

### SQL (DuckDB CLI)

From the repository root, after `data/raw/orders.csv` exists:

```bash
duckdb work.duckdb < examples/csv_to_parquet/csv_to_parquet.sql
```

Interactive:

```bash
duckdb work.duckdb
```

```sql
.read examples/csv_to_parquet/csv_to_parquet.sql
```

### Python

From the repository root:

```bash
python examples/csv_to_parquet/csv_to_parquet.py
```

The script will:

1. Create `data/raw/` and `data/output/` if needed
2. Seed `data/raw/orders.csv` from DuckDB public TPC-H data when the file is absent
3. Run ingestion → EDA → staging → validation → export
4. Print validation results and the output path

### Verify the Parquet file

```bash
duckdb -c "SELECT COUNT(*) AS n, MIN(order_date) AS min_date, MAX(order_date) AS max_date FROM read_parquet('data/output/orders.parquet');"
```

Or in Python:

```python
import duckdb
duckdb.sql("SELECT * FROM read_parquet('data/output/orders.parquet') LIMIT 5").show()
```

## Files in this example

| File                 | Purpose                                      |
|----------------------|----------------------------------------------|
| `README.md`          | This guide                                   |
| `csv_to_parquet.sql` | Standalone SQL workflow                      |
| `csv_to_parquet.py`  | Same workflow with optional CSV seeding      |

## Next steps

- Promote `staging.stg_orders` into `curated.fct_orders` with joins and business rules — see `notebooks/01_etl_base.ipynb`
- Add validation helpers from `python/validation_helpers.py`
- For spatial exports, follow `docs/10_export/` GeoParquet patterns

## Related docs

- [CSV ingestion](../../docs/02_ingestion/csv.md)
- [Parquet export](../../docs/10_export/parquet_export.md)
- [Primary key uniqueness](../../docs/09_validation/primary_key_uniqueness.md)
