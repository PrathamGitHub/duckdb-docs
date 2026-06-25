# Duplicate Check

Find duplicate business keys or fully duplicated rows before promoting data to `curated` or `output`.

## Purpose

Detect records that violate expected grain (one row per `order_id`, one row per `customer_id`) or exact duplicate lines from bad joins and re-ingest.

## When to Use

- After `raw` ingest on `raw.raw_orders` and `raw.raw_customers`
- Before declaring a primary key in `staging` or `curated`
- When [row_counts](row_counts.md) shows `COUNT(*) > COUNT(DISTINCT key)`
- After deduplication logic — confirm duplicates are gone

## SQL Template

Duplicate business key (`order_id`):

```sql
SELECT
  order_id,
  COUNT(*) AS row_count
FROM raw.raw_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, order_id;
```

Duplicate composite key (`customer_id`, `order_date`):

```sql
SELECT
  customer_id,
  order_date,
  COUNT(*) AS row_count
FROM staging.stg_orders
GROUP BY customer_id, order_date
HAVING COUNT(*) > 1
ORDER BY row_count DESC;
```

Full-row duplicates (all columns match):

```sql
SELECT *
FROM (
  SELECT
    *,
    COUNT(*) OVER (PARTITION BY order_id, customer_id, order_date, amount, order_status) AS dup_count
  FROM raw.raw_orders
) d
WHERE dup_count > 1
ORDER BY order_id, customer_id;
```

Summary metric (how many keys are duplicated):

```sql
SELECT
  COUNT(*) AS duplicate_key_groups,
  SUM(row_count - 1) AS extra_rows
FROM (
  SELECT order_id, COUNT(*) AS row_count
  FROM raw.raw_orders
  GROUP BY order_id
  HAVING COUNT(*) > 1
) dup;
```

## Notebook Usage

```python
dupes = con.sql("""
  SELECT order_id, COUNT(*) AS n
  FROM raw.raw_orders
  GROUP BY 1
  HAVING COUNT(*) > 1
  ORDER BY n DESC
  LIMIT 50
""").df()
dupes

# Customer email duplicates (if column exists)
con.sql("""
  SELECT email, COUNT(*) AS n
  FROM raw.raw_customers
  WHERE email IS NOT NULL
  GROUP BY 1
  HAVING COUNT(*) > 1
""").df()
```

Practice dataset — duplicate country-year should not exist:

```python
con.sql("""
  SELECT country_name, year, COUNT(*) AS n
  FROM raw.raw_population_csv
  GROUP BY 1, 2
  HAVING COUNT(*) > 1
""").df()
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| Key column(s) | `order_id` or `(customer_id, order_date)` | Expected unique grain |
| `{schema}.{table}` | `staging.stg_orders` | Layer under test |
| `HAVING` threshold | `COUNT(*) > 1` | Use `> 0` only in summary subqueries |
| `LIMIT` | `50` | Cap duplicate listing in notebooks |

## Expected Output

**Duplicate key listing:**

| order_id | row_count |
|----------|-----------|
| ORD-0042 | 3 |
| ORD-1099 | 2 |

**Summary:**

| duplicate_key_groups | extra_rows |
|----------------------|------------|
| 15 | 18 |

Zero rows means no duplicates at the tested grain.

## Common Variations

### Keep-latest duplicate inspection (before dedupe)

```sql
SELECT *
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY order_date DESC
    ) AS rn
  FROM raw.raw_orders
) ranked
WHERE rn > 1;
```

### Duplicates excluding null keys

```sql
SELECT customer_id, COUNT(*) AS n
FROM raw.raw_customers
WHERE customer_id IS NOT NULL
GROUP BY 1
HAVING COUNT(*) > 1;
```

### Cross-table duplicate customer IDs

```sql
SELECT c.customer_id
FROM raw.raw_customers c
INNER JOIN (
  SELECT customer_id
  FROM raw.raw_customers
  GROUP BY 1
  HAVING COUNT(*) > 1
) d ON c.customer_id = d.customer_id
ORDER BY c.customer_id;
```

### Duplicate check on ingested file batches

```sql
SELECT order_id, source_file, COUNT(*) AS n
FROM raw.raw_orders
GROUP BY 1, 2
HAVING COUNT(*) > 1;
```

## Interpretation Guidance

- **Few duplicates with round `row_count`** — often double ingest or overlapping glob files; fix at `raw` re-ingest.
- **Many duplicates on natural key** — source system allows repeats; define dedupe rule in `staging` (keep latest, sum amounts, etc.).
- **Full-row duplicates** — harmless for analytics but wasteful; `DISTINCT` or `GROUP BY ALL` in `staging`.
- **No duplicates but orphan keys** — orders referencing missing customers; join audit separate from this check.

## Follow-up Actions

| Finding | Action |
|---------|--------|
| Duplicate keys | Deduplicate in `staging` with `ROW_NUMBER()` or aggregate |
| Double ingest | Drop/replace `raw` table; fix glob or ingest idempotency |
| Null keys duplicated | [null_profile](null_profile.md); filter nulls before uniqueness test |
| Clean keys | Proceed to [numeric_summary](numeric_summary.md) or `curated` builds |

## Related Pages

- [Row counts](row_counts.md)
- [Distinct profile](distinct_profile.md)
- [Null profile](null_profile.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB GROUP BY / HAVING](https://duckdb.org/docs/current/sql/query_syntax/groupby.html)
