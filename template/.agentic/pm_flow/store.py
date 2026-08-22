"""The pm-flow store: what exists, and what happened.

Two kinds of thing live in a flow directory, and they want opposite treatment.

*Definitions* - who an agent is, what rules bind it, how a project is arranged -
change rarely, are worth diffing, and are the things a human wants to edit. They
stay markdown with YAML frontmatter and [[wikilinks]], which git handles well and
an Obsidian-style graph editor can read directly. This store *indexes* them so
they can be queried and joined; it is not where they live.

*Records* - runs, attempts, spans, outcomes - are written continuously while
agents work. As files they are unmergeable churn in somebody else's repository,
and answering any question about them means re-parsing everything from the
start. Those live here and only here.

The dividing line is mutability, not importance. `source_path` on a definition
row is what says "this row is a projection; the file is the truth".

The model is deliberately not a description of pm-flow's current five roles. A
topology is an addressable arrangement of agents and rules, and a run points at
one, so the same project can be run under several arrangements and compared.
That is the whole reason the schema is normalised rather than a wide table of
what today's driver happens to dispatch.

Standard library only. Recording must never be the reason a run fails, so the
dependency the exporter needs is imported only by the exporter.
"""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import time
from pathlib import Path

SCHEMA_VERSION = 1

# A panel seat can be mid-dispatch while another writes, so a busy database is
# the normal case rather than an error. Wait instead of failing.
BUSY_TIMEOUT_MS = 10_000

