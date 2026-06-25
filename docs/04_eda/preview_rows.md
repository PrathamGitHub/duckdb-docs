# Preview Rows

Quickly scan sample records from a `raw` or `staging` table before deeper profiling.

## Purpose

Surface column values, formatting quirks, and obvious data issues without running full aggregates. Preview rows are the first EDA step after ingest.

## When to Use

- Immediately after `source → raw` ingest
- Before writing `staging` transforms — confirm delimiter parsing, date formats, and ID shapes
- When a stakeholder asks "what does this dataset look like?"
- After schema changes upstream — compare a fresh sample to prior runs

Run on `raw.raw_orders`, `staging.stg_orders`, or `raw.raw_customers` depending on which layer you are validating.

## SQL Template

Head sample (deterministic, fast):

```sql
SELECT *
FROM raw.raw_orders
LIMIT 20;
```

Random sample (better coverage on large tables):

```sql
SELECT *
FROM staging.stg_orders
USING SAMPLE 20;
```

Stratified preview by a key column:

```sql
SELECT *
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY order_status ORDER BY order_id) AS rn
  FROM raw.raw_orders
) s
WHERE rn <= 3
ORDER BY order_status, order_id;
```

Column subset (focus on business keys):

```sql
SELECT order_id, customer_id, order_date, amount, order_status
FROM raw.raw_orders
LIMIT 25;
```

## Notebook Usage

After the [notebook setup cell](../01_setup/notebook_setup_cell.md) and ingest:

```python
# Practice dataset: population CSV already in raw (see workflow_layers.md)
con.sql("SELECT * FROM raw.raw_population_csv LIMIT 10").df()

# Orders-style preview after you load raw.raw_orders
preview = con.sql("""
  SELECT *
  FROM raw.raw_orders
  USING SAMPLE 15
""").df()
preview
```

Display side-by-side layers:

```python
for table in ["raw.raw_orders", "staging.stg_orders"]:
    print(f"\n--- {table} ---")
    display(con.sql(f"SELECT * FROM {table} LIMIT 5").df())
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `{schema}.{table}` | `raw.raw_orders` | Target layer and table |
| `LIMIT n` | `20` | Row cap for head sample |
| `USING SAMPLE n` | `15` | Approximate random sample size |
| Column list | `order_id, amount` | Narrow projection for wide tables |
| `PARTITION BY` column | `order_status` | Stratified sampling key |

## Expected Output

A small result set (typically 5–50 rows) with one row per record and one column per field. You should see:

- Whether headers mapped to sensible column names
- Leading zeros, currency symbols, or mixed date formats in string columns
- Obvious sentinel values (`N/A`, `9999`, empty strings)

## Common Variations

### Exclude geometry blobs (spatial tables)

```sql
SELECT * EXCLUDE (geom)
FROM raw.raw_parcels_gdb
LIMIT 10;
```

### Preview with row number for notebook discussion

```sql
SELECT ROW_NUMBER() OVER () AS preview_row, *
FROM raw.raw_customers
LIMIT 20;
```

### Compare raw vs staging for the same keys

```sql
SELECT 'raw' AS layer, r.*
FROM raw.raw_orders r
WHERE order_id IN ('ORD-1001', 'ORD-1002', 'ORD-1003')
UNION ALL
SELECT 'staging' AS layer, s.*
FROM staging.stg_orders s
WHERE order_id IN ('ORD-1001', 'ORD-1002', 'ORD-1003');
```

### HTTP source without local mirror

```sql
SELECT country_name, year, value
FROM raw.raw_population_csv
LIMIT 10;
```

## Interpretation Guidance

- **Uniform formatting** in ID and date columns suggests clean ingest; mixed formats signal work needed in `staging`.
- **Unexpected nulls** in preview rows warrant a full [null profile](null_profile.md) — a few nulls in sample may hide a 40% null rate overall.
- **Duplicate-looking rows** in the sample are not proof of duplicates — run [duplicate_check](duplicate_check.md).
- **Extreme values** in preview (negative amounts, year `2099`) trigger [numeric_summary](numeric_summary.md) and [date_range_check](date_range_check.md).

## Follow-up Actions

| Observation | Next step |
|-------------|-----------|
| Wrong types or column names | Fix ingest options; update `staging` casts — [schema_inspection](schema_inspection.md) |
| Suspicious nulls | [null_profile](null_profile.md) |
| Possible duplicate keys | [duplicate_check](duplicate_check.md) |
| Need volume context | [row_counts](row_counts.md) |
| Ready to clean | Promote rules to `staging.stg_*` per [workflow layers](../00_overview/workflow_layers.md) |

## Related Pages

- [Schema inspection](schema_inspection.md)
- [Row counts](row_counts.md)
- [CSV ingestion](../02_ingestion/csv.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB SELECT](https://duckdb.org/docs/current/sql/query_syntax/select.html)
