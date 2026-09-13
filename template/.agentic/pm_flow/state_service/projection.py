"""A timeline's projection: its hash, its replay from the log, and verification.

The projection of a timeline is every row of `PROJECTION_TABLES` that belongs
to it. Its hash is sha256 over, table by table in that fixed order, the line
`<table>\\n` followed by one line per row ordered by primary key, each row the
`store.dumps` (sorted-key JSON) of its columns minus `EXCLUDED_COLUMNS`. Legacy
rows with a NULL `timeline_id` belong to no timeline and are never hashed.

`verify` does not trust the stored hash or the live tables: it replays the
recorded changes into an in-memory copy of the schema and compares all three.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3

import store
from state_service import reducer
from state_service.errors import StateError

PROJECTION_TABLES = (
    "timelines", "tasks", "task_revisions", "task_assignments", "task_dependencies",
    "jobs", "checkpoints", "timeline_sources", "executions", "human_gates",
    "experiment_arms", "experiment_replicates",
)

# Columns that change without a transaction (lease metadata, heartbeats) or
# record wall-clock time of the write rather than state.
EXCLUDED_COLUMNS = {
    "jobs": {"lease_owner", "lease_until"},
    "tasks": {"updated_at"},
    "timelines": {"updated_at"},
}

# Which rows of a table belong to a timeline. Every table not listed has a
# `timeline_id` column. A timeline is its own row, and an experiment arm is the
# one the timeline was forked for.
_MEMBERSHIP = {
    "timelines": "id = ?",
    "experiment_arms": "id = (SELECT experiment_arm_id FROM timelines WHERE id = ?)",
}


def digests(connection, timeline_id: int) -> tuple[str, dict[str, str]]:
    """The projection hash and a digest per table, over the same lines."""
    whole = hashlib.sha256()
    tables = {}
    for table in PROJECTION_TABLES:
        info = connection.execute(
            "SELECT name, pk FROM pragma_table_info(?) ORDER BY cid", (table,)).fetchall()
        excluded = EXCLUDED_COLUMNS.get(table, set())
        columns = [name for name, _ in info if name not in excluded]
        selected = ", ".join(f'"{name}"' for name in columns)
        order = ", ".join(f'"{name}"' for name, pk in sorted(info, key=lambda c: c[1]) if pk)
        part = hashlib.sha256()
        header = f"{table}\n".encode("utf-8")
        whole.update(header)
        part.update(header)
        rows = connection.execute(
            f"SELECT {selected} FROM {table}"
            f" WHERE {_MEMBERSHIP.get(table, 'timeline_id = ?')} ORDER BY {order}",
            (timeline_id,))
        for row in rows:
            line = store.dumps(dict(zip(columns, row)))
            if line == "{}":
                # A row always has its primary key, so "{}" is store.dumps
                # failing to serialise it. Hashing that would equate rows.
                raise ValueError(f"{table} row could not be serialised")
            data = (line + "\n").encode("utf-8")
            whole.update(data)
            part.update(data)
        tables[table] = part.hexdigest()
    return whole.hexdigest(), tables


def hash_projection(connection, timeline_id: int) -> str:
    return digests(connection, timeline_id)[0]


def replay(connection, timeline_id: int, upto_seq: int | None = None) -> sqlite3.Connection:
    """A scratch in-memory store holding only what the log says the timeline is.

    The schema is copied from the store, so uniqueness rules hold on replay as
    they did on apply. Foreign keys are off: the scratch holds one timeline's
    projection, not the projects, principals and transactions its rows name.
    The timeline row itself is re-created by its recorded `timeline.create`.
    """
    scratch = sqlite3.connect(":memory:")
    scratch.row_factory = sqlite3.Row
    scratch.execute("PRAGMA foreign_keys = OFF")
    for (ddl,) in connection.execute(
            "SELECT sql FROM sqlite_master WHERE type IN ('table', 'index')"
            " AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"
            " ORDER BY type = 'index', rowid"):
        scratch.execute(ddl)
    transactions = connection.execute(
        "SELECT id, seq, committed_at FROM state_transactions"
        " WHERE timeline_id = ? AND (? IS NULL OR seq <= ?) ORDER BY seq",
        (timeline_id, upto_seq, upto_seq)).fetchall()
    for transaction_id, seq, committed_at in transactions:
        context = reducer.Context(project_id=None, timeline_key=None,
                                  timeline_id=timeline_id, transaction_id=transaction_id,
                                  at=committed_at, scope=None)
        for operation, version, payload_json in connection.execute(
                "SELECT operation, operation_version, payload_json FROM state_changes"
                " WHERE transaction_id = ? ORDER BY ordinal", (transaction_id,)):
            # json.loads, not store.loads: a corrupt payload must fail replay,
            # not replay as an empty one.
            reducer.replay_change(scratch, context, operation, version,
                                  json.loads(payload_json))
        reducer.advance_timeline(scratch, timeline_id, seq, committed_at)
    return scratch


def verify(connection, timeline_id: int) -> dict:
    """Replay the whole log and compare with the stored head hash and the live rows.

    `head_seq` is the last sequence in the log, `stored` the projection hash
    recorded with it, `replayed` the hash of the replay and `current` the hash
    of the live tables. `match` holds only when all three agree.
    `mismatched_tables` lists the tables whose live rows differ from the replay.
    """
    head = connection.execute(
        "SELECT seq, projection_hash FROM state_transactions WHERE timeline_id = ?"
        " ORDER BY seq DESC LIMIT 1", (timeline_id,)).fetchone()
    head_seq, stored = (head[0], head[1]) if head else (0, None)
    current, current_tables = digests(connection, timeline_id)
    report = {"head_seq": head_seq, "stored": stored, "current": current}
    scratch = None
    try:
        scratch = replay(connection, timeline_id)
        replayed, replayed_tables = digests(scratch, timeline_id)
    except (StateError, ValueError, sqlite3.Error) as error:
        # A log that cannot be replayed reproduces nothing.
        detail = error.document() if isinstance(error, StateError) else {"detail": str(error)}
        return {**report, "replayed": None, "match": False, "mismatched_tables": [],
                "replay_error": detail}
    finally:
        if scratch is not None:
            scratch.close()
    return {
        **report,
        "replayed": replayed,
        "match": stored is not None and stored == replayed == current,
        "mismatched_tables": [table for table in PROJECTION_TABLES
                              if current_tables[table] != replayed_tables[table]],
    }