SCHEMA = """
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);

-- ---------------------------------------------------------------- vocabulary
--
-- What each backend can actually do. `difficulty` is one vocabulary in pm-flow
-- and every CLI spells it differently, so the mapping is data rather than a
-- case statement buried in the dispatcher. `capabilities` records the things
-- worth branching on - whether a CLI accepts an inbound traceparent, whether it
-- emits GenAI semantic conventions, where its token counts can be read from -
-- so the exporter can compensate for a backend instead of assuming one.
CREATE TABLE IF NOT EXISTS clis (
    key             TEXT PRIMARY KEY,
    display_name    TEXT,
    exec_name       TEXT,
    thinking_levels TEXT NOT NULL DEFAULT '{}',
    capabilities    TEXT NOT NULL DEFAULT '{}',
    default_params  TEXT NOT NULL DEFAULT '{}'
);

-- ---------------------------------------------------------------- personas
--
-- A persona is who an agent is: its expertise, its stance, the contract its
-- output must satisfy. It is deliberately model-agnostic. A persona that names
-- a CLI or a model cannot be shared with anyone who does not have that model,
-- and the whole point of a persona is that it travels.
--
-- Personas are content-versioned. Editing a prompt produces a new row rather
-- than mutating the old one, because a result is only attributable if you know
-- exactly which words produced it - and comparing two personas is meaningless
-- if one of them drifted underneath the comparison.
--
-- `extends_id` and `layer` are what make prompts composable rather than
-- monolithic: a seat can stack a base craft persona, a domain overlay and a
-- house style, and each layer stays separately shareable and separately
-- attributable.
CREATE TABLE IF NOT EXISTS personas (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    key           TEXT NOT NULL,
    title         TEXT,
    summary       TEXT,
    body          TEXT,
    layer         TEXT NOT NULL DEFAULT 'base',   -- base | domain | task | style
    extends_id    INTEGER REFERENCES personas(id),
    pack_id       INTEGER REFERENCES persona_packs(id),
    author        TEXT,
    license       TEXT,
    source_url    TEXT,
    version       TEXT,
    tags          TEXT NOT NULL DEFAULT '[]',
    metadata      TEXT NOT NULL DEFAULT '{}',
    content_hash  TEXT NOT NULL,
    source_path   TEXT,
    created_at    REAL NOT NULL,
    UNIQUE (key, content_hash)
);
CREATE INDEX IF NOT EXISTS personas_by_key   ON personas(key);
CREATE INDEX IF NOT EXISTS personas_by_layer ON personas(layer);

-- Where a set of personas came from, so a borrowed one keeps its provenance and
-- can be updated from source without losing what was measured about it.
CREATE TABLE IF NOT EXISTS persona_packs (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL UNIQUE,
    source_url   TEXT,
    ref          TEXT,
    author       TEXT,
    license      TEXT,
    description  TEXT,
    manifest     TEXT NOT NULL DEFAULT '{}',
    installed_at REAL NOT NULL
);

-- The local half a persona deliberately does not carry: which backend runs it.
-- Separating these is what lets the same persona be measured across models, and
-- what lets a shared persona install on a machine with a different model mix.
CREATE TABLE IF NOT EXISTS bindings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    key             TEXT NOT NULL,
    cli             TEXT REFERENCES clis(key),
    model           TEXT,
    thinking_level  TEXT,
    access_tier     TEXT,
    cli_params      TEXT NOT NULL DEFAULT '{}',
    content_hash    TEXT NOT NULL,
    created_at      REAL NOT NULL,
    UNIQUE (key, content_hash)
);

-- What an agent may reach for. Bound to the binding rather than the persona:
-- tool access is a property of the machine and the tier it runs at, not of the
-- expertise, and a persona that carried tool grants would be unsafe to install.
CREATE TABLE IF NOT EXISTS tool_grants (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    binding_id  INTEGER NOT NULL REFERENCES bindings(id) ON DELETE CASCADE,
    tool        TEXT NOT NULL,
    pattern     TEXT,
    mode        TEXT NOT NULL DEFAULT 'allow',
    UNIQUE (binding_id, tool, pattern, mode)
);

-- ------------------------------------------------------------------- rules
--
-- A rule is a bindable piece of policy - a contract, a guardrail, an invariant.
-- It is separate from the agent that obeys it so the same rule can bind to a
-- whole project, to one topology, or to a single agent, and so changing it once
-- changes it everywhere it applies.
CREATE TABLE IF NOT EXISTS rules (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    key           TEXT NOT NULL,
    title         TEXT,
    kind          TEXT,
    body          TEXT,
    metadata      TEXT NOT NULL DEFAULT '{}',
    content_hash  TEXT NOT NULL,
    source_path   TEXT,
    created_at    REAL NOT NULL,
    UNIQUE (key, content_hash)
);
CREATE INDEX IF NOT EXISTS rules_by_key ON rules(key);

-- Polymorphic on purpose: the same binding table answers "what rules does this
-- project have", "what does this topology add", and "what binds this one
-- agent", which is the question the future editor draws edges for.
CREATE TABLE IF NOT EXISTS rule_bindings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id     INTEGER NOT NULL REFERENCES rules(id) ON DELETE CASCADE,
    scope_type  TEXT NOT NULL,          -- project | topology | agent | template
    scope_id    INTEGER NOT NULL,
    ordering    INTEGER NOT NULL DEFAULT 0,
    UNIQUE (rule_id, scope_type, scope_id)
);
CREATE INDEX IF NOT EXISTS rule_bindings_by_scope ON rule_bindings(scope_type, scope_id);

-- -------------------------------------------------------------- topologies
--
-- The arrangement: which agents fill which roles, and how they relate. This is
-- the unit of the experiment. A run names one, so two runs of the same project
-- under different topologies are directly comparable, and `parent_id` records
-- that one arrangement was derived from another rather than invented.
--
-- A topology with no project is a design: reusable, unbound, instantiable.
CREATE TABLE IF NOT EXISTS topologies (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    key          TEXT NOT NULL,
    name         TEXT,
    description  TEXT,
    project_id   INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    parent_id    INTEGER REFERENCES topologies(id),
    is_template  INTEGER NOT NULL DEFAULT 0,
    domain       TEXT,
    metadata     TEXT NOT NULL DEFAULT '{}',
    source_path  TEXT,
    created_at   REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS topologies_by_project ON topologies(project_id);
-- A topology is identified by its key within its project, and `INSERT OR IGNORE`
-- needs something to conflict against or it quietly inserts a duplicate on every
-- re-sync. COALESCE rather than a plain UNIQUE because SQLite treats NULLs as
-- distinct, which would let unbound template topologies pile up under one key.
CREATE UNIQUE INDEX IF NOT EXISTS topologies_identity
    ON topologies(key, COALESCE(project_id, 0));

-- One row per seat, not per role, so a panel of independent seats is the plain
-- case rather than a special one.
CREATE TABLE IF NOT EXISTS topology_agents (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    topology_id  INTEGER NOT NULL REFERENCES topologies(id) ON DELETE CASCADE,
    role_key     TEXT NOT NULL,
    persona_id   INTEGER REFERENCES personas(id),
    binding_id   INTEGER REFERENCES bindings(id),
    seat         INTEGER NOT NULL DEFAULT 1,
    ordering     INTEGER NOT NULL DEFAULT 0,
    overrides    TEXT NOT NULL DEFAULT '{}',
    UNIQUE (topology_id, role_key, seat)
);

-- The stack of persona layers composed into one seat, in application order.
-- This is the drag-and-drop surface: swapping the base layer of a seat while
-- leaving its domain overlay and house style intact is a single row change, and
-- the run that follows is directly comparable to the one before it.
CREATE TABLE IF NOT EXISTS seat_personas (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    topology_agent_id  INTEGER NOT NULL REFERENCES topology_agents(id) ON DELETE CASCADE,
    persona_id         INTEGER NOT NULL REFERENCES personas(id),
    ordering           INTEGER NOT NULL DEFAULT 0,
    UNIQUE (topology_agent_id, persona_id)
);

-- How roles relate: who assigns to whom, who reviews whom, what a failure
-- escalates to. Stored as edges because that is what the visual editor edits
-- and what a graph view renders.
CREATE TABLE IF NOT EXISTS topology_edges (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    topology_id  INTEGER NOT NULL REFERENCES topologies(id) ON DELETE CASCADE,
    from_role    TEXT NOT NULL,
    to_role      TEXT NOT NULL,
    kind         TEXT NOT NULL,          -- assigns | reviews | escalates_to | adjudicates
    metadata     TEXT NOT NULL DEFAULT '{}',
    UNIQUE (topology_id, from_role, to_role, kind)
);

-- ---------------------------------------------------------------- projects
CREATE TABLE IF NOT EXISTS projects (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    key          TEXT NOT NULL UNIQUE,
    name         TEXT,
    domain       TEXT,
    description  TEXT,
    metadata     TEXT NOT NULL DEFAULT '{}',
    source_path  TEXT,
    created_at   REAL NOT NULL
);

-- The work. `parent_id` carries decomposition, so a section that was cut into
-- smaller sections keeps the shape of how it was cut.
CREATE TABLE IF NOT EXISTS tasks (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id   INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    key          TEXT NOT NULL,
    title        TEXT,
    brief        TEXT,
    priority     TEXT,
    status       TEXT,
    parent_id    INTEGER REFERENCES tasks(id),
    metadata     TEXT NOT NULL DEFAULT '{}',
    source_path  TEXT,
    created_at   REAL NOT NULL,
    UNIQUE (project_id, key)
);

CREATE TABLE IF NOT EXISTS task_dependencies (
    task_id       INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, depends_on_id)
);

-- ----------------------------------------------------------------- records
--
-- A run is one execution of one project under one topology. The run id doubles
-- as the trace id, so an unattended run is a single trace and every attempt
-- inside it is a span beneath it.
CREATE TABLE IF NOT EXISTS runs (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    run_key      TEXT NOT NULL UNIQUE,
    trace_id     TEXT NOT NULL,
    project_id   INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    topology_id  INTEGER REFERENCES topologies(id),
    command      TEXT,
    label        TEXT,
    started_at   REAL NOT NULL,
    ended_at     REAL,
    status       TEXT,
    host         TEXT,
    pid          INTEGER,
    metadata     TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS runs_by_project ON runs(project_id);
CREATE INDEX IF NOT EXISTS runs_by_topology ON runs(topology_id);

-- One row per agent invocation: the record the whole store exists to make
-- queryable. Keyed by run, task and attempt, and pointed at the exact agent
-- definition that produced it.
--
-- cli/model/thinking_level are duplicated from the definition on purpose. A
-- definition is content-versioned, but an override at dispatch time is not, and
-- a record that cannot say what was actually called is not a record.
CREATE TABLE IF NOT EXISTS attempts (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id               INTEGER REFERENCES runs(id) ON DELETE CASCADE,
    project_id           INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    task_id              INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    persona_id           INTEGER REFERENCES personas(id),
    binding_id           INTEGER REFERENCES bindings(id),
    persona_stack        TEXT NOT NULL DEFAULT '[]',
    role_key             TEXT NOT NULL,
    seat                 INTEGER NOT NULL DEFAULT 1,
    cycle                INTEGER,
    attempt_no           INTEGER NOT NULL DEFAULT 1,
    label                TEXT,
    step                 TEXT,
    trace_id             TEXT,
    span_id              TEXT,
    cli                  TEXT,
    model                TEXT,
    thinking_level       TEXT,
    access_tier          TEXT,
    started_at           REAL,
    ended_at             REAL,
    duration_s           REAL,
    status               TEXT,
    failure_reason       TEXT,
    cost_usd             REAL,
    input_tokens         INTEGER,
    output_tokens        INTEGER,
    reasoning_tokens     INTEGER,
    cache_read_tokens    INTEGER,
    cache_write_tokens   INTEGER,
    total_tokens         INTEGER,
    input_artifact_id    INTEGER REFERENCES artifacts(id),
    output_artifact_id   INTEGER REFERENCES artifacts(id),
    response_path        TEXT,
    metadata             TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS attempts_by_run  ON attempts(run_id);
CREATE INDEX IF NOT EXISTS attempts_by_task ON attempts(task_id);
CREATE INDEX IF NOT EXISTS attempts_by_role ON attempts(role_key);
CREATE INDEX IF NOT EXISTS attempts_by_span ON attempts(span_id);

-- Content-addressed, because the same system prompt is sent on nearly every
-- dispatch and storing it once per attempt would make the store mostly
-- duplicate text.
CREATE TABLE IF NOT EXISTS artifacts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    sha256      TEXT NOT NULL UNIQUE,
    media_type  TEXT,
    bytes       INTEGER,
    truncated   INTEGER NOT NULL DEFAULT 0,
    content     TEXT,
    created_at  REAL NOT NULL
);

-- How a run turned out, one measurement per row. Open-ended by design: a
-- verdict, a cost, a cycle count, a test result and a human score are all just
-- metrics, and comparing topologies means comparing these.
CREATE TABLE IF NOT EXISTS outcomes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      INTEGER REFERENCES runs(id) ON DELETE CASCADE,
    project_id  INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    task_id     INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
    attempt_id  INTEGER REFERENCES attempts(id) ON DELETE CASCADE,
    metric      TEXT NOT NULL,
    value_num   REAL,
    value_text  TEXT,
    source      TEXT,                   -- verdict | test | judge | human | derived
    recorded_at REAL NOT NULL,
    metadata    TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS outcomes_by_run    ON outcomes(run_id);
CREATE INDEX IF NOT EXISTS outcomes_by_metric ON outcomes(metric);

-- --------------------------------------------------------------- telemetry
--
-- `exported_at` is what lets a backend be started after the fact: an unshipped
-- span is one where this is NULL, so replaying a finished run into a Phoenix
-- that was launched an hour late needs no separate queue.
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
    run_id          INTEGER REFERENCES runs(id) ON DELETE CASCADE,
    attempt_id      INTEGER REFERENCES attempts(id) ON DELETE SET NULL,
    exported_at     REAL
);
CREATE INDEX IF NOT EXISTS spans_by_trace     ON spans(trace_id);
CREATE INDEX IF NOT EXISTS spans_by_parent    ON spans(parent_span_id);
CREATE INDEX IF NOT EXISTS spans_unexported   ON spans(exported_at, ended_at);

CREATE TABLE IF NOT EXISTS span_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    span_id     TEXT NOT NULL REFERENCES spans(span_id) ON DELETE CASCADE,
    at          REAL NOT NULL,
    name        TEXT NOT NULL,
    attributes  TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS span_events_by_span ON span_events(span_id);

-- ------------------------------------------------------------------- views
--
-- The comparison the topology model exists to support: same project, several
-- arrangements, what each one cost and produced.
CREATE VIEW IF NOT EXISTS topology_comparison AS
SELECT
    p.key                        AS project,
    t.key                        AS topology,
    r.run_key                    AS run,
    r.status                     AS run_status,
    COUNT(a.id)                  AS attempts,
    SUM(COALESCE(a.cost_usd, 0)) AS cost_usd,
    SUM(COALESCE(a.total_tokens, 0)) AS total_tokens,
    SUM(CASE WHEN a.status = 'error' THEN 1 ELSE 0 END) AS failed_attempts,
    r.ended_at - r.started_at    AS duration_s
FROM runs r
LEFT JOIN projects   p ON p.id = r.project_id
LEFT JOIN topologies t ON t.id = r.topology_id
LEFT JOIN attempts   a ON a.run_id = r.id
GROUP BY r.id;
"""


