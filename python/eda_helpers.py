"""Exploratory data analysis helpers for DuckDB tables."""

from __future__ import annotations

import re

import duckdb

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


def preview_table(
    con: duckdb.DuckDBPyConnection,
    table: str,
    *,
    limit: int = 20,
) -> duckdb.DuckDBPyRelation:
    """Return the first *limit* rows from *table*."""
    if limit < 1:
        raise ValueError("limit must be at least 1.")
    quoted = _quote_table(table)
    return con.sql(f"SELECT * FROM {quoted} LIMIT {int(limit)}")


def row_count(con: duckdb.DuckDBPyConnection, table: str) -> int:
    """Return the total row count for *table*."""
    quoted = _quote_table(table)
    result = con.sql(f"SELECT COUNT(*) AS row_count FROM {quoted}").fetchone()
    return int(result[0])


def generate_null_profile_sql(table: str, columns: list[str]) -> str:
    """Build SQL that returns one row per column with null counts and percentages."""
    columns = _validate_columns(columns)
    quoted_table = _quote_table(table)

    unions: list[str] = []
    for column in columns:
        col = _quote_identifier(column)
        unions.append(
            f"SELECT '{column}' AS column_name, "
            f"COUNT(*) - COUNT({col}) AS null_count FROM base"
        )

    union_sql = "\n  UNION ALL\n  ".join(unions)
    return f"""
WITH base AS (
  SELECT * FROM {quoted_table}
),
metrics AS (
  {union_sql}
)
SELECT
  column_name,
  null_count,
  (SELECT COUNT(*) FROM base) AS total_rows,
  ROUND(100.0 * null_count / (SELECT COUNT(*) FROM base), 2) AS null_pct
FROM metrics
ORDER BY null_count DESC
""".strip()


def generate_distinct_profile_sql(table: str, columns: list[str]) -> str:
    """Build SQL that returns one row per column with distinct value counts."""
    columns = _validate_columns(columns)
    quoted_table = _quote_table(table)

    unions: list[str] = []
    for column in columns:
        col = _quote_identifier(column)
        unions.append(
            f"SELECT '{column}' AS column_name, "
            f"COUNT(DISTINCT {col}) AS distinct_count FROM base"
        )

    union_sql = "\n  UNION ALL\n  ".join(unions)
    return f"""
WITH base AS (
  SELECT * FROM {quoted_table}
)
{union_sql}
ORDER BY distinct_count DESC
""".strip()


def numeric_summary(
    con: duckdb.DuckDBPyConnection,
    table: str,
    columns: list[str],
) -> duckdb.DuckDBPyRelation:
    """Return min, max, avg, and stddev for numeric *columns*."""
    columns = _validate_columns(columns)
    quoted_table = _quote_table(table)

    parts: list[str] = []
    for column in columns:
        col = _quote_identifier(column)
        parts.append(
            f"MIN({col}) AS {_quote_identifier(f'{column}_min')}, "
            f"MAX({col}) AS {_quote_identifier(f'{column}_max')}, "
            f"AVG({col}) AS {_quote_identifier(f'{column}_avg')}, "
            f"STDDEV_SAMP({col}) AS {_quote_identifier(f'{column}_stddev')}"
        )

    select_sql = ",\n  ".join(parts)
    return con.sql(f"SELECT\n  {select_sql}\nFROM {quoted_table}")


def categorical_frequency(
    con: duckdb.DuckDBPyConnection,
    table: str,
    column: str,
    *,
    top_n: int = 20,
) -> duckdb.DuckDBPyRelation:
    """Return the top *top_n* values for a categorical *column* with counts and percentages."""
    _validate_columns([column])
    if top_n < 1:
        raise ValueError("top_n must be at least 1.")

    quoted_table = _quote_table(table)
    col = _quote_identifier(column)
    return con.sql(
        f"""
        SELECT
          {col} AS value,
          COUNT(*) AS row_count,
          ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
        FROM {quoted_table}
        GROUP BY 1
        ORDER BY row_count DESC
        LIMIT {int(top_n)}
        """
    )
