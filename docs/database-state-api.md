# Database state API

The contract of the state service in `template/.agentic/pm_flow/state_service/`.
It is pinned to `docs/database-workflows-spec.md` at `9236bde` (sections 5.1 and
6) and grows with the workplan. This revision covers schema identities,
migration, the request envelope, operations version 1 for timelines, tasks and
dependencies, errors, the projection hash and `verify`. Jobs, source integration
and checkpoints are added as those land.

## Schema version 2

A project's store is one SQLite file, `runs/pm_flow.db` (`store.default_path`).
Schema version 2 is version 1 (`store.SCHEMA`) plus step 2
(`state_service/schema.py`, `STEPS[2]`). There is no second database.

### Identities

| Table | Identity and uniqueness | Holds |
|---|---|---|
| `principals` | `key` | The attributable actor of a transaction: a human, a configured agent identity or the system. Not a role. |
| `timelines` | `(project_id, key)`; one `production` timeline per project (partial unique index on `project_id WHERE purpose = 'production'`); `(experiment_arm_id, replicate)` | A history. `purpose` is `production`, `experiment` or `replay`. `head_seq` is the last committed sequence number and `version` the optimistic-concurrency counter. |
| `state_transactions` | `(timeline_id, seq)`; `(timeline_id, idempotency_key)` | One committed state-service request: actor, optional job, request hash and resulting projection hash. |
| `state_changes` | `(transaction_id, ordinal)` | The typed operations one transaction applied, in order, with operation version and payload. |
| `jobs` | `(timeline_id, idempotency_key)` | Claimable work. `kind` is `execute_node`, `evaluate`, `integrate_source`, `dispatch_external`, `export_telemetry` or `materialize_fork`. `state` is `queued`, `leased`, `waiting`, `succeeded`, `failed`, `cancelled` or `dead`. `fencing_epoch` only increases. `payload_json` is the recorded intent, `result_json` the recorded result. |
| `checkpoints` | `id` | An addressable position: sequence number, projection hash, source heads, and whether it is replayable and why not. |
| `timeline_sources` | primary key `(timeline_id, repository)` | The source head per repository per timeline. |
| `experiment_arms` | `(project_id, experiment_key, key)` | One arm of an experiment: baseline flag, overrides and reuse policy. |
| `experiment_replicates` | `(experiment_arm_id, replicate)` | One replicate of an arm and, once forked, its timeline. |
| `task_revisions` | `(task_id, timeline_id, revision)` | Immutable task requirements, numbered per timeline. |
| `task_assignments` | `id` | A seat on a task in a timeline, with relationship, optional principal, persona and binding. |
| `executions` | `id` | One activation of a task revision: iteration, member, alignment and activation keys, status and outcome code. |
| `environment_revisions` | `content_hash` | One distinct effective invocation environment. |
| `human_gates` | `(timeline_id, key)` | A persisted wait for a human decision. |

Existing tables gain columns only:

| Table | Added columns |
|---|---|
| `projects` | `authority_mode TEXT NOT NULL DEFAULT 'legacy'` |
| `tasks` | `timeline_id`, `version`, `updated_at`, `updated_txn_id`, all nullable |
| `task_dependencies` | `timeline_id`, `created_txn_id`, both nullable |

### Rules the schema enforces and the ones it leaves to the service

- Every `*_id` column declares a foreign key, with two exceptions:
  `jobs.subject_id` and `state_changes.entity_id` are polymorphic over
  `subject_kind` and `entity_kind`, are text because some entities have composite
  keys, and are validated by the service.
- CHECK constraints cover only the vocabularies spec 5.1 fixes: timeline
  `purpose`, job `kind` and job `state`. Timeline, execution and gate status,
  assignment relationship, gate decision and outcome code are free text, and the
  service validates their transitions. No role, outcome or verdict is an enum.
- Existing rows keep their ids and get NULL timeline columns. A row with a NULL
  `timeline_id` is legacy state and belongs to no projection hash. Every existing
  project has `authority_mode = 'legacy'`, and the state service does not change
  it.
