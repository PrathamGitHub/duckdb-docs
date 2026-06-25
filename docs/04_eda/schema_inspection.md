# Schema Inspection

List column names, data types, and nullability for any workflow table before transforms or exports.

## Purpose

Document the structural contract of `raw`, `staging`, or `curated` tables. Schema inspection answers "what columns exist and what types did DuckDB infer?"

## When to Use

- Right after ingest — before assuming types are correct
- When joining `raw.raw_orders` to `raw.raw_customers` — confirm key column types match
- After `staging` builds — verify casts applied (`VARCHAR` → `DATE`, `DOUBLE`)
- Before publishing to `output` — ensure export columns match consumer expectations

## SQL Template

Quick describe (DuckDB-native):

```sql
DESCRIBE raw.raw_orders;
```

Information schema (portable, filterable):

```sql
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name = 'raw_orders'
ORDER BY ordinal_position;
```

Compare schemas across layers:

```sql
SELECT
  table_schema,
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE (table_schema, table_name) IN (
  ('raw', 'raw_orders'),
  ('staging', 'stg_orders')
)
ORDER BY table_schema, table_name, ordinal_position;
```

List all tables in workflow schemas:

```sql
SELECT table_schema, table_name, estimated_size
FROM duckdb_tables()
WHERE table_schema IN ('raw', 'staging', 'curated')
ORDER BY table_schema, table_name;
```

## Notebook Usage

```python
# Single table
schema = con.sql("DESCRIBE raw.raw_customers").df()
schema

# Programmatic column list for dynamic SQL (null/distinct profiles)
cols = con.sql("""
  SELECT column_name, data_type
  FROM information_schema.columns
  WHERE table_schema = 'raw' AND table_name = 'raw_orders'
  ORDER BY ordinal_position
""").df()
cols
```

Practice dataset:

```python
con.sql("DESCRIBE raw.raw_population_csv").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `table_schema` | `raw`, `staging`, `curated` | Workflow layer |
| `table_name` | `raw_orders`, `stg_orders`, `raw_customers` | Unqualified table name in `information_schema` |
| Schema compare list | pairs of `(schema, table)` | Cross-layer drift checks |

## Expected Output

`DESCRIBE` returns one row per column with:

| column_name | column_type | null | key | default | extra |
|-------------|-------------|------|-----|---------|-------|

`information_schema.columns` returns standard metadata including `data_type` and `is_nullable`.

## Common Variations

### Geometry column check (spatial tables)

```sql
DESCRIBE raw.raw_parcels_gdb;

SELECT
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name = 'raw_parcels_gdb'
  AND data_type LIKE '%GEOMETRY%';
```

### Column count summary

```sql
SELECT
  table_schema,
  table_name,
  COUNT(*) AS column_count
FROM information_schema.columns
WHERE table_schema IN ('raw', 'staging')
GROUP BY 1, 2
ORDER BY 1, 2;
```

### Find VARCHAR columns that should be numeric in staging

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw'
  AND table_name = 'raw_orders'
  AND data_type IN ('VARCHAR', 'STRING')
  AND column_name IN ('amount', 'quantity', 'order_id');
```

## Interpretation Guidance

- **Inferred `VARCHAR` on IDs** — common after CSV ingest; leading zeros and alphanumeric IDs should stay `VARCHAR`, not `INTEGER`.
- **`DOUBLE` on money fields** — acceptable for EDA; consider `DECIMAL` in `curated` for reporting.
- **Missing expected columns** — upstream schema change; block `staging` until resolved.
- **Type mismatch across layers** — e.g. `customer_id` as `BIGINT` in `raw` and `VARCHAR` in `staging` — fix before joins.

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Wrong inferred types | Add explicit `types` at ingest or `TRY_CAST` in `staging` |
| Extra unexpected columns | Document in ingest notes; drop or rename in `staging` |
| Nullable key columns | [null_profile](null_profile.md) on key fields |
| Ready for profiling | [row_counts](row_counts.md), [null_profile](null_profile.md), [distinct_profile](distinct_profile.md) |

## Related Pages

- [Preview rows](preview_rows.md)
- [Null profile](null_profile.md)
- [Naming conventions](../00_overview/naming_conventions.md)

Official reference: [DuckDB DESCRIBE](https://duckdb.org/docs/current/guides/meta/describe.html)
