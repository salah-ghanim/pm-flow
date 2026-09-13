"""Numbered schema steps after version 1.

`store.SCHEMA` is version 1 and is applied, idempotently, on every open.
Everything after it lives here as one DDL script per target version, and
`store._migrate` runs each script exactly once, inside the transaction that
bumps `schema_version`. That is why these statements are plain `CREATE` and
`ALTER` rather than `IF NOT EXISTS`: a step that finds its table already there
has met a store it does not understand, and failing is the honest answer.

A step only ever adds. Existing tables are never dropped or rebuilt: every
record in the store is addressed by its id, and an additive step is the only
kind that cannot change one.

Foreign keys name only tables that exist once the step has run. SQLite rejects
every insert, NULL or not, into a table whose foreign key names a missing
parent, so a column pointing at an identity a later section owns (a workflow
run, a topology node, an experiment) is added by that section's own step, not
declared early here.

CHECK constraints are reserved for the vocabularies spec 5.1 fixes: timeline
purposes, job kinds and job states. Roles, relationships, outcomes and verdicts
are data, validated by the service where they are used.
"""

STEP_2 = """
-- ---------------------------------------------------------------- principals
--
-- Who committed a transaction. A request carries an actor, and an actor that is
-- only a string cannot be joined to anything, so it is an identity from the
-- first migration. `kind` distinguishes a human, a configured agent identity and
-- the system; it is not a role.
CREATE TABLE principals (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    key           TEXT NOT NULL,
    kind          TEXT NOT NULL,
    display_name  TEXT,
    created_at    REAL NOT NULL
);
CREATE UNIQUE INDEX principals_identity ON principals(key);

-- ----------------------------------------------------------------- timelines
--
-- A history. Each project has at most one `production` timeline; experiment
-- and replay timelines fork from a position in another one. `head_seq` is the
-- last committed transaction and `version` the optimistic-concurrency counter a
-- request's `expected_version` is compared with.
CREATE TABLE timelines (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id               INTEGER NOT NULL REFERENCES projects(id),
    key                      TEXT NOT NULL,
    purpose                  TEXT NOT NULL
                             CHECK (purpose IN ('production', 'experiment', 'replay')),
    parent_timeline_id       INTEGER REFERENCES timelines(id),
    fork_seq                 INTEGER,
    fork_checkpoint_id       INTEGER REFERENCES checkpoints(id),
    experiment_arm_id        INTEGER REFERENCES experiment_arms(id),
    replicate                INTEGER,
    side_effect_policy_json  TEXT NOT NULL DEFAULT '{}',
    status                   TEXT NOT NULL,
    head_seq                 INTEGER NOT NULL DEFAULT 0,
    version                  INTEGER NOT NULL DEFAULT 0,
    created_at               REAL NOT NULL,
    updated_at               REAL NOT NULL
);
CREATE UNIQUE INDEX timelines_identity ON timelines(project_id, key);
CREATE UNIQUE INDEX timelines_one_production
    ON timelines(project_id) WHERE purpose = 'production';
CREATE UNIQUE INDEX timelines_replicate ON timelines(experiment_arm_id, replicate);

-- ------------------------------------------------------- transactions and log
--
-- Append-only and contiguous per timeline. One row per committed state-service
-- request; its changes are the typed operations the reducer applied, in order.
CREATE TABLE state_transactions (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    timeline_id      INTEGER NOT NULL REFERENCES timelines(id),
    seq              INTEGER NOT NULL,
    actor_id         INTEGER NOT NULL REFERENCES principals(id),
    job_id           INTEGER REFERENCES jobs(id),
    idempotency_key  TEXT NOT NULL,
    request_hash     TEXT NOT NULL,
    projection_hash  TEXT NOT NULL,
    committed_at     REAL NOT NULL
);
CREATE UNIQUE INDEX state_transactions_seq
    ON state_transactions(timeline_id, seq);
CREATE UNIQUE INDEX state_transactions_idempotency
    ON state_transactions(timeline_id, idempotency_key);

-- `entity_id` is polymorphic over `entity_kind` and some entities have composite
-- keys, so it is text and carries no foreign key; the reducer validates it.
CREATE TABLE state_changes (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id     INTEGER NOT NULL REFERENCES state_transactions(id),
    ordinal            INTEGER NOT NULL,
    operation          TEXT NOT NULL,
    operation_version  INTEGER NOT NULL,
    entity_kind        TEXT NOT NULL,
    entity_id          TEXT NOT NULL,
    payload_json       TEXT NOT NULL DEFAULT '{}'
);
CREATE UNIQUE INDEX state_changes_ordinal
    ON state_changes(transaction_id, ordinal);

-- ---------------------------------------------------------------------- jobs
--
-- Claimable work. `fencing_epoch` only increases: leasing increments it and a
-- completion carrying an older one is rejected. `payload_json` is the intent the
-- creating transaction recorded and `result_json` what the completing one did.
-- `subject_id` is polymorphic over `subject_kind`, like `state_changes.entity_id`.
-- Spec 5.1's `workflow_run_id` is added by the step that creates `workflow_runs`.
CREATE TABLE jobs (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    timeline_id        INTEGER NOT NULL REFERENCES timelines(id),
    kind               TEXT NOT NULL
                       CHECK (kind IN ('execute_node', 'evaluate', 'integrate_source',
                                       'dispatch_external', 'export_telemetry',
                                       'materialize_fork')),
    subject_kind       TEXT NOT NULL,
    subject_id         TEXT NOT NULL,
    state              TEXT NOT NULL DEFAULT 'queued'
                       CHECK (state IN ('queued', 'leased', 'waiting', 'succeeded',
                                        'failed', 'cancelled', 'dead')),
    priority           INTEGER NOT NULL DEFAULT 0,
    not_before         REAL,
    idempotency_key    TEXT NOT NULL,
    input_fingerprint  TEXT NOT NULL,
    payload_json       TEXT NOT NULL DEFAULT '{}',
    result_json        TEXT,
    lease_owner        TEXT,
    lease_until        REAL,
    fencing_epoch      INTEGER NOT NULL DEFAULT 0,
    attempt_count      INTEGER NOT NULL DEFAULT 0,
    max_attempts       INTEGER NOT NULL,
    reuse_of_job_id    INTEGER REFERENCES jobs(id),
    created_txn_id     INTEGER NOT NULL REFERENCES state_transactions(id),
    completed_txn_id   INTEGER REFERENCES state_transactions(id)
);
CREATE UNIQUE INDEX jobs_idempotency ON jobs(timeline_id, idempotency_key);
CREATE INDEX jobs_by_state ON jobs(timeline_id, state, priority);

-- --------------------------------------------------- positions and sources
--
-- `replayable` has no default: a checkpoint whose history holds imported work
-- with uncaptured inputs is not replayable, and only the writer knows that.
CREATE TABLE checkpoints (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    timeline_id           INTEGER NOT NULL REFERENCES timelines(id),
    seq                   INTEGER NOT NULL,
    key                   TEXT,
    reason                TEXT NOT NULL,
    projection_hash       TEXT NOT NULL,
    snapshot_artifact_id  INTEGER REFERENCES artifacts(id),
    source_heads_json     TEXT NOT NULL DEFAULT '{}',
    replayable            INTEGER NOT NULL,
    replay_limits_json    TEXT NOT NULL DEFAULT '{}',
    created_txn_id        INTEGER NOT NULL REFERENCES state_transactions(id)
);
CREATE INDEX checkpoints_by_position ON checkpoints(timeline_id, seq);

CREATE TABLE timeline_sources (
    timeline_id     INTEGER NOT NULL REFERENCES timelines(id),
    repository      TEXT NOT NULL,
    ref_name        TEXT NOT NULL,
    head_commit     TEXT NOT NULL,
    updated_txn_id  INTEGER NOT NULL REFERENCES state_transactions(id),
    PRIMARY KEY (timeline_id, repository)
);

-- --------------------------------------------------------------- experiments
--
-- Arms are grouped by `experiment_key` until the experiment section creates
-- `experiments` and adds the `experiment_id` column pointing at it.
CREATE TABLE experiment_arms (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      INTEGER NOT NULL REFERENCES projects(id),
    experiment_key  TEXT NOT NULL,
    key             TEXT NOT NULL,
    is_baseline     INTEGER NOT NULL DEFAULT 0,
    overrides_json  TEXT NOT NULL DEFAULT '[]',
    overrides_hash  TEXT NOT NULL,
    reuse_policy    TEXT NOT NULL,
    created_txn_id  INTEGER NOT NULL REFERENCES state_transactions(id)
);
CREATE UNIQUE INDEX experiment_arms_identity
    ON experiment_arms(project_id, experiment_key, key);

-- A replicate exists before its timeline is forked, so `timeline_id` is null
-- until then.
CREATE TABLE experiment_replicates (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    experiment_arm_id  INTEGER NOT NULL REFERENCES experiment_arms(id),
    replicate          INTEGER NOT NULL,
    timeline_id        INTEGER REFERENCES timelines(id),
    created_txn_id     INTEGER NOT NULL REFERENCES state_transactions(id)
);
CREATE UNIQUE INDEX experiment_replicates_identity
    ON experiment_replicates(experiment_arm_id, replicate);

-- ------------------------------------------------------ revisions and work
--
-- Immutable requirements for a task, numbered per timeline.
CREATE TABLE task_revisions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id             INTEGER NOT NULL REFERENCES tasks(id),
    timeline_id         INTEGER NOT NULL REFERENCES timelines(id),
    revision            INTEGER NOT NULL,
    parent_revision_id  INTEGER REFERENCES task_revisions(id),
    title               TEXT,
    objective           TEXT,
    contract_json       TEXT NOT NULL DEFAULT '{}',
    content_hash        TEXT NOT NULL,
    created_txn_id      INTEGER NOT NULL REFERENCES state_transactions(id)
);
CREATE UNIQUE INDEX task_revisions_identity
    ON task_revisions(task_id, timeline_id, revision);

-- Who is on a task. `seat_key` and `relationship` are free text: a seat is a
-- participant in whatever arrangement runs the task, not a built-in role.
CREATE TABLE task_assignments (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    timeline_id       INTEGER NOT NULL REFERENCES timelines(id),
    task_id           INTEGER NOT NULL REFERENCES tasks(id),
    task_revision_id  INTEGER REFERENCES task_revisions(id),
    seat_key          TEXT NOT NULL,
    relationship      TEXT NOT NULL,
    principal_id      INTEGER REFERENCES principals(id),
    persona_id        INTEGER REFERENCES personas(id),
    binding_id        INTEGER REFERENCES bindings(id),
    created_txn_id    INTEGER NOT NULL REFERENCES state_transactions(id),
    ended_txn_id      INTEGER REFERENCES state_transactions(id)
);
CREATE INDEX task_assignments_by_task ON task_assignments(timeline_id, task_id);

-- One activation of a task, including rework iterations and fan-out members.
-- The workflow-run and node columns are added by the step that creates those
-- tables.
CREATE TABLE executions (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    timeline_id          INTEGER NOT NULL REFERENCES timelines(id),
    task_id              INTEGER NOT NULL REFERENCES tasks(id),
    task_revision_id     INTEGER NOT NULL REFERENCES task_revisions(id),
    job_id               INTEGER REFERENCES jobs(id),
    parent_execution_id  INTEGER REFERENCES executions(id),
    iteration            INTEGER NOT NULL,
    member_key           TEXT,
    alignment_key        TEXT NOT NULL,
    activation_key       TEXT NOT NULL,
    status               TEXT NOT NULL,
    outcome_code         TEXT,
    version              INTEGER NOT NULL DEFAULT 0,
    created_txn_id       INTEGER NOT NULL REFERENCES state_transactions(id),
    updated_txn_id       INTEGER REFERENCES state_transactions(id)
);
CREATE INDEX executions_by_task ON executions(timeline_id, task_id);

-- The effective invocation environment, one row per distinct combination.
-- Everything but the hash is nullable because a historical invocation whose
-- CLI version or effective model was never captured stays unknown.
CREATE TABLE environment_revisions (
    id                         INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash               TEXT NOT NULL,
    cli                        TEXT,
    cli_version                TEXT,
    model_requested            TEXT,
    model_effective            TEXT,
    effort_requested           TEXT,
    effort_effective           TEXT,
    params_json                TEXT NOT NULL DEFAULT '{}',
    instruction_slots_json     TEXT NOT NULL DEFAULT '{}',
    tool_manifest_artifact_id  INTEGER REFERENCES artifacts(id),
    isolation_json             TEXT NOT NULL DEFAULT '{}',
    created_at                 REAL NOT NULL
);
CREATE UNIQUE INDEX environment_revisions_identity
    ON environment_revisions(content_hash);

-- A persisted wait for a human decision. `decision` is whatever the gate's
-- policy accepts; it is not a fixed verdict vocabulary.
CREATE TABLE human_gates (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    timeline_id      INTEGER NOT NULL REFERENCES timelines(id),
    key              TEXT NOT NULL,
    task_id          INTEGER REFERENCES tasks(id),
    execution_id     INTEGER REFERENCES executions(id),
    status           TEXT NOT NULL,
    payload_json     TEXT NOT NULL DEFAULT '{}',
    decision         TEXT,
    resolved_by_id   INTEGER REFERENCES principals(id),
    version          INTEGER NOT NULL DEFAULT 0,
    opened_txn_id    INTEGER NOT NULL REFERENCES state_transactions(id),
    resolved_txn_id  INTEGER REFERENCES state_transactions(id)
);
CREATE UNIQUE INDEX human_gates_identity ON human_gates(timeline_id, key);

-- ------------------------------------------------------ existing tables
--
-- Columns only, all nullable or defaulted, so every existing row and id stays
-- exactly as it was. A row with a NULL `timeline_id` is legacy state: it belongs
-- to no timeline and to no projection hash.
ALTER TABLE projects ADD COLUMN authority_mode TEXT NOT NULL DEFAULT 'legacy';
ALTER TABLE tasks ADD COLUMN timeline_id INTEGER REFERENCES timelines(id);
ALTER TABLE tasks ADD COLUMN version INTEGER;
ALTER TABLE tasks ADD COLUMN updated_at REAL;
ALTER TABLE tasks ADD COLUMN updated_txn_id INTEGER REFERENCES state_transactions(id);
ALTER TABLE task_dependencies ADD COLUMN timeline_id INTEGER REFERENCES timelines(id);
ALTER TABLE task_dependencies ADD COLUMN created_txn_id INTEGER REFERENCES state_transactions(id);
CREATE INDEX tasks_by_timeline ON tasks(timeline_id);
"""

# Target version -> the DDL that takes a store from the version before it.
STEPS = {
    2: STEP_2,
}
