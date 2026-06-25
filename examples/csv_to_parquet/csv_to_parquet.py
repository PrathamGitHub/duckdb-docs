#!/usr/bin/env python3
"""CSV → raw → staging → Parquet example using DuckDB.

Run from the repository root:

    python examples/csv_to_parquet/csv_to_parquet.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb

# Repository root (parent of examples/csv_to_parquet/)
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = PROJECT_ROOT / "work.duckdb"
RAW_CSV_PATH = PROJECT_ROOT / "data" / "raw" / "orders.csv"
OUTPUT_PARQUET_PATH = PROJECT_ROOT / "data" / "output" / "orders.parquet"

RAW_TABLE = "raw.raw_orders"
STAGING_TABLE = "staging.stg_orders"

# Public TPC-H sample used to seed orders.csv when missing
LINEITEM_URL = "https://shell.duckdb.org/data/tpch/0_01/parquet/lineitem.parquet"
SEED_ROW_LIMIT = 10_000

REQUIRED_COLUMNS = ("order_id", "customer_id", "order_date", "amount")
KEY_COLUMNS = ("order_id",)


def ensure_directories() -> None:
    RAW_CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PARQUET_PATH.parent.mkdir(parents=True, exist_ok=True)


def seed_orders_csv(con: duckdb.DuckDBPyConnection) -> None:
    """Write data/raw/orders.csv from a real public dataset when absent."""
    if RAW_CSV_PATH.exists():
        print(f"Using existing source file: {RAW_CSV_PATH}")
        return

    print(f"Seeding {RAW_CSV_PATH} from {LINEITEM_URL} ...")
    con.execute("INSTALL httpfs; LOAD httpfs;")

    csv_path = RAW_CSV_PATH.as_posix()
    con.execute(
        f"""
        COPY (
          SELECT
            l_orderkey AS order_id,
            MIN(l_suppkey) AS customer_id,
            MIN(CAST(l_shipdate AS DATE)) AS order_date,
            SUM(l_extendedprice) AS amount,
            SUM(l_quantity) AS quantity,
            CASE
              WHEN BOOL_OR(l_returnflag = 'R') THEN 'returned'
              WHEN BOOL_OR(l_linestatus = 'F') THEN 'shipped'
              ELSE 'pending'
            END AS order_status
          FROM read_parquet('{LINEITEM_URL}')
          WHERE l_orderkey IS NOT NULL
          GROUP BY l_orderkey
          ORDER BY l_orderkey
          LIMIT {SEED_ROW_LIMIT}
        )
        TO '{csv_path}'
        (HEADER, DELIMITER ',');
        """
    )
    print(f"Created {RAW_CSV_PATH}")


def setup_database(con: duckdb.DuckDBPyConnection) -> None:
    for schema in ("raw", "staging", "curated"):
        con.execute(f'CREATE SCHEMA IF NOT EXISTS "{schema}";')


def ingest_raw(con: duckdb.DuckDBPyConnection) -> int:
    csv_path = RAW_CSV_PATH.as_posix()
    con.execute(
        f"""
        CREATE OR REPLACE TABLE {RAW_TABLE} AS
        SELECT *
        FROM read_csv_auto(
          '{csv_path}',
          header = true,
          sample_size = -1
        );
        """
    )
    return con.sql(f"SELECT COUNT(*) AS n FROM {RAW_TABLE}").fetchone()[0]


def _print_relation(con: duckdb.DuckDBPyConnection, sql: str) -> None:
    rel = con.sql(sql)
    print(rel)


def run_eda(con: duckdb.DuckDBPyConnection) -> None:
    print("\n--- Raw preview (10 rows) ---")
    _print_relation(con, f"SELECT * FROM {RAW_TABLE} LIMIT 10")

    print("\n--- Raw schema ---")
    _print_relation(con, f"DESCRIBE {RAW_TABLE}")

    print("\n--- Null profile ---")
    _print_relation(
        con,
        f"""
        SELECT
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
          COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
          COUNT(*) FILTER (WHERE order_date IS NULL) AS null_order_date,
          COUNT(*) FILTER (WHERE amount IS NULL) AS null_amount
        FROM {RAW_TABLE}
        """,
    )


def build_staging(con: duckdb.DuckDBPyConnection) -> int:
    con.execute(
        f"""
        CREATE OR REPLACE TABLE {STAGING_TABLE} AS
        SELECT
          TRY_CAST(order_id AS BIGINT) AS order_id,
          TRY_CAST(customer_id AS BIGINT) AS customer_id,
          TRY_CAST(order_date AS DATE) AS order_date,
          TRY_CAST(amount AS DOUBLE) AS amount,
          TRY_CAST(quantity AS INTEGER) AS quantity,
          LOWER(TRIM(COALESCE(order_status, 'unknown'))) AS order_status
        FROM {RAW_TABLE}
        WHERE order_id IS NOT NULL
          AND TRIM(CAST(order_id AS VARCHAR)) != '';
        """
    )
    return con.sql(f"SELECT COUNT(*) AS n FROM {STAGING_TABLE}").fetchone()[0]


def validate(con: duckdb.DuckDBPyConnection) -> None:
    stg_n = con.sql(f"SELECT COUNT(*) FROM {STAGING_TABLE}").fetchone()[0]
    if stg_n == 0:
        raise ValueError("Validation failed: staging table is empty")

    null_predicates = " OR ".join(f"{col} IS NULL" for col in REQUIRED_COLUMNS)
    required_nulls = con.sql(
        f"""
        SELECT COUNT(*) AS n
        FROM {STAGING_TABLE}
        WHERE {null_predicates}
        """
    ).fetchone()[0]
    if required_nulls > 0:
        raise ValueError(
            f"Validation failed: {required_nulls} rows with null required fields"
        )

    key_list = ", ".join(KEY_COLUMNS)
    dupes = con.sql(
        f"""
        SELECT {key_list}, COUNT(*) AS n
        FROM {STAGING_TABLE}
        GROUP BY {key_list}
        HAVING COUNT(*) > 1
        LIMIT 5
        """
    ).fetchall()
    if dupes:
        raise ValueError(f"Validation failed: duplicate keys: {dupes}")

    raw_n, dropped = con.sql(
        f"""
        SELECT
          (SELECT COUNT(*) FROM {RAW_TABLE}) AS raw_n,
          (SELECT COUNT(*) FROM {RAW_TABLE})
            - (SELECT COUNT(*) FROM {STAGING_TABLE}) AS dropped_rows
        """
    ).fetchone()
    if con.sql(f"SELECT COUNT(*) FROM {STAGING_TABLE}").fetchone()[0] > raw_n:
        raise ValueError("Validation failed: staging row count exceeds raw")

    bad_amounts = con.sql(
        f"""
        SELECT COUNT(*) FROM {STAGING_TABLE}
        WHERE amount IS NULL OR amount <= 0
        """
    ).fetchone()[0]
    if bad_amounts > 0:
        raise ValueError(
            f"Validation failed: {bad_amounts} rows with non-positive amount"
        )

    print("\n--- Validation summary ---")
    print(f"  staging rows:     {stg_n:,}")
    print(f"  raw rows:         {raw_n:,}")
    print(f"  dropped in stg:   {dropped:,}")
    print(f"  required nulls:   {required_nulls}")
    print(f"  duplicate keys:   0")
    print(f"  bad amounts:      {bad_amounts}")
    print("  result:           PASS")


def export_parquet(con: duckdb.DuckDBPyConnection) -> None:
    out_path = OUTPUT_PARQUET_PATH.as_posix()
    con.execute(
        f"""
        COPY {STAGING_TABLE}
        TO '{out_path}'
        (FORMAT PARQUET, COMPRESSION ZSTD);
        """
    )

    staging_n, parquet_n = con.sql(
        f"""
        SELECT
          (SELECT COUNT(*) FROM {STAGING_TABLE}) AS staging_n,
          (SELECT COUNT(*) FROM read_parquet('{out_path}')) AS parquet_n
        """
    ).fetchone()
    if staging_n != parquet_n:
        raise ValueError(
            f"Export mismatch: staging={staging_n}, parquet={parquet_n}"
        )

    print(f"\nExported {parquet_n:,} rows to {OUTPUT_PARQUET_PATH}")


def main() -> int:
    if not (PROJECT_ROOT / "README.md").exists():
        print(
            "Run this script from the repository root context "
            f"(expected project at {PROJECT_ROOT}).",
            file=sys.stderr,
        )
        return 1

    ensure_directories()

    con = duckdb.connect(str(DB_PATH))
    try:
        setup_database(con)
        seed_orders_csv(con)

        raw_n = ingest_raw(con)
        print(f"Ingested {raw_n:,} rows into {RAW_TABLE}")

        run_eda(con)

        stg_n = build_staging(con)
        print(f"\nBuilt {STAGING_TABLE} with {stg_n:,} rows")

        validate(con)
        export_parquet(con)
    finally:
        con.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
