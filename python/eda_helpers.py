"""Exploratory data analysis helpers for DuckDB tables."""

from __future__ import annotations

import math
import re
from typing import TYPE_CHECKING

import duckdb

if TYPE_CHECKING:
    import pandas as pd

_IDENT_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_NUMERIC_TYPES = {
    "TINYINT",
    "SMALLINT",
    "INTEGER",
    "BIGINT",
    "HUGEINT",
    "UTINYINT",
    "USMALLINT",
    "UINTEGER",
    "UBIGINT",
    "UHUGEINT",
    "FLOAT",
    "DOUBLE",
    "DECIMAL",
    "REAL",
}


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


def list_table_columns(
    con: duckdb.DuckDBPyConnection,
    table: str,
) -> list[tuple[str, str]]:
    """Return ``(column_name, column_type)`` pairs from ``DESCRIBE``."""
    quoted = _quote_table(table)
    rows = con.sql(f"DESCRIBE {quoted}").fetchall()
    return [(row[0], row[1]) for row in rows]


def _is_numeric_type(column_type: str) -> bool:
    return column_type.split("(")[0].upper() in _NUMERIC_TYPES


def _parse_schema_table(table: str) -> tuple[str, str]:
    parts = table.split(".")
    if len(parts) != 2:
        raise ValueError(f"Expected schema.table, got: {table!r}")
    return parts[0], parts[1]


def generate_top_values_sql(table: str, column: str, *, top_n: int = 10) -> str:
    """SQL for top-N values with row counts and percentages for one column."""
    _validate_columns([column])
    if top_n < 1:
        raise ValueError("top_n must be at least 1.")

    quoted_table = _quote_table(table)
    col = _quote_identifier(column)
    return f"""
SELECT
  CAST({col} AS VARCHAR) AS value,
  COUNT(*) AS row_count,
  100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS pct
FROM {quoted_table}
GROUP BY 1
ORDER BY row_count DESC
LIMIT {int(top_n)}
""".strip()


def generate_numeric_column_stats_sql(table: str, column: str) -> str:
    """SQL returning min/max/quantiles/mean/stddev for one numeric column."""
    _validate_columns([column])
    quoted_table = _quote_table(table)
    col = _quote_identifier(column)
    return f"""
SELECT
  MIN({col}) AS min,
  MAX({col}) AS max,
  quantile_cont({col}, 0.25) AS q1,
  quantile_cont({col}, 0.5) AS median,
  quantile_cont({col}, 0.75) AS q3,
  AVG({col}) AS mean,
  STDDEV_SAMP({col}) AS std
FROM {quoted_table}
WHERE {col} IS NOT NULL
""".strip()


def generate_outlier_count_sql(
    table: str,
    column: str,
    *,
    lower: float,
    upper: float,
) -> str:
    """SQL returning a count of rows outside ``[lower, upper]`` for one column."""
    _validate_columns([column])
    quoted_table = _quote_table(table)
    col = _quote_identifier(column)
    return f"""
SELECT COUNT(*) AS outlier_count
FROM {quoted_table}
WHERE {col} IS NOT NULL
  AND ({col} < {lower} OR {col} > {upper})
""".strip()


def _format_top_values(
    con: duckdb.DuckDBPyConnection,
    table: str,
    column: str,
    *,
    top_n: int,
) -> str:
    sql = generate_top_values_sql(table, column, top_n=top_n)
    rows = con.sql(sql).fetchall()
    parts: list[str] = []
    for value, _count, pct in rows:
        parts.append(f"{value} ({math.floor(pct)}%)")
    return ", ".join(parts)


def _table_estimated_bytes(con: duckdb.DuckDBPyConnection, table: str) -> int | None:
    schema_name, table_name = _parse_schema_table(table)
    try:
        row = con.sql(
            """
            SELECT estimated_size
            FROM duckdb_tables()
            WHERE schema_name = ? AND table_name = ?
            LIMIT 1
            """,
            params=[schema_name, table_name],
        ).fetchone()
    except duckdb.Error:
        return None
    return int(row[0]) if row and row[0] is not None else None


def _format_memory(kb: float) -> str:
    if kb > 1024 * 1024:
        return f"{round(kb / 1024 / 1024, 1)}+ GB"
    if kb > 1024:
        return f"{round(kb / 1024, 1)}+ MB"
    return f"{round(kb, 1)}+ KB"


