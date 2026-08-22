"""The pm-flow store: one SQLite file per project, holding what happened.

Why a database, in a flow whose whole architecture is files on disk.

The flow's *state* is deliberately files: every tick observes them, derives the
next action, and exits, so an interrupted run resumes by being run again. That
property is worth keeping and this module does not touch it.

What files are bad at is the *record*. pm-flow installs into someone else's
repository and then writes to it continuously while agents work, so a text
ledger is a file that changes on every dispatch, conflicts on every merge, and
has to be re-parsed from the start to answer any question about it. Telemetry
makes that worse: spans are wide, nested, and only interesting in aggregate.

So the record lives here. It is append-mostly, it is one file the installing
repository can ignore outright, and it answers questions in a query instead of
a scan. It is also the buffer that makes observability work at all: an
unattended run lasts hours and the backend that wants the traces is usually not
running when they are produced. Spans are recorded here first and exported
whenever a backend appears - see trace_export.py.

Nothing in this module imports anything that is not in the standard library.
Recording must never be the reason a run fails, so the dependency that only the
exporter needs is only imported by the exporter.
"""

from __future__ import annotations

import json
import os
import sqlite3
import time
from pathlib import Path

SCHEMA_VERSION = 1

# A writer can be waiting on a panel seat that is mid-dispatch, so a busy
# database is normal rather than exceptional. Wait rather than fail.
BUSY_TIMEOUT_MS = 10_000

SCHEMA = """
CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER NOT NULL
);

-- One row per `run` or `tick` invocation. The run id doubles as the trace id,
-- so a whole unattended run is one trace and every dispatch inside it is a
-- span under that trace.
CREATE TABLE IF NOT EXISTS runs (
    run_id      TEXT PRIMARY KEY,
    project     TEXT NOT NULL,
    domain      TEXT,
    command     TEXT,
    started_at  REAL NOT NULL,
    ended_at    REAL,
    status      TEXT,
    host        TEXT,
    pid         INTEGER
);

-- The span tree. Written by the driver as work happens, read by the exporter.
--
-- `exported_at` is what makes a backend startable after the fact: a span that
-- has never been shipped is simply one where this is NULL, so replaying into a
-- Phoenix that was started an hour late needs no separate queue.
CREATE TABLE IF NOT EXISTS spans (
    span_id         TEXT PRIMARY KEY,
    trace_id        TEXT NOT NULL,
    parent_span_id  TEXT,
    name            TEXT NOT NULL,
    kind            TEXT NOT NULL DEFAULT 'INTERNAL',
    started_at      REAL NOT NULL,
    ended_at        REAL,
    status          TEXT NOT NULL DEFAULT 'UNSET',
    status_message  TEXT,
    attributes      TEXT NOT NULL DEFAULT '{}',
    project         TEXT,
    section         TEXT,
    role            TEXT,
    exported_at     REAL
);
CREATE INDEX IF NOT EXISTS spans_by_trace   ON spans(trace_id);
CREATE INDEX IF NOT EXISTS spans_by_parent  ON spans(parent_span_id);
CREATE INDEX IF NOT EXISTS spans_unexported ON spans(exported_at, ended_at);

-- Timestamped events on a span: a retry, a usage-limit pause, a stall
-- termination. This is where the supervision layer becomes visible.
CREATE TABLE IF NOT EXISTS span_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    span_id     TEXT NOT NULL,
    at          REAL NOT NULL,
    name        TEXT NOT NULL,
    attributes  TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS span_events_by_span ON span_events(span_id);

-- One row per dispatch: the same facts the cost ledger records, plus what it
-- could never hold - tokens, wall-clock duration, how many attempts it took,
-- and which span it was.
--
-- This is a superset of runs/cost_ledger.tsv rather than a replacement for it.
-- The ledger is still the file the budget is enforced from; retiring it is a
-- separate change from introducing somewhere better to put it.
CREATE TABLE IF NOT EXISTS dispatches (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    span_id         TEXT,
    trace_id        TEXT,
    run_id          TEXT,
    project         TEXT,
    section         TEXT,
    cycle           INTEGER,
    role            TEXT NOT NULL,
    seat            INTEGER,
    label           TEXT,
    cli             TEXT,
    model           TEXT,
    difficulty      TEXT,
    access          TEXT,
    started_at      REAL,
    ended_at        REAL,
    duration_s      REAL,
    attempts        INTEGER,
    status          TEXT,
    failure_reason  TEXT,
    cost_usd        REAL,
    input_tokens    INTEGER,
    output_tokens   INTEGER,
    cache_read_tokens    INTEGER,
    cache_write_tokens   INTEGER,
    total_tokens    INTEGER,
    response_path   TEXT
);
CREATE INDEX IF NOT EXISTS dispatches_by_section ON dispatches(section);
CREATE INDEX IF NOT EXISTS dispatches_by_run     ON dispatches(run_id);
"""


def default_path(project_dir: str | os.PathLike) -> Path:
    """Where a project's store lives. One file, beside the run artifacts."""
    return Path(project_dir) / "runs" / "pm_flow.db"


def connect(db_path: str | os.PathLike) -> sqlite3.Connection:
    """Open the store, creating and migrating it if needed.

    WAL is not an optimisation here. Panel seats are dispatched in parallel and
    each one records its own spans, so concurrent writers are the normal case;
    the default rollback journal would make them serialise behind a lock that
    can outlive a model call.
    """
    path = Path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(str(path), timeout=BUSY_TIMEOUT_MS / 1000)
    connection.row_factory = sqlite3.Row
    connection.execute(f"PRAGMA busy_timeout = {BUSY_TIMEOUT_MS}")
    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA synchronous = NORMAL")
    connection.execute("PRAGMA foreign_keys = ON")
    _migrate(connection)
    return connection


def _migrate(connection: sqlite3.Connection) -> None:
    with connection:
        connection.executescript(SCHEMA)
        row = connection.execute("SELECT version FROM schema_version").fetchone()
        if row is None:
            connection.execute(
                "INSERT INTO schema_version (version) VALUES (?)", (SCHEMA_VERSION,)
            )
        elif row["version"] > SCHEMA_VERSION:
            # A newer pm-flow wrote this store. Reading it with older accessors
            # would silently ignore columns that matter, so say so instead.
            raise SystemExit(
                f"store schema version {row['version']} is newer than this "
                f"pm-flow understands ({SCHEMA_VERSION}); upgrade pm-flow"
            )


def now() -> float:
    return time.time()


def dumps(value) -> str:
    """JSON that never explodes on something unserialisable."""
    try:
        return json.dumps(value, ensure_ascii=False, default=str)
    except (TypeError, ValueError):
        return "{}"


def loads(raw: str | None):
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return {}
