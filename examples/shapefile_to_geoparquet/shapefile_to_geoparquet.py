#!/usr/bin/env python3
"""Shapefile → raw → curated → GeoParquet example using DuckDB spatial.

Run from the repository root:

    python examples/shapefile_to_geoparquet/shapefile_to_geoparquet.py
"""

from __future__ import annotations

import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

import duckdb

# Repository root (parent of examples/shapefile_to_geoparquet/)
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = PROJECT_ROOT / "work.duckdb"
RAW_DIR = PROJECT_ROOT / "data" / "raw"
RAW_SHP_PATH = RAW_DIR / "parcels.shp"
OUTPUT_PARQUET_PATH = PROJECT_ROOT / "data" / "output" / "geo_parcels.parquet"

RAW_TABLE = "raw.raw_parcels"
CURATED_TABLE = "curated.geo_parcels"

# Natural Earth 110m admin boundaries — polygon practice data for Shapefile ingest
SHAPEFILE_SEED_URL = (
    "https://naciscdn.org/naturalearth/110m/cultural/"
    "ne_110m_admin_0_countries.zip"
)
SEED_BASENAME = "ne_110m_admin_0_countries"
TARGET_BASENAME = "parcels"
SHAPEFILE_SIDECARS = (".shp", ".shx", ".dbf", ".prj", ".cpg")


def ensure_directories() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_PARQUET_PATH.parent.mkdir(parents=True, exist_ok=True)


def _shapefile_ready() -> bool:
    return RAW_SHP_PATH.exists() and (RAW_DIR / f"{TARGET_BASENAME}.dbf").exists()


def seed_parcels_shapefile() -> None:
    """Write data/raw/parcels.* from a real public Shapefile zip when absent."""
    if _shapefile_ready():
        print(f"Using existing source Shapefile: {RAW_SHP_PATH}")
        return

    print(f"Seeding {RAW_DIR}/{TARGET_BASENAME}.* from {SHAPEFILE_SEED_URL} ...")

    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "seed.zip"
        urllib.request.urlretrieve(SHAPEFILE_SEED_URL, zip_path)

        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(tmp)

        for suffix in SHAPEFILE_SIDECARS:
            source = Path(tmp) / f"{SEED_BASENAME}{suffix}"
            if not source.exists():
                continue
            target = RAW_DIR / f"{TARGET_BASENAME}{suffix}"
            target.write_bytes(source.read_bytes())

    if not _shapefile_ready():
        raise FileNotFoundError(
            f"Seed failed: expected {RAW_SHP_PATH} and sidecars in {RAW_DIR}"
        )

    print(f"Created {RAW_SHP_PATH} (+ sidecars)")


def setup_database(con: duckdb.DuckDBPyConnection) -> None:
    for schema in ("raw", "staging", "curated"):
        con.execute(f'CREATE SCHEMA IF NOT EXISTS "{schema}";')


def load_spatial_extensions(con: duckdb.DuckDBPyConnection) -> None:
    for ext in ("spatial",):
        con.execute(f"INSTALL {ext};")
        con.execute(f"LOAD {ext};")
        print(f"Loaded extension: {ext}")


def ingest_raw(con: duckdb.DuckDBPyConnection) -> int:
    shp_path = RAW_SHP_PATH.as_posix()
    con.execute(
        f"""
        CREATE OR REPLACE TABLE {RAW_TABLE} AS
        SELECT *
        FROM ST_Read('{shp_path}');
        """
    )
    return con.sql(f"SELECT COUNT(*) AS n FROM {RAW_TABLE}").fetchone()[0]


def _print_relation(con: duckdb.DuckDBPyConnection, sql: str) -> None:
    print(con.sql(sql))


def run_spatial_eda(con: duckdb.DuckDBPyConnection) -> dict[str, int]:
    print("\n--- Raw preview (10 rows) ---")
    _print_relation(con, f"SELECT * FROM {RAW_TABLE} LIMIT 10")

    print("\n--- Raw schema ---")
    _print_relation(con, f"DESCRIBE {RAW_TABLE}")

    print("\n--- Geometry type counts ---")
    _print_relation(
        con,
        f"""
        SELECT
          ST_GeometryType(geom) AS geom_type,
          COUNT(*) AS row_count
        FROM {RAW_TABLE}
        GROUP BY 1
        ORDER BY row_count DESC
        """,
    )

    print("\n--- Null / empty geometry ---")
    null_profile = con.sql(
        f"""
        SELECT
          COUNT(*) AS total_rows,
          COUNT(geom) AS with_geom,
          COUNT(*) - COUNT(geom) AS null_geom,
          SUM(
            CASE WHEN geom IS NOT NULL AND ST_IsEmpty(geom) THEN 1 ELSE 0 END
          ) AS empty_geom
        FROM {RAW_TABLE}
        """
    ).fetchone()
    print(
        f"  total={null_profile[0]:,}  with_geom={null_profile[1]:,}  "
        f"null_geom={null_profile[2]:,}  empty_geom={null_profile[3]:,}"
    )

    print("\n--- Invalid geometry ---")
    invalid_geom, valid_geom = con.sql(
        f"""
        SELECT
          SUM(
            CASE WHEN geom IS NOT NULL AND NOT ST_IsValid(geom) THEN 1 ELSE 0 END
          ) AS invalid_geom,
          SUM(
            CASE WHEN geom IS NOT NULL AND ST_IsValid(geom) THEN 1 ELSE 0 END
          ) AS valid_geom
        FROM {RAW_TABLE}
        """
    ).fetchone()
    print(f"  invalid_geom={invalid_geom:,}  valid_geom={valid_geom:,}")

    print("\n--- Spatial extent ---")
    bbox = con.sql(
        f"""
        SELECT ST_Extent(geom) AS bbox
        FROM {RAW_TABLE}
        WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
        """
    ).fetchone()[0]
    print(f"  bbox={bbox}")

    return {
        "null_geom": int(null_profile[2]),
        "empty_geom": int(null_profile[3]),
        "invalid_geom": int(invalid_geom or 0),
    }