- Some columns are not in version 2 because the table they would reference does
  not exist yet: spec 5.1's `jobs.workflow_run_id`, the workflow-run and node
  columns of `executions`, and `experiment_arms.experiment_id` (arms are grouped
  by `experiment_key` until then). SQLite rejects every insert into a table whose
  foreign key names a missing table, NULL values included, so declaring them
  early would make those tables unwritable. The step that creates each parent
  table adds its column with `ALTER TABLE ... ADD COLUMN ... REFERENCES`.
- Any schema change after version 2 is a new step 3. A store already at
  version 2 never runs step 2 again, so editing step 2 changes new stores only.

## Migration

### When it runs

`store.connect(path)` migrates on every open. It is the only code path that
changes a schema. `cli.py migrate --apply` opens the store through it.

### Procedure

1. Apply `store.SCHEMA` (version 1, `IF NOT EXISTS`). This does nothing to an
   existing store.
2. Read `schema_version`. At the target version, return: no lock is taken and
   nothing is written. Above it, refuse with `store schema version N is newer
   than this pm-flow understands`.
3. Otherwise take the write lock (`BEGIN IMMEDIATE`) and read the version again,
   because another process may have migrated in the meantime.
4. No version row means a new store. Run every step, insert
   `schema_version = SCHEMA_VERSION` and commit. There is nothing to back up.
5. At version `n`, back up to `<db>.v<n>.bak`. Then, in the same transaction,
   run step `n+1` and set `schema_version = n+1`. Commit and repeat until the
   store reaches the target.

A failure at any point rolls back the step's transaction and raises
`SystemExit` with the reason. The store stays at version `n`, with no object from
step `n+1`.

### Backup

- Path: `<db>.v<n>.bak`, beside the store. `<db>` is the file name SQLite
  reports for the store. For a project store at version 1 that is
  `runs/pm_flow.db.v1.bak`.
- The copy is taken with `sqlite3.Connection.backup` through a second
  connection while the migrating connection holds the write lock. No write can
  land between the copy and the step.
- The copy is written to `<db>.v<n>.bak.partial` and switched to
  `journal_mode = DELETE`, so it is one self-contained file. It is renamed into
  place only after its `schema_version` reads `n` and `PRAGMA quick_check`
  returns `ok`. A `.bak` that exists is complete.
- If the backup cannot be written or does not verify, the partial copy is
  removed and the open fails with
  `could not back up store to <path> (<reason>); not migrating from version <n>`.
  No DDL has run at that point.
- An existing `<db>.v<n>.bak` is replaced only when the store is at version `n`
  again: after a failed step, or after a restore. The replacement is a copy of
  the state about to be migrated.
- pm-flow never deletes backups. A backup holds everything the store holds,
  including captured prompts and artifacts, and needs the same handling.

### Command line

```
python3 <flow>/state_service/cli.py migrate --db <store> --dry-run
python3 <flow>/state_service/cli.py migrate --db <store> --apply
```

`--db` may also come before `migrate`. Each command prints one JSON document
on stdout.

`--dry-run` opens the store read-only and writes nothing to it. SQLite may create
`-wal` and `-shm` files beside a WAL store, as it does for any reader. A missing
file is an error, not a new store.

```json
{"current_version": 1, "db": "/…/runs/pm_flow.db", "steps": [{"adds_tables": ["principals", "timelines", "…"], "backup": "/…/runs/pm_flow.db.v1.bak", "version": 2}], "target_version": 2}
```

`current_version` is `null` for a file with no version row. Its steps have no
backup.

`--apply` migrates through `store.connect`, checks that the store reached the
target and that every reported backup exists, and prints:

```json
{"backups": ["/…/runs/pm_flow.db.v1.bak"], "db": "/…/runs/pm_flow.db", "previous_version": 1, "version": 2}
```

On a store already at the target, `backups` is empty.

Any failure prints `{"error": "migration_failed", "detail": "<reason>"}` and
exits 1. Failures include a missing store, a newer schema, a failed backup and
an SQLite error.

## Rollback boundary

`<db>.v1.bak` is a complete version-1 store as it was at the moment step 2
began.

- Restoring it loses nothing only if nothing has been written to the store since
  the migration committed.
- Any later write is missing from the backup, and restoring the backup discards
  it. That covers state-service transactions and equally the attempts, spans and
  outcomes the engine records on every dispatch. Rollback after such writes is
  lossy by construction.
