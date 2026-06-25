"""Project path helpers for the source → raw → staging → curated → output workflow."""

from __future__ import annotations

from pathlib import Path
from typing import TypedDict


class ProjectPaths(TypedDict):
    """Standard on-disk and database paths for a duckeb-docs project."""

    root: Path
    data_dir: Path
    source_dir: Path
    raw_dir: Path
    staging_dir: Path
    curated_dir: Path
    output_dir: Path
    db_path: Path


def find_project_root(start: Path | None = None) -> Path:
    """Walk up from *start* (or cwd) until ``pyproject.toml`` is found.

    Returns *start* unchanged when no project marker is found.
    """
    start = start or Path.cwd()
    for path in (start, *start.parents):
        if (path / "pyproject.toml").exists():
            return path
    return start


def get_default_project_paths(root: Path | None = None) -> ProjectPaths:
    """Return workflow folder paths relative to the project root.

    Parameters
    ----------
    root:
        Project root directory. When ``None``, :func:`find_project_root` is used.
    """
    project_root = root or find_project_root()
    data_dir = project_root / "data"

    return ProjectPaths(
        root=project_root,
        data_dir=data_dir,
        source_dir=data_dir / "source",
        raw_dir=data_dir / "raw",
        staging_dir=data_dir / "staging",
        curated_dir=data_dir / "curated",
        output_dir=data_dir / "output",
        db_path=project_root / "work.duckdb",
    )


def ensure_project_dirs(root: Path | None = None) -> ProjectPaths:
    """Create workflow folders when missing and return resolved paths."""
    paths = get_default_project_paths(root)
    for key in ("source_dir", "raw_dir", "staging_dir", "curated_dir", "output_dir"):
        paths[key].mkdir(parents=True, exist_ok=True)
    return paths


def sql_path(path: Path) -> str:
    """Return a forward-slash path string safe for DuckDB SQL literals."""
    return path.resolve().as_posix()