def build_curated(con: duckdb.DuckDBPyConnection) -> int:
    # Natural Earth seed mapping. Swap column names when using real parcel exports.
    con.execute(
        f"""
        CREATE OR REPLACE TABLE {CURATED_TABLE} AS
        SELECT
          CAST(OGC_FID AS VARCHAR) AS parcel_id,
          COALESCE(
            NULLIF(TRIM(NAME), ''),
            NULLIF(TRIM(ADMIN), ''),
            'unknown'
          ) AS owner_name,
          COALESCE(NULLIF(TRIM(ISO_A3), ''), 'UNK') AS zoning_code,
          COALESCE(
            NULLIF(TRIM(CONTINENT), ''),
            NULLIF(TRIM(REGION_UN), ''),
            'unknown'
          ) AS boundary_name,
          ST_Area(
            ST_Transform(ST_MakeValid(geom), 'EPSG:4326', 'EPSG:3857')
          ) AS area_sqm,
          ST_MakeValid(geom) AS geom
        FROM {RAW_TABLE}
        WHERE geom IS NOT NULL
          AND NOT ST_IsEmpty(geom);
        """
    )
    return con.sql(f"SELECT COUNT(*) AS n FROM {CURATED_TABLE}").fetchone()[0]


def validate(con: duckdb.DuckDBPyConnection) -> None:
    curated_n = con.sql(f"SELECT COUNT(*) FROM {CURATED_TABLE}").fetchone()[0]
    if curated_n == 0:
        raise ValueError("Validation failed: curated table is empty")

    bad_geom = con.sql(
        f"""
        SELECT COUNT(*) AS n
        FROM {CURATED_TABLE}
        WHERE geom IS NULL OR ST_IsEmpty(geom)
        """
    ).fetchone()[0]
    if bad_geom > 0:
        raise ValueError(
            f"Validation failed: {bad_geom} rows with null or empty geometry"
        )

    invalid_geom = con.sql(
        f"""
        SELECT COUNT(*) AS n
        FROM {CURATED_TABLE}
        WHERE NOT ST_IsValid(geom)
        """
    ).fetchone()[0]
    if invalid_geom > 0:
        raise ValueError(
            f"Validation failed: {invalid_geom} rows with invalid geometry"
        )

    dupes = con.sql(
        f"""
        SELECT parcel_id, COUNT(*) AS n
        FROM {CURATED_TABLE}
        GROUP BY parcel_id
        HAVING COUNT(*) > 1
        LIMIT 5
        """
    ).fetchall()
    if dupes:
        raise ValueError(f"Validation failed: duplicate parcel_id values: {dupes}")

    raw_n, dropped = con.sql(
        f"""
        SELECT
          (SELECT COUNT(*) FROM {RAW_TABLE}) AS raw_n,
          (SELECT COUNT(*) FROM {RAW_TABLE})
            - (SELECT COUNT(*) FROM {CURATED_TABLE}) AS dropped_rows
        """
    ).fetchone()
    if curated_n > raw_n:
        raise ValueError("Validation failed: curated row count exceeds raw")

    print("\n--- Validation summary ---")
    print(f"  curated rows:     {curated_n:,}")
    print(f"  raw rows:         {raw_n:,}")
    print(f"  dropped in cur:   {dropped:,}")
    print(f"  bad geometry:     {bad_geom}")
    print(f"  invalid geometry: {invalid_geom}")
    print(f"  duplicate keys:   0")
    print("  result:           PASS")


def export_geoparquet(con: duckdb.DuckDBPyConnection) -> None:
    out_path = OUTPUT_PARQUET_PATH.as_posix()
    con.execute(
        f"""
        COPY (
          SELECT
            parcel_id,
            owner_name,
            zoning_code,
            boundary_name,
            area_sqm,
            geom
          FROM {CURATED_TABLE}
          WHERE geom IS NOT NULL
            AND NOT ST_IsEmpty(geom)
            AND ST_IsValid(geom)
        )
        TO '{out_path}'
        (FORMAT PARQUET, COMPRESSION ZSTD);
        """
    )

    curated_n, parquet_n = con.sql(
        f"""
        SELECT
          (SELECT COUNT(*) FROM {CURATED_TABLE}) AS curated_n,
          (SELECT COUNT(*) FROM read_parquet('{out_path}')) AS parquet_n
        """
    ).fetchone()
    if curated_n != parquet_n:
        raise ValueError(
            f"Export mismatch: curated={curated_n}, parquet={parquet_n}"
        )

    geom_types = con.sql(
        f"""
        SELECT DISTINCT ST_GeometryType(geom) AS geom_type
        FROM read_parquet('{out_path}')
        """
    ).fetchall()
    print(f"\nExported {parquet_n:,} rows to {OUTPUT_PARQUET_PATH}")
    print(f"Round-trip geometry types: {[row[0] for row in geom_types]}")


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
        seed_parcels_shapefile()
        load_spatial_extensions(con)

        raw_n = ingest_raw(con)
        print(f"Ingested {raw_n:,} features into {RAW_TABLE}")

        run_spatial_eda(con)

        curated_n = build_curated(con)
        print(f"\nBuilt {CURATED_TABLE} with {curated_n:,} rows")

        validate(con)
        export_geoparquet(con)
    finally:
        con.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