def default_path(project_dir: str | os.PathLike) -> Path:
    """Where a project's store lives. One file, beside the run artifacts."""
    return Path(project_dir) / "runs" / "pm_flow.db"


def connect(db_path: str | os.PathLike) -> sqlite3.Connection:
    """Open the store, creating and migrating it if needed.

    WAL is not a tuning choice. Panel seats are dispatched in parallel and each
    records its own spans, so concurrent writers are normal; the default
    rollback journal would make them queue behind a lock that can outlive a
    model call.
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
            # would quietly ignore columns that matter, so refuse instead.
            raise SystemExit(
                f"store schema version {row['version']} is newer than this "
                f"pm-flow understands ({SCHEMA_VERSION}); upgrade pm-flow"
            )


# ------------------------------------------------------------------ helpers

def now() -> float:
    return time.time()


def content_hash(*parts) -> str:
    """The identity of a definition. Two definitions with the same content are
    the same definition, however they were spelled or wherever they came from."""
    digest = hashlib.sha256()
    for part in parts:
        digest.update(b"\x00")
        if part is None:
            continue
        if not isinstance(part, str):
            part = dumps(part)
        digest.update(part.encode("utf-8", "replace"))
    return digest.hexdigest()


def dumps(value) -> str:
    """JSON that never explodes on something unserialisable."""
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
    except (TypeError, ValueError):
        return "{}"


def loads(raw: str | None):
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return {}


def put_artifact(connection, content: str, media_type: str = "text/markdown",
                 max_bytes: int = 0) -> int | None:
    """Store text once, by hash. Returns the artifact id.

    Truncation is recorded rather than hidden: a review reading back a prompt
    needs to know it is looking at part of one.
    """
    if content is None:
        return None
    raw = content.encode("utf-8", "replace")
    truncated = 0
    if max_bytes and len(raw) > max_bytes:
        raw = raw[:max_bytes]
        truncated = 1
        content = raw.decode("utf-8", "ignore")
    sha = hashlib.sha256(raw).hexdigest()
    with connection:
        row = connection.execute(
            "SELECT id FROM artifacts WHERE sha256 = ?", (sha,)
        ).fetchone()
        if row:
            return row["id"]
        cursor = connection.execute(
            "INSERT INTO artifacts (sha256, media_type, bytes, truncated, content, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (sha, media_type, len(raw), truncated, content, now()),
        )
        return cursor.lastrowid