- The only restore today is manual:
  1. Stop every process using the store.
  2. Move `pm_flow.db`, `pm_flow.db-wal` and `pm_flow.db-shm` aside. A WAL file
     beside the restored file belongs to the other database and must not be
     replayed into it.
  3. Copy `pm_flow.db.v1.bak` to `pm_flow.db`.
  4. Run the previous pm-flow version against it.

  A version-2 engine opening the restored store migrates it again.
- A restore command must detect writes made after the migration. It must refuse
  to restore over them unless given `--discard-new-state`. That command will be
  built once the state service has a write path. Until then no CLI command
  restores a backup.

## Requests

Every authoritative change is a request to `state_service.service.apply(db,
request)`, or `cli.py apply`. A request commits exactly one transaction on one
timeline, or nothing.

### Envelope, version 1

```json
{
  "request_version": 1,
  "project": "ledger",
  "actor": {"key": "salah", "kind": "human"},
  "timeline": "main",
  "scope": "*",
  "idempotency_key": "create-alpha",
  "expected_version": 1,
  "operations": [
    {"op": "task.create", "op_version": 1, "key": "alpha", "title": "Alpha"}
  ]
}
```

| Field | Required | Shape and meaning |
|---|---|---|
| `request_version` | yes | The integer `1`. |
| `project` | yes | Project key. The project must already exist in `projects`; the state service does not create projects. |
| `actor` | yes | `{"key", "kind"}`, both non-empty strings. The principal is recorded on first use. A key already recorded with a different `kind` is `conflict`. `kind` is free text. |
| `timeline` | yes | Timeline key within the project. It must exist, unless the first operation is `timeline.create`. |
| `scope` | yes | `"*"` for every task, or `{"tasks": [task keys]}`. |
| `idempotency_key` | yes | Non-empty string, unique per timeline. |
| `expected_version` | no | Non-negative integer. When present it must equal the timeline's `version` (0 for a timeline the request creates), else `conflict`. |
| `operations` | yes | Non-empty list of `{"op", "op_version", ...arguments}`. `op` is a non-empty string and `op_version` an integer. |

Any other field, or a wrong shape, is `invalid_contract`. So is a request file
that cannot be read or is not JSON.

### Processing order

1. Validate the envelope (`invalid_contract`). Nothing is opened before this.
2. `BEGIN IMMEDIATE`. Everything below runs under this one write lock.
3. Resolve the project (`invalid_reference`).
4. If the timeline exists and already has a transaction with this
   `idempotency_key`: return that transaction's result if the request is
   identical (same `request_hash`), otherwise `conflict`. Nothing is written.
5. Compare `expected_version` (`conflict`).
6. A missing timeline is `invalid_reference` unless the first operation is
   `timeline.create`.
7. Record the actor principal.
8. Read `head_seq` and insert the `state_transactions` row at `seq = head_seq + 1`,
   with `request_hash = store.content_hash(request)`. A request that creates its
   timeline inserts this row right after the creating operation, because the row
   names the timeline.
9. Apply each operation through the reducer, in order.
10. Write one `state_changes` row per operation, `ordinal` 0..n-1.
11. Set `timelines.head_seq = seq` and `version = version + 1`.
12. Compute the projection hash, store it on the transaction row, commit.

A `StateError` at any step rolls back every write of the request. Its
principal, log row, change rows and projection rows are all discarded.

### Result

```json
{"changes": 1, "projection_hash": "…", "seq": 2, "timeline_version": 2, "transaction_id": 2}
```

An identical request with an idempotency key that already committed returns
that commit's result with `"idempotent_replay": true` added, and exits 0. No row
is written.

There is no stored result column. A replayed result is recomputed from the log
row: `transaction_id`, `seq` and `projection_hash` are columns, `changes` counts
the transaction's `state_changes` rows, and `timeline_version` is
`timelines.version - (timelines.head_seq - seq)`. That formula holds because
every committed transaction advances `head_seq` and `version` together by one,
and nothing else advances either. Both columns are in the projection hash, so a
change to either outside the service shows up in `verify`.

## Operations, version 1

Task references are task keys. A key must be in the request's `scope`, else
`denied_scope`. Scope is checked before the key is looked up. The key must then
name a task on the request's timeline, which belongs to the request's project,
else `invalid_reference`. A key that exists only in another project, or only as a
legacy task, is `invalid_reference`. Unknown or missing arguments are
`invalid_contract`. Status, seat and relationship values are free text and are
never checked against a list.