def get_table_summary(
    con: duckdb.DuckDBPyConnection,
    table: str,
    *,
    print_summary: bool = True,
    properties_as_columns: bool = True,
    top_n: int = 10,
    exclude: list[str] | None = None,
) -> pd.DataFrame:
    """Build a column-oriented EDA profile using DuckDB SQL (minimal pandas assembly)."""
    import pandas as pd

    exclude_set = set(exclude or [])
    columns_meta = [
        (name, dtype)
        for name, dtype in list_table_columns(con, table)
        if name not in exclude_set
    ]
    if not columns_meta:
        raise ValueError(f"No columns to profile on {table!r}")

    column_names = [name for name, _ in columns_meta]
    n_rows = row_count(con, table)
    n_cols = len(column_names)

    print(f"RangeIndex: {n_rows} entries; Data columns (total {n_cols} columns)")
    estimated_bytes = _table_estimated_bytes(con, table)
    if estimated_bytes is not None:
        print(f"memory usage: {_format_memory(estimated_bytes / 1024)}\n")
    else:
        print("memory usage: (unavailable — table not in catalog)\n")

    null_df = con.sql(generate_null_profile_sql(table, column_names)).df()
    null_map = dict(zip(null_df["column_name"], null_df["null_count"]))

    distinct_df = con.sql(generate_distinct_profile_sql(table, column_names)).df()
    distinct_map = dict(zip(distinct_df["column_name"], distinct_df["distinct_count"]))

    top_label = f"Top {top_n} Unique Values"
    top_map = {
        column: _format_top_values(con, table, column, top_n=top_n)
        for column in column_names
    }

    property_rows: dict[str, dict[str, object]] = {
        "dtype": {name: dtype for name, dtype in columns_meta},
        "Missing Counts": {name: int(null_map[name]) for name in column_names},
        "nUniques": {name: int(distinct_map[name]) for name in column_names},
        top_label: top_map,
    }

    numeric_stat_names = [
        "min",
        "max",
        "LW (1.5)",
        "Q1",
        "Median",
        "Q3",
        "UW (1.5)",
        "Outlier Count (1.5*IQR)",
        "mean-3*std",
        "mean",
        "std",
        "mean+3*std",
        "Outlier Count (3*std)",
    ]
    for stat_name in numeric_stat_names:
        property_rows[stat_name] = {name: math.nan for name in column_names}

    for name, dtype in columns_meta:
        if not _is_numeric_type(dtype):
            continue

        stats = con.sql(generate_numeric_column_stats_sql(table, name)).fetchone()
        if not stats or stats[0] is None:
            continue

        min_val, max_val, q1, median, q3, mean, std = stats
        min_val = float(min_val)
        max_val = float(max_val)
        q1 = float(q1)
        median = float(median)
        q3 = float(q3)
        mean = float(mean)
        std = float(std) if stats[6] is not None else 0.0

        lw = max(min_val, q1 - 1.5 * (q3 - q1))
        uw = min(max_val, q3 + 1.5 * (q3 - q1))
        lo_std = max(min_val, mean - 3 * std)
        hi_std = min(max_val, mean + 3 * std)

        iqr_count = int(
            con.sql(generate_outlier_count_sql(table, name, lower=lw, upper=uw)).fetchone()[0]
        )
        std_count = int(
            con.sql(generate_outlier_count_sql(table, name, lower=lo_std, upper=hi_std)).fetchone()[0]
        )

        def _outlier_label(count: int) -> str:
            if count == 0:
                return "0"
            return f"{count} ({round(count * 100.0 / n_rows, 1)}%)"

        property_rows["min"][name] = round(min_val, 1)
        property_rows["max"][name] = round(max_val, 1)
        property_rows["LW (1.5)"][name] = round(lw, 1)
        property_rows["Q1"][name] = round(q1, 1)
        property_rows["Median"][name] = round(median, 1)
        property_rows["Q3"][name] = round(q3, 1)
        property_rows["UW (1.5)"][name] = round(uw, 1)
        property_rows["Outlier Count (1.5*IQR)"][name] = _outlier_label(iqr_count)
        property_rows["mean-3*std"][name] = round(lo_std, 1)
        property_rows["mean"][name] = round(mean, 1)
        property_rows["std"][name] = round(std, 1)
        property_rows["mean+3*std"][name] = round(hi_std, 1)
        property_rows["Outlier Count (3*std)"][name] = _outlier_label(std_count)

    ordered_props = [
        "dtype",
        "Missing Counts",
        "nUniques",
        top_label,
        *numeric_stat_names,
    ]
    summary = pd.DataFrame(property_rows).T.reindex(ordered_props)
    col_order = summary.loc["dtype"].astype(str).sort_values(ascending=False).index
    summary = summary[col_order].astype(str)

    if properties_as_columns:
        summary = summary.T
    if print_summary:
        print(summary)

    return summary
