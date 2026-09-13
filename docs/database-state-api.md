# Database state API

The contract of the state service in `template/.agentic/pm_flow/state_service/`.
It is pinned to `docs/database-workflows-spec.md` at `9236bde` (sections 5.1 and
6) and grows with the workplan. This revision covers schema identities and
migration. The request envelope, operations, errors, jobs, source integration and
verification are added as those land.

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
