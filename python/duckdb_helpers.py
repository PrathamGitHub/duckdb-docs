"""Core DuckDB connection and introspection helpers for notebooks and scripts."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import duckdb

from path_helpers import ensure_project_dirs

_IDENT_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
COMMON_EXTENSIONS = ("httpfs", "spatial", "json")


def _quote_identifier(name: str) -> str:
    """Quote a validated SQL identifier."""
    if not _IDENT_PATTERN.match(name):
        raise ValueError(f"Invalid SQL identifier: {name!r}")
    return f'"{name}"'


def _quote_table(table: str) -> str:
    """Quote a schema-qualified table name such as ``raw.raw_orders``."""
    parts = table.split(".")
    if not parts or len(parts) > 2:
        raise ValueError(f"Expected schema.table or table, got: {table!r}")
    return ".".join(_quote_identifier(part) for part in parts)


def connect_database(
    db_path: str | Path | None = None,
    *,
    read_only: bool = False,
    create_schemas: bool = True,
) -> duckdb.DuckDBPyConnection:
    """Open a DuckDB connection and optionally create workflow schemas.

    When *db_path* is ``None``, uses ``work.duckdb`` at the project root and
    ensures on-disk workflow folders exist.
    """
    if db_path is None:
        paths = ensure_project_dirs()
        db_path = paths["db_path"]
    else:
        db_path = Path(db_path)

    con = duckdb.connect(str(db_path), read_only=read_only)

    if create_schemas:
        for schema in ("raw", "staging", "curated"):
            con.execute(f"CREATE SCHEMA IF NOT EXISTS {_quote_identifier(schema)};")

    return con


def load_extension(con: duckdb.DuckDBPyConnection, extension: str) -> None:
    """Install and load a single DuckDB extension."""
    if not _IDENT_PATTERN.match(extension):
        raise ValueError(f"Invalid extension name: {extension!r}")
    con.execute(f"INSTALL {extension};")
    con.execute(f"LOAD {extension};")


def load_common_extensions(con: duckdb.DuckDBPyConnection) -> None:
    """Install and load extensions used across ingest, spatial, and JSON workflows."""
    for extension in COMMON_EXTENSIONS:
        load_extension(con, extension)


def run_sql_file(
    con: duckdb.DuckDBPyConnection,
    sql_file: str | Path,
    *,
    parameters: dict[str, Any] | None = None,
) -> duckdb.DuckDBPyConnection:
    """Execute SQL read from a ``.sql`` file.

    Uses DuckDB's parameter binding when *parameters* is provided.
    Returns the connection for chaining in notebooks.
    """
    sql_file = Path(sql_file)
    sql = sql_file.read_text(encoding="utf-8")
    if parameters:
        con.execute(sql, parameters)
    else:
        con.execute(sql)
    return con


def list_tables(
    con: duckdb.DuckDBPyConnection,
    schema: str | None = None,
) -> duckdb.DuckDBPyRelation:
    """List tables, optionally filtered to a single schema."""
    if schema is not None and not _IDENT_PATTERN.match(schema):
        raise ValueError(f"Invalid schema name: {schema!r}")

    if schema is None:
        query = """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
            ORDER BY table_schema, table_name
        """
        return con.sql(query)

    query = """
        SELECT table_schema, table_name, table_type
        FROM information_schema.tables
        WHERE table_schema = ?
        ORDER BY table_name
    """
    return con.execute(query, [schema])


def describe_table(con: duckdb.DuckDBPyConnection, table: str) -> duckdb.DuckDBPyRelation:
    """Return column names and types for *table* (``schema.table`` or ``table``)."""
    quoted = _quote_table(table)
    return con.sql(f"DESCRIBE {quoted}")