| Operation | Arguments | Effect |
|---|---|---|
| `timeline.create` | `purpose` (must be `production`), `status` (optional, default `active`) | Creates the request's `timeline` for the project with `head_seq` 0 and `version` 0. Other purposes are `invalid_contract` in version 1. A second production timeline for the project, or an existing key, is `conflict`. |
| `task.create` | `key`, optional `title`, `objective`, `status`, `contract` (object, default `{}`) | Inserts a `tasks` row on the timeline with `version` 1 and `updated_txn_id`, plus `task_revisions` revision 1 with `content_hash = store.content_hash(title, objective, contract)`. A key already used in the project, on any timeline or as a legacy task, is `conflict`, because `tasks` is unique on `(project_id, key)`. |
| `task.revise` | `task`, at least one of `title`, `objective`, `contract` | Inserts the next revision, with `parent_revision_id` pointing at the latest. Omitted fields carry over from the latest revision. Sets `tasks.title`, `version + 1` and `updated_txn_id`. |
| `task.set_status` | `task`, `status` | Sets `tasks.status`, `version + 1` and `updated_txn_id`. |
| `task.assign` | `task`, `seat_key`, `relationship` | Inserts a `task_assignments` row against the task's latest revision. |
| `dependency.add` | `task`, `depends_on` | `task` depends on `depends_on`. It is `cyclic_dependency` if `depends_on` already reaches `task` through the timeline's `task_dependencies`, including when it is `task` itself. An existing identical dependency is `conflict`. |
| `dependency.remove` | `task`, `depends_on` | Deletes that dependency. If it does not exist, `invalid_reference`. |

Every operation writes one `state_changes` row:

- `operation` and `operation_version`.
- `entity_kind` (`timeline`, `task`, `task_assignment` or `task_dependency`).
- `entity_id`: the row id, or `<task_id>:<depends_on_id>` for a dependency.
- `payload_json`: `{"args": {...}, "bound": {...}}`.

`args` holds the operation's arguments as sent. `bound` holds what the operation
fixed when it first ran:

- the row ids it allocated (`timeline_id`, `task_id`, `revision_id`,
  `assignment_id`);
- for `timeline.create`, also the envelope's `project_id` and `key`.

Replay feeds `bound` back so the replayed rows get the same ids. Reducers read
no clock. Every timestamp they write is the transaction's `committed_at`.

An unknown `(op, op_version)` pair is `unknown_operation_version`. It is never
skipped, and no version is assumed.

## Errors

A refused request prints `{"error": "<code>", "detail": "<text>"}` on stdout and
exits 1. `code` is the contract. `detail` is for people and may change.

| Code | Meaning |
|---|---|
| `conflict` | Stale `expected_version`. Uniqueness violated: second production timeline, existing timeline or task key, duplicate dependency. Idempotency key reused for a different request. Principal key reused with another kind. |
| `invalid_reference` | Unknown store, project or timeline. Task key not on the request's timeline. Missing dependency on remove. |
| `invalid_contract` | Malformed envelope, operation arguments or request file. A registration that would override the built-in vocabulary. A recorded change payload that is not `{args, bound}`. |
| `unmet_dependency` | Reserved for dependency-gated operations (later tasks). |
| `lost_lease` | Reserved for job completion with a stale fencing epoch (T3). |
| `denied_scope` | A task key outside the request's `scope`. |
| `denied_side_effect` | Reserved for side effects a timeline may not perform (T4). |
| `non_replayable_checkpoint` | Reserved for checkpoints (T5). |
| `confounded_comparison` | Reserved for experiment comparison. |
| `unknown_operation_version` | No reducer for `(op, op_version)`. |
| `cyclic_dependency` | A dependency that would close a cycle, including self-dependency. |
| `idempotent_replay` | Not an error. It marks a replayed result (`"idempotent_replay": true`, exit 0). |

The command line adds two codes of its own, outside the service vocabulary:

- `migration_failed`: the store could not be opened at this engine's schema
  version.
- `store_error`: an SQLite or file error the service did not anticipate.

## Projection hash

A timeline's projection is every row of these tables that belongs to it, in
this fixed order:

`timelines`, `tasks`, `task_revisions`, `task_assignments`, `task_dependencies`,
`jobs`, `checkpoints`, `timeline_sources`, `executions`, `human_gates`,
`experiment_arms`, `experiment_replicates`.

- **Membership.** For `timelines`, the row whose `id` is the timeline. For
  `experiment_arms`, the arm named by the timeline's `experiment_arm_id`. For
  every other table, rows whose `timeline_id` is the timeline. Legacy rows with
  a NULL `timeline_id` belong to no timeline.
- **Excluded columns.** `jobs.lease_owner`, `jobs.lease_until`,
  `tasks.updated_at` and `timelines.updated_at`. Every other column is included,
  among them `timelines.head_seq` and `version`, row ids, and `created_at`
  values.
- **Canonical row.** `store.dumps` (JSON with sorted keys) of a dict of the
  row's remaining columns. A row that serialises to `{}` is an error, not a
  hash input.
- **Hash.** sha256 over, for each table in order, the bytes `<table>\n`, then
  `<canonical row>\n` for each row ordered by the table's primary key. A table's
  digest is sha256 over the same bytes for that table alone.

`state_transactions.projection_hash` is the hash after the transaction's
changes, including its `head_seq` and `version` advance.

## Verify

`projection.verify(connection, timeline_id)` replays the log and does not trust
the stored hash or the live rows:

1. Copy the store's table and index DDL into `sqlite3.connect(":memory:")`, with
   foreign keys off. The scratch holds only this timeline's projection.
2. For each transaction of the timeline in `seq` order, re-apply its
   `state_changes` in `ordinal` order through the same reducer functions, with
   the recorded `bound` values and `committed_at`. Then advance `head_seq` and
   `version` as apply does. The timeline row itself is re-created by its
   recorded `timeline.create`.
3. Hash the scratch projection, then hash the live projection.

```json
{"current": "…", "head_seq": 5, "match": false, "mismatched_tables": ["tasks"], "replayed": "…", "stored": "…"}
```

| Field | Meaning |
|---|---|
| `head_seq` | The last `seq` in the log. |
| `stored` | `projection_hash` recorded on that transaction. |
| `replayed` | Hash of the scratch projection. |
| `current` | Hash of the live projection. |
| `match` | True only when `stored`, `replayed` and `current` are equal. |
| `mismatched_tables` | Tables whose live digest differs from the replayed digest, in table order. |

If the log cannot be replayed, for example a corrupt payload or a reducer
refusing a recorded change, the report has `"replayed": null`, `"match": false`
and a `replay_error` holding the error document.

## Extensions

`state_service.extensions` holds process-local registries:

- `register_operation(name, version, fn)` adds a reducer with the built-in
  signature `fn(connection, context, args) -> (entity_kind, entity_id, payload)`.
  The payload must be `{"args", "bound"}`. A `name` already in the built-in
  vocabulary, at any version, is refused with `invalid_contract`, as is a second
  registration of the same pair. Every process that applies or verifies a
  timeline containing the operation must register it first, or lookup raises
  `unknown_operation_version`.
- `register_job_handler(kind, fn)` and `register_decision(kind, fn)` store into
  `JOB_HANDLERS` and `DECISIONS`. Their contracts arrive with jobs (T3).

## Command line for requests and timelines

```
python3 <flow>/state_service/cli.py apply --db <store> --request <json-file>
python3 <flow>/state_service/cli.py timeline log --db <store> --project <key> --timeline <key>
python3 <flow>/state_service/cli.py timeline projection --db <store> --project <key> --timeline <key>
python3 <flow>/state_service/cli.py timeline verify --db <store> --project <key> --timeline <key>
```

Each prints one JSON document. None of them creates a store: a missing `--db`
file is `invalid_reference`. The `timeline` commands read inside one snapshot.

- `apply` prints the result, or an error with exit 1.
- `timeline log` prints `project`, `timeline`, `head_seq`, `version` and
  `transactions`: `[{seq, transaction_id, idempotency_key, projection_hash,
  actor, committed_at, changes}]` in `seq` order.
- `timeline projection` prints `project`, `timeline`, `head_seq`,
  `projection_hash` and `tables` (table → digest) for the live rows.
- `timeline verify` prints `project`, `timeline` and the verify report. It exits
  0 when `match` is true, 1 otherwise.
