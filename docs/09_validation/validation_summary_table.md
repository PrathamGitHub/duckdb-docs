# Validation Summary Table

Collect individual check results into one queryable table for notebooks, delivery packages, and CI gates.

## Purpose

Standardize validation output shape (`check_name`, `table_name`, `status`, `violating_rows`, `run_ts`) so every template in this folder can feed a single pass/fail dashboard.

## When to Use

- End of `notebooks/03_validation_checks.ipynb` — one DataFrame for stakeholders
- Before [export delivery package](../08_spatial_transformation/export_ready_spatial_layer.md)
- In repeatable pipelines — append one row per check per run
- CI / automation — fail build if any `status = 'FAIL'`

## SQL Template

Create a persistent summary table:

```sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE TABLE IF NOT EXISTS curated.validation_results (
  run_id VARCHAR,
  run_ts TIMESTAMP,
  check_id VARCHAR,
  check_name VARCHAR,
  table_name VARCHAR,
  status VARCHAR,           -- 'PASS' or 'FAIL'
  violating_rows BIGINT,    -- 0 for summary checks; interpret metric separately
  detail VARCHAR,
  PRIMARY KEY (run_id, check_id)
);
```

Populate from scalar subqueries (violation-style checks return 0 on pass):

```sql
INSERT INTO curated.validation_results
SELECT
  'run_20250625_143000' AS run_id,
  CURRENT_TIMESTAMP AS run_ts,
  v.check_id,
  v.check_name,
  v.table_name,
  CASE WHEN v.violating_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  v.violating_rows,
  v.detail
FROM (
  SELECT
    'VAL-002' AS check_id,
    'primary_key_uniqueness' AS check_name,
    'staging.stg_orders' AS table_name,
    (SELECT COUNT(*) FROM (
      SELECT order_id FROM staging.stg_orders GROUP BY 1 HAVING COUNT(*) > 1
    )) AS violating_rows,
    'key: order_id' AS detail
  UNION ALL
  SELECT
    'VAL-003',
    'required_field_null_check',
    'staging.stg_orders',
    (SELECT COUNT(*) FROM staging.stg_orders
     WHERE order_id IS NULL OR customer_id IS NULL
        OR order_date IS NULL OR amount IS NULL),
    'required: order_id, customer_id, order_date, amount'
  UNION ALL
  SELECT
    'VAL-004',
    'referential_integrity',
    'staging.stg_orders → curated.dim_customers',
    (SELECT COUNT(*) FROM staging.stg_orders o
     LEFT JOIN curated.dim_customers d ON o.customer_id = d.customer_id
     WHERE d.customer_id IS NULL AND o.customer_id IS NOT NULL),
    'fk: customer_id'
  UNION ALL
  SELECT
    'VAL-006',
    'category_domain_check',
    'staging.stg_orders.order_status',
    (SELECT COUNT(*) FROM staging.stg_orders
     WHERE order_status IS NOT NULL
       AND order_status NOT IN ('pending', 'shipped', 'cancelled', 'returned')),
    'domain: pending, shipped, cancelled, returned'
  UNION ALL
  SELECT
    'VAL-009',
    'spatial_validity_check',
    'curated.geo_parcels',
    (SELECT COUNT(*) FROM curated.geo_parcels
     WHERE geom IS NULL OR ST_IsEmpty(geom) OR NOT ST_IsValid(geom)),
    'geom validity gate'
) v;
```

View latest run summary:

```sql
SELECT
  check_id,
  check_name,
  table_name,
  status,
  violating_rows,
  detail
FROM curated.validation_results
WHERE run_id = 'run_20250625_143000'
ORDER BY check_id;
```

Fail-fast gate:

```sql
SELECT COUNT(*) AS failed_checks
FROM curated.validation_results
WHERE run_id = 'run_20250625_143000'
  AND status = 'FAIL';
-- failed_checks = 0 → pipeline pass
```

## Notebook Usage

```python
import uuid
from datetime import datetime, timezone

RUN_ID = f"run_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"

checks = [
    {
        "check_id": "VAL-002",
        "check_name": "primary_key_uniqueness",
        "table_name": "staging.stg_orders",
        "sql": """
          SELECT COUNT(*) AS n FROM (
            SELECT order_id FROM staging.stg_orders GROUP BY 1 HAVING COUNT(*) > 1
          )
        """,
        "detail": "key: order_id",
    },
    {
        "check_id": "VAL-003",
        "check_name": "required_field_null_check",
        "table_name": "staging.stg_orders",
        "sql": """
          SELECT COUNT(*) AS n FROM staging.stg_orders
          WHERE order_id IS NULL OR customer_id IS NULL
             OR order_date IS NULL OR amount IS NULL
        """,
        "detail": "required core fields",
    },
]

rows = []
for c in checks:
    n = con.sql(c["sql"]).fetchone()[0]
    rows.append({
        "run_id": RUN_ID,
        "check_id": c["check_id"],
        "check_name": c["check_name"],
        "table_name": c["table_name"],
        "violating_rows": n,
        "status": "PASS" if n == 0 else "FAIL",
        "detail": c["detail"],
    })

import pandas as pd
summary = pd.DataFrame(rows)
summary

assert (summary.status == "PASS").all(), "Validation failures:\n" + summary.to_string()
```

Export summary to `output`:

```python
con.register("validation_summary_df", summary)
con.sql(f"""
  COPY validation_summary_df
  TO 'data/output/validation/{RUN_ID}_summary.parquet'
  (FORMAT PARQUET)
""")
```

## Parameters to Replace

| Parameter | Example | Notes |
|-----------|---------|-------|
| `run_id` | `run_20250625_143000` | Unique per pipeline execution |
| `check_id` | `VAL-002` … `VAL-009` | Matches [template index](../../template_index.md) |
| `violating_rows` | `0` | For violation queries; use `detail` for summary metrics |
| Summary checks | [row count](row_count_reconciliation.md), [aggregate](aggregate_reconciliation.md) | Store metrics in `detail`; set `status` from business rules |
| Fail-fast | `assert all PASS` | Notebook vs batch mode |

## Expected Output

| check_id | check_name | table_name | status | violating_rows | detail |
|----------|------------|------------|--------|----------------|--------|
| VAL-002 | primary_key_uniqueness | staging.stg_orders | PASS | 0 | key: order_id |
| VAL-003 | required_field_null_check | staging.stg_orders | PASS | 0 | required: order_id, … |
| VAL-004 | referential_integrity | staging.stg_orders → curated.dim_customers | PASS | 0 | fk: customer_id |
| VAL-006 | category_domain_check | staging.stg_orders.order_status | FAIL | 2 | domain: pending, … |
| VAL-009 | spatial_validity_check | curated.geo_parcels | PASS | 0 | geom validity gate |

**Gate query:** `failed_checks = 0` → overall **pass**.

## Pass/Fail Interpretation

| Pattern | Rule |
|---------|------|
| Violation checks ([PK](primary_key_uniqueness.md), [nulls](required_field_null_check.md), [FK](referential_integrity.md), [domain](category_domain_check.md), [range](value_range_check.md), [dates](date_range_validation.md), [spatial](spatial_validity_check.md)) | `violating_rows = 0` → **PASS** |
| [Row count reconciliation](row_count_reconciliation.md) | Set `status` from documented tolerance; put counts in `detail` |
| [Aggregate reconciliation](aggregate_reconciliation.md) | `status = PASS` when delta within tolerance; store `delta` in `detail` |
| Any `FAIL` row | Overall pipeline **fail** unless explicitly waived with documented reason |

## Common Variations

### Include summary checks as rows

```sql
SELECT
  'VAL-001' AS check_id,
  'row_count_reconciliation' AS check_name,
  'raw → staging → fct' AS table_name,
  CASE
    WHEN (SELECT COUNT(*) FROM staging.stg_orders) <= (SELECT COUNT(*) FROM raw.raw_orders)
     AND (SELECT COUNT(*) FROM curated.fct_orders) <= (SELECT COUNT(*) FROM staging.stg_orders)
    THEN 'PASS' ELSE 'FAIL'
  END AS status,
  0 AS violating_rows,
  'raw=' || (SELECT COUNT(*)::VARCHAR FROM raw.raw_orders)
    || ', stg=' || (SELECT COUNT(*)::VARCHAR FROM staging.stg_orders)
    || ', fct=' || (SELECT COUNT(*)::VARCHAR FROM curated.fct_orders) AS detail;
```

### Latest run view

```sql
CREATE OR REPLACE VIEW curated.v_validation_latest AS
SELECT *
FROM curated.validation_results
WHERE run_id = (
  SELECT run_id FROM curated.validation_results
  ORDER BY run_ts DESC LIMIT 1
);
```

### Append-only history (no overwrite)

```sql
-- Use INSERT only; never DELETE production validation history without policy
INSERT INTO curated.validation_results SELECT ...;
```

### Markdown report cell in notebook

```python
def to_markdown_report(df: pd.DataFrame) -> str:
    passed = (df.status == "PASS").sum()
    total = len(df)
    lines = [
        f"# Validation Report — {RUN_ID}",
        f"**Result:** {passed}/{total} checks passed",
        "",
        df.to_markdown(index=False),
    ]
    return "\n".join(lines)

print(to_markdown_report(summary))
```

## How to Document Results

1. **Run metadata** — `run_id`, UTC timestamp, DuckDB version, dataset version or git commit.
2. **Per-check rows** — insert into `curated.validation_results` or save Parquet under `data/output/validation/`.
3. **Failure appendix** — link Parquet samples of violating rows (e.g. `VAL-004_orphans.parquet`).
4. **Waivers** — if a check is intentionally failed, add `detail = 'WAIVED: reason'` and require human sign-off.
5. **Delivery README** — copy the summary table into the export package manifest.

Example manifest snippet:

```text
Validation run: run_20250625_143000
Overall: PASS (7/7)
Artifacts:
  - data/output/validation/run_20250625_143000_summary.parquet
  - data/output/validation/VAL-004_orphans.parquet (empty on pass)
```

## Related Pages

- [Row count reconciliation](row_count_reconciliation.md)
- [Primary key uniqueness](primary_key_uniqueness.md)
- [Required field null check](required_field_null_check.md)
- [Referential integrity](referential_integrity.md)
- [Value range check](value_range_check.md)
- [Category domain check](category_domain_check.md)
- [Date range validation](date_range_validation.md)
- [Aggregate reconciliation](aggregate_reconciliation.md)
- [Spatial validity check](spatial_validity_check.md)
- [Workflow layers](../00_overview/workflow_layers.md)

Official reference: [DuckDB CREATE TABLE](https://duckdb.org/docs/current/sql/statements/create_table.html)
