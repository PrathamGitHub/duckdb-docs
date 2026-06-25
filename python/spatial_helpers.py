"""Spatial extension and geometry QA SQL helpers."""

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


def load_spatial_extension(con: duckdb.DuckDBPyConnection) -> None:
    """Install and load the DuckDB ``spatial`` extension."""
    con.execute("INSTALL spatial;")
    con.execute("LOAD spatial;")


def spatial_extent_sql(
    table: str,
    geom_column: str = "geom",
    *,
    include_axes: bool = True,
) -> str:
    """Build SQL to compute the bounding box for a geometry column."""
    if not _IDENT_PATTERN.match(geom_column):
        raise ValueError(f"Invalid geometry column name: {geom_column!r}")

    quoted_table = _quote_table(table)
    geom = _quote_identifier(geom_column)
    where_clause = f"WHERE {geom} IS NOT NULL AND NOT ST_IsEmpty({geom})"

    if include_axes:
        return f"""
SELECT
  ST_XMin(ST_Extent({geom})) AS xmin,
  ST_YMin(ST_Extent({geom})) AS ymin,
  ST_XMax(ST_Extent({geom})) AS xmax,
  ST_YMax(ST_Extent({geom})) AS ymax,
  ST_Extent({geom}) AS bbox
FROM {quoted_table}
{where_clause}
""".strip()

    return f"""
SELECT
  ST_Extent({geom}) AS bbox
FROM {quoted_table}
{where_clause}
""".strip()


def geometry_type_count_sql(
    table: str,
    geom_column: str = "geom",
) -> str:
    """Build SQL to count features by ``ST_GeometryType``."""
    if not _IDENT_PATTERN.match(geom_column):
        raise ValueError(f"Invalid geometry column name: {geom_column!r}")

    quoted_table = _quote_table(table)
    geom = _quote_identifier(geom_column)
    return f"""
SELECT
  ST_GeometryType({geom}) AS geom_type,
  COUNT(*) AS feature_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM {quoted_table}
WHERE {geom} IS NOT NULL
GROUP BY 1
ORDER BY feature_count DESC
""".strip()


def null_geometry_check_sql(
    table: str,
    geom_column: str = "geom",
    *,
    list_rows: bool = False,
    id_column: str | None = None,
    limit: int = 100,
) -> str:
    """Build SQL to summarize or list null and empty geometries."""
    if not _IDENT_PATTERN.match(geom_column):
        raise ValueError(f"Invalid geometry column name: {geom_column!r}")

    quoted_table = _quote_table(table)
    geom = _quote_identifier(geom_column)

    if list_rows:
        if id_column is None:
            raise ValueError("id_column is required when list_rows=True.")
        if not _IDENT_PATTERN.match(id_column):
            raise ValueError(f"Invalid id column name: {id_column!r}")
        id_col = _quote_identifier(id_column)
        return f"""
SELECT
  {id_col},
  {geom},
  CASE
    WHEN {geom} IS NULL THEN 'null'
    WHEN ST_IsEmpty({geom}) THEN 'empty'
    ELSE 'ok'
  END AS geom_status
FROM {quoted_table}
WHERE {geom} IS NULL OR ST_IsEmpty({geom})
LIMIT {int(limit)}
""".strip()

    return f"""
SELECT
  COUNT(*) AS total_rows,
  COUNT({geom}) AS non_null_geom,
  COUNT(*) - COUNT({geom}) AS null_geom,
  ROUND(100.0 * (COUNT(*) - COUNT({geom})) / COUNT(*), 2) AS null_geom_pct,
  SUM(CASE WHEN {geom} IS NOT NULL AND ST_IsEmpty({geom}) THEN 1 ELSE 0 END) AS empty_geom,
  ROUND(
    100.0 * SUM(CASE WHEN {geom} IS NOT NULL AND ST_IsEmpty({geom}) THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS empty_geom_pct
FROM {quoted_table}
""".strip()


def invalid_geometry_check_sql(
    table: str,
    geom_column: str = "geom",
    *,
    list_rows: bool = False,
    id_column: str | None = None,
    limit: int = 100,
) -> str:
    """Build SQL to summarize or list invalid geometries."""
    if not _IDENT_PATTERN.match(geom_column):
        raise ValueError(f"Invalid geometry column name: {geom_column!r}")

    quoted_table = _quote_table(table)
    geom = _quote_identifier(geom_column)

    if list_rows:
        if id_column is None:
            raise ValueError("id_column is required when list_rows=True.")
        if not _IDENT_PATTERN.match(id_column):
            raise ValueError(f"Invalid id column name: {id_column!r}")
        id_col = _quote_identifier(id_column)
        return f"""
SELECT
  {id_col},
  ST_GeometryType({geom}) AS geom_type,
  ST_IsValid({geom}) AS is_valid,
  ST_IsValidReason({geom}) AS invalid_reason
FROM {quoted_table}
WHERE {geom} IS NOT NULL
  AND NOT ST_IsValid({geom})
LIMIT {int(limit)}
""".strip()

    return f"""
SELECT
  COUNT(*) AS total_rows,
  COUNT({geom}) AS with_geom,
  SUM(CASE WHEN {geom} IS NOT NULL AND NOT ST_IsValid({geom}) THEN 1 ELSE 0 END) AS invalid_geom,
  ROUND(
    100.0 * SUM(CASE WHEN {geom} IS NOT NULL AND NOT ST_IsValid({geom}) THEN 1 ELSE 0 END)
      / NULLIF(COUNT({geom}), 0),
    2
  ) AS invalid_geom_pct
FROM {quoted_table}
""".strip()
