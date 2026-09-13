"""Plan and apply schema migrations on request.

The migration itself is `store._migrate`, which every `store.connect` runs. This
module reports what that would do without writing to the store, and applies it
by opening the store the ordinary way, so exactly one code path changes a
schema.
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

import store


class MigrationError(Exception):
    """A store this command cannot plan or migrate."""


def _inspect(db_path) -> tuple[str, int | None]:
    """The store's file as SQLite names it, and its schema version.

    Read through a read-only connection. The file name comes from SQLite rather
    than from the argument so a planned backup path is the one `store._migrate`
    will write. A version of None means no version row: `store.connect` treats
    that file as a new store.
    """
    path = Path(db_path)
    if not path.is_file():
        raise MigrationError(f"no store at {path}")
    connection = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
    try:
        database = next(row[2] for row in connection.execute("PRAGMA database_list")
                        if row[1] == "main")
        has_versions = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_version'"
        ).fetchone()
        row = (connection.execute("SELECT version FROM schema_version").fetchone()
               if has_versions else None)
    finally:
        connection.close()
    return database, (None if row is None else row[0])


def tables_added(step_sql: str) -> list[str]:
    return re.findall(r"^CREATE TABLE (\w+)", step_sql, flags=re.MULTILINE)


def plan(db_path) -> dict:
    """The steps between the store's version and this engine's, without writing."""
    database, current = _inspect(db_path)
    target = store.SCHEMA_VERSION
    if current is not None and current > target:
        raise MigrationError(
            f"store schema version {current} is newer than this pm-flow "
            f"understands ({target}); upgrade pm-flow"
        )
    first = 2 if current is None else current + 1
    steps = [
        {
            "version": version,
            "adds_tables": tables_added(store.schema_steps()[version]),
            # A store with no version row is new: there is nothing to preserve.
            "backup": (None if current is None
                       else str(store.backup_path(database, version - 1))),
        }
        for version in range(first, target + 1)
    ]
    return {
        "db": database,
        "current_version": current,
        "target_version": target,
        "steps": steps,
    }


def apply(db_path) -> dict:
    """Migrate through `store.connect` and report the backups it left."""
    before = plan(db_path)
    store.connect(db_path).close()
    database, version = _inspect(db_path)
    backups = [step["backup"] for step in before["steps"] if step["backup"]]
    missing = [backup for backup in backups if not Path(backup).is_file()]
    if version != before["target_version"] or missing:
        raise MigrationError(
            f"store is at version {version} after migrating"
            + (f"; missing backups: {', '.join(missing)}" if missing else "")
        )
    return {
        "db": database,
        "previous_version": before["current_version"],
        "version": version,
        "backups": backups,
    }
