"""Data-quality validation SQL generators for pipeline layers."""

from __future__ import annotations

import re

_IDENT_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _quote_identifier(name: str) -> str:
    if not _IDENT_PATTERN.match(name):
        raise ValueError(f"Invalid SQL identifier: {name!r}")
    return f'"{name}"'


def _quote_table(table: str) -> str:
    parts = table.split(".")
    if not parts or len(parts) > 2:
        raise ValueError(f"Expected schema.table or table, got: {table!r}")
    return ".".join(_quote_identifier(part) for part in parts)


def _validate_columns(columns: list[str]) -> list[str]:
    if not columns:
        raise ValueError("At least one column is required.")
    for column in columns:
        if not _IDENT_PATTERN.match(column):
            raise ValueError(f"Invalid column name: {column!r}")
    return columns


def required_fields_null_check_sql(
    table: str,
    required_columns: list[str],
    *,
    include_violation_label: bool = True,
    limit: int = 100,
) -> str:
    """Build SQL to list rows where any required column is NULL."""
    required_columns = _validate_columns(required_columns)
    quoted_table = _quote_table(table)

    where_parts = [f"{_quote_identifier(column)} IS NULL" for column in required_columns]
    where_sql = "\n   OR ".join(where_parts)

    select_columns = ",\n  ".join(_quote_identifier(column) for column in required_columns)

    if include_violation_label:
        case_parts = [
            f"WHEN {_quote_identifier(column)} IS NULL THEN '{column}'"
            for column in required_columns
        ]
        case_sql = "\n    ".join(case_parts)
        select_sql = f"{select_columns},\n  CASE\n    {case_sql}\n  END AS first_null_field"
    else:
        select_sql = select_columns

    return f"""
SELECT
  {select_sql}
FROM {quoted_table}
WHERE {where_sql}
LIMIT {int(limit)}
""".strip()


def primary_key_uniqueness_sql(
    table: str,
    key_columns: list[str],
) -> str:
    """Build SQL to return duplicate key groups (zero rows means pass)."""
    key_columns = _validate_columns(key_columns)
    quoted_table = _quote_table(table)

    group_sql = ", ".join(_quote_identifier(column) for column in key_columns)
    select_sql = ",\n  ".join(_quote_identifier(column) for column in key_columns)

    return f"""
SELECT
  {select_sql},
  COUNT(*) AS row_count
FROM {quoted_table}
GROUP BY {group_sql}
HAVING COUNT(*) > 1
ORDER BY row_count DESC
""".strip()


def row_count_reconciliation_sql(
    tables: list[str],
    *,
    compare_to_first: bool = True,
) -> str:
    """Build SQL to compare row counts across pipeline tables.

    *tables* should be ordered by layer, for example
    ``['raw.raw_orders', 'staging.stg_orders', 'curated.fct_orders']``.
    """
    if len(tables) < 2:
        raise ValueError("At least two tables are required.")

    unions: list[str] = []
    for table in tables:
        quoted = _quote_table(table)
        unions.append(f"SELECT '{table}' AS table_name, COUNT(*) AS row_count FROM {quoted}")

    union_sql = "\n  UNION ALL\n  ".join(unions)

    if not compare_to_first:
        return f"""
WITH counts AS (
  {union_sql}
)
SELECT table_name, row_count
FROM counts
ORDER BY table_name
""".strip()

    first_table = tables[0]
    return f"""
WITH counts AS (
  {union_sql}
),
expected AS (
  SELECT row_count AS baseline_count
  FROM counts
  WHERE table_name = '{first_table}'
)
SELECT
  c.table_name,
  c.row_count,
  e.baseline_count,
  c.row_count - e.baseline_count AS delta_from_first,
  CASE
    WHEN c.table_name = '{first_table}' THEN 'BASELINE'
    WHEN c.row_count > e.baseline_count THEN 'FAIL: exceeds baseline'
    WHEN c.row_count < e.baseline_count THEN 'WARN: below baseline'
    ELSE 'OK'
  END AS status
FROM counts c
CROSS JOIN expected e
ORDER BY c.table_name
""".strip()


def referential_integrity_sql(
    child_table: str,
    parent_table: str,
    foreign_key: str,
    *,
    parent_key: str | None = None,
    list_rows: bool = True,
    limit: int = 100,
) -> str:
    """Build SQL to find orphan foreign keys in *child_table*."""
    if not _IDENT_PATTERN.match(foreign_key):
        raise ValueError(f"Invalid foreign key column: {foreign_key!r}")

    parent_key = parent_key or foreign_key
    if not _IDENT_PATTERN.match(parent_key):
        raise ValueError(f"Invalid parent key column: {parent_key!r}")

    child = _quote_table(child_table)
    parent = _quote_table(parent_table)
    child_alias = "c"
    parent_alias = "p"
    fk = _quote_identifier(foreign_key)
    pk = _quote_identifier(parent_key)

    if list_rows:
        return f"""
SELECT
  {child_alias}.*
FROM {child} AS {child_alias}
LEFT JOIN {parent} AS {parent_alias}
  ON {child_alias}.{fk} = {parent_alias}.{pk}
WHERE {parent_alias}.{pk} IS NULL
  AND {child_alias}.{fk} IS NOT NULL
LIMIT {int(limit)}
""".strip()

    return f"""
SELECT COUNT(*) AS orphan_rows
FROM {child} AS {child_alias}
LEFT JOIN {parent} AS {parent_alias}
  ON {child_alias}.{fk} = {parent_alias}.{pk}
WHERE {parent_alias}.{pk} IS NULL
  AND {child_alias}.{fk} IS NOT NULL
""".strip()
