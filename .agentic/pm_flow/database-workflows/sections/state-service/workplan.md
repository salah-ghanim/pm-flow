# state-service workplan

Contract: `brief.md`, pinned to `docs/database-workflows-spec.md` at `9236bde`
(sections 3, 4, 5.1, 6, 8, 9 and acceptance A3/A15).

## Design summary

- Extend the existing per-project SQLite store in
  `template/.agentic/pm_flow/store.py` (schema version 1, `connect()` and
  `_migrate()`) with a versioned migration to schema version 2. Existing tables
  and AUTOINCREMENT ids are kept; new tables are added and existing
  current-state tables gain nullable timeline/version columns. `_migrate()`
  becomes a per-version ladder that takes an SQLite backup-API copy before the
  first schema change and refuses to run when the backup fails.
- All authoritative mutation goes through one package,
  `template/.agentic/pm_flow/state_service/`, whose public entry point is a
  versioned request: `{"request_version": 1, "project", "actor", "timeline",
  "scope", "idempotency_key", "expected_version"?, "operations": [...]}`. The
  service validates, opens one `BEGIN IMMEDIATE` transaction, appends a
  `state_transactions` row with contiguous `seq`, applies every operation through
  the versioned reducer to the projection tables, computes and stores the
  `projection_hash`, and commits. Nothing else in the engine writes to projection
  tables.
- The reducer is a table of `(operation, operation_version) -> function`. An
  unknown pair raises `unknown_operation_version`; it never skips. Projection
  hash is the sha256 of canonical JSON (`store.dumps`, sort_keys) of every
  projection row belonging to the timeline, table by table in a fixed order,
  rows by primary key, with lease metadata columns (`lease_owner`,
  `lease_until`) excluded. `verify` re-applies the log into a scratch in-memory
  copy of the projection and compares hashes at every checkpoint and the head.
- Jobs live in the same log. `job.create`, `job.lease`, `job.complete`,
  `job.fail` and `job.cancel` are operations; leasing increments
  `fencing_epoch` and every completion carries the epoch it leased with.
  Heartbeat extends `lease_until` only, through the service, without a logged
  transaction. Workers never hold a database transaction across a Git operation
  or a provider call: lease commits, work happens, completion is a new request.
- `template/.agentic/pm_flow/source_integration.py` is the `integrate_source`
  job handler. The creating transaction records intent (repository, base
  branch, section branch, base head, branch head). The worker performs the Git
  merge outside any database transaction using the same
  `merge-tree --write-tree` precheck the driver uses in
  `merge_section_worktree`. Recovery reads the repository before merging: if a
  commit on the base already has the recorded base head and branch head as its
  parents, or the branch head is already an ancestor of the base, the job
  completes with that commit and performs no second merge.
- Tests are zsh scripts in the repository's existing style
  (`tests/store_ledger_test.sh`: `#!/bin/zsh -f`, `set -euo pipefail`, PM_FLOW_*
  scrub, mktemp root with guarded cleanup, `fail`/`assert_eq`). The two brief
  entry points discover scenario directories: `tests/knowledge_state_test.sh`
  runs every `tests/database_state/state/*/scenario.zsh` and
  `tests/timeline_replay_test.sh` runs every
  `tests/database_state/replay/*/scenario.zsh`, each in its own temp root with
  `REPO_ROOT`, `FLOW` (a copy of the template engine) and `TEST_ROOT` exported.
  Other sections add scenario directories; they do not edit the entry points.
- Contracts are published in `docs/database-state-api.md` and grow with each
  task: identities and schema (T1), request envelope, operations and errors
  (T2), jobs and extension registration (T3), source integration (T4),
  checkpoints and verify (T5).

## Interfaces and data changes

- Schema version 2, tables per spec 5.1 with concrete constraints: `timelines`
  (partial unique index on one `production` per project; unique
  `(project_id, key)`; unique `(experiment_arm_id, replicate)`),
  `state_transactions` (unique `(timeline_id, seq)` and
  `(timeline_id, idempotency_key)`), `state_changes` (unique
  `(transaction_id, ordinal)`), `checkpoints`, `timeline_sources`, `jobs`
  (unique `(timeline_id, idempotency_key)`), plus identity tables
  `task_revisions`, `task_assignments`, `environment_revisions`,
  `experiment_arms`, `experiment_replicates`, `human_gates` and `executions`
  so cutover-era rows can reference them. `tasks` gains nullable `timeline_id`,
  `version`, `updated_at`, `updated_txn_id`; `task_dependencies` gains
  `timeline_id` and `created_txn_id`; `projects` gains `authority_mode`
  defaulting to `legacy`. Legacy rows keep NULL timeline columns and are not
  part of any projection hash.
- Request envelope version 1 and operation vocabulary version 1:
  `timeline.create`, `task.create`, `task.revise`, `task.set_status`,
  `task.assign`, `dependency.add`, `dependency.remove`, `job.create`,
  `job.lease`, `job.complete`, `job.fail`, `job.cancel`,
  `execution.create`, `execution.complete`, `output.publish`,
  `panel.expect`, `panel.join`, `decomposition.apply`, `gate.open`,
  `gate.resolve`, `checkpoint.create`, `source.integrated`.
- Structured errors, each a JSON object `{"error": code, "detail": ...}`
  with a non-zero exit from the CLI: `conflict`, `invalid_reference`,
  `invalid_contract`, `unmet_dependency`, `lost_lease`, `denied_scope`,
  `denied_side_effect`, `non_replayable_checkpoint`, `confounded_comparison`,
  `unknown_operation_version`, `cyclic_dependency`, `idempotent_replay`
  (returns the original result, exit 0).
- Extension contracts: `state_service.extensions.register_operation(name,
  version, reducer_fn)`, `register_job_handler(kind, handler_fn)` and
  `register_decision(kind, fn)`; registrations are process-local and the built-in
  vocabulary cannot be overridden.
- CLI: `python3 <flow>/state_service/cli.py --db <path> <command>` with
  commands `migrate --dry-run|--apply`, `apply --request <json-file>`,
  `job lease|heartbeat|complete|fail`, `job run --kind integrate_source`,
  `timeline log|projection|verify`, `checkpoint create|list`, `query
  eligible|context`. Output is one JSON document on stdout.

## Task T1 — Versioned migration to schema 2 with backup, identities and the test entry points

- Status: done (cycle 001, accepted 2026-09-13)
- Outcome: opening a version-1 store through `store.connect()` writes a
  backup, applies migration 2, records `schema_version = 2`, keeps every
  existing row id, and a version-2 store opens without change. Every identity
  the brief names (timelines, transactions, changes, jobs, checkpoints,
  environment revisions, experiment arms and replicates) exists as a table
  with the uniqueness rules above. `tests/knowledge_state_test.sh` exists,
  discovers scenario directories, and its first scenario proves the migration.
- Paths: `template/.agentic/pm_flow/store.py`,
  `template/.agentic/pm_flow/state_service/__init__.py`,
  `template/.agentic/pm_flow/state_service/schema.py`,
  `template/.agentic/pm_flow/state_service/migrate.py`,
  `template/.agentic/pm_flow/state_service/cli.py`,
  `tests/knowledge_state_test.sh`,
  `tests/database_state/state/schema_migration/scenario.zsh`,
  `docs/database-state-api.md`.
- Reuse: `store.SCHEMA`, `store.connect`, `store._migrate`, `store.dumps`,
  `store.content_hash`, `sqlite3.Connection.backup`; test harness shape from
  `tests/store_ledger_test.sh`; existing store tests `tests/store_ledger_test.sh`,
  `tests/outcome_record_test.sh` and `tests/trace_commands_test.sh` as the
  regression net for preserved identities.
- Behaviour: `store.SCHEMA_VERSION = 2`; `_migrate` reads the current version,
  and for each step below the target copies the database file to
  `<db>.v<current>.bak` with `Connection.backup` before executing that step's
  DDL inside one transaction and bumping the version row; a newer version still
  refuses as today. `cli.py migrate --dry-run` prints the current version,
  target version and the tables each step would add without writing;
  `--apply` performs it and prints the backup path. Rollback boundary: a
  `.v1.bak` restored over the store is a complete version-1 store; document
  this and that rollback after version-2 writes loses those writes and must be
  refused unless `--discard-new-state` is passed.
- Acceptance IDs: A3 (identities and rejections rest on this schema), A15
  (transaction and change tables).
- Validation: `zsh tests/knowledge_state_test.sh` prints one `ok
  schema_migration` line and `knowledge state tests passed`; the scenario
  creates a version-1 store with `store.py` from git (`git show
  HEAD:template/.agentic/pm_flow/store.py` into the temp root), inserts a
  project, a task and an attempt, reopens it with the new `store.py`, and
  asserts the backup file exists, `schema_version` is 2, the row ids are
  unchanged, and `sqlite_master` lists every new table and unique index.
  `zsh tests/store_ledger_test.sh`, `zsh tests/outcome_record_test.sh` and
  `zsh tests/trace_commands_test.sh` still pass.
- Depends on: None.

## Task T2 — Transaction service, reducer, projection hash and rejections

- Status: done (cycle 002, accepted 2026-09-13)
- Outcome: a request through `cli.py apply` appends one contiguous
  transaction with its changes and a stored projection hash; a repeated
  idempotency key returns the first result without a new row; a stale
  `expected_version` returns `conflict`; a task, dependency or timeline from
  another project returns `invalid_reference` or `denied_scope`; adding a
  dependency that closes a cycle returns `cyclic_dependency`; `timeline verify`
  reproduces the head hash from the log, and a direct SQL edit to a projection
  row makes `verify` report the mismatching table.
- Paths: `template/.agentic/pm_flow/state_service/service.py`,
  `template/.agentic/pm_flow/state_service/reducer.py`,
  `template/.agentic/pm_flow/state_service/projection.py`,
  `template/.agentic/pm_flow/state_service/errors.py`,
  `template/.agentic/pm_flow/state_service/extensions.py`,
  `template/.agentic/pm_flow/state_service/cli.py`,
  `tests/database_state/state/transactions/scenario.zsh`,
  `tests/database_state/state/rejections/scenario.zsh`,
  `docs/database-state-api.md`.
- Reuse: T1 schema; `store.dumps` for canonical JSON; `store.content_hash`.
- Behaviour: `timeline.create` with purpose `production` creates the single
  production timeline for a project (second attempt: `conflict`). Operations
  `task.create`, `task.revise`, `task.set_status`, `task.assign`,
  `dependency.add`, `dependency.remove`. Cycle check walks concrete
  `task_dependencies` for the timeline before insert. Every request runs in
  one `BEGIN IMMEDIATE`; `seq` is `head_seq + 1` read inside it; `timelines.
  head_seq` and `version` advance in the same transaction. `verify` builds an
  in-memory projection by replaying `state_changes` from seq 1 and compares
  its hash with the stored hash at head; on mismatch it lists the tables whose
  canonical rows differ.
- Acceptance IDs: A3 (invalid references, cross-project access, cyclic
  dependencies, stale updates), A15 (contiguous sequence, outside-mutation
  detection).
- Validation: `zsh tests/knowledge_state_test.sh` prints `ok transactions` and
  `ok rejections`. The transactions scenario applies five requests and asserts
  `seq` 1..5 with no gap, one row per idempotency key after a repeat, and
  `verify` exit 0; then runs a raw `UPDATE tasks SET status=...` and asserts
  `verify` exits non-zero naming `tasks`. The rejections scenario asserts each
  error code listed in the outcome by exact string.
- Depends on: T1.

## Task T3 — Jobs: leases, fencing, retries and bounded queries under competing processes

- Status: pending
- Outcome: several processes leasing one queued job get exactly one lease;
  the loser receives `conflict`; a worker completing with an epoch older than
  the current lease receives `lost_lease` and the job stays as the current
  lessee left it; an expired lease can be re-leased with a higher epoch;
  `max_attempts` moves a job to `dead`; `query eligible` and `query context`
  return bounded results.
- Paths: `template/.agentic/pm_flow/state_service/jobs.py`,
  `template/.agentic/pm_flow/state_service/queries.py`,
  `template/.agentic/pm_flow/state_service/cli.py`,
  `template/.agentic/pm_flow/state_service/extensions.py`,
  `tests/database_state/state/job_fencing/scenario.zsh`,
  `docs/database-state-api.md`.
- Reuse: T2 service and reducer; `BUSY_TIMEOUT_MS` from `store.py`.
- Behaviour: `job.create` records kind, subject, idempotency key,
  `input_fingerprint`, `max_attempts`; `job.lease` succeeds only when state is
  `queued` or the lease has expired, sets `leased`, `lease_owner`,
  `lease_until`, increments `fencing_epoch` and `attempt_count`; `job.complete`
  and `job.fail` require `fencing_epoch` equal to the job's current epoch and
  state `leased`; `job.fail` requeues below `max_attempts` and sets `dead`
  otherwise; `heartbeat` extends `lease_until` only when owner and epoch match.
  `query eligible` lists tasks whose dependencies are all in a terminal
  accepted status; `query context --max-bytes N` returns a task's revision,
  assignments and dependency titles truncated to N bytes with a `truncated`
  flag. `register_job_handler(kind, fn)` is the handler registry `job run`
  consults.
- Acceptance IDs: A3 (competing workers, stale epoch).
- Validation: `zsh tests/knowledge_state_test.sh` prints `ok job_fencing`.
  The scenario launches eight background `cli.py job lease` processes for one
  job with `&` and `wait`, asserts exactly one stdout contains
  `"leased": true` and seven contain `conflict`; then it makes the lease
  expire (`--lease-seconds 1` and a short sleep), leases again from a second
  process, and asserts the first process's `job complete` returns
  `lost_lease` while the second's succeeds, with `attempt_count` 2 and one
  `succeeded` state.
- Depends on: T2.

## Task T4 — `integrate_source` job with crash recovery and no second merge

- Status: pending
- Outcome: an `integrate_source` job merges a section branch into the base
  branch through the worker, records the resulting merge commit in its
  completing transaction, and a worker killed after the Git merge but before
  completion is recovered by the next lease without creating a second merge
  commit. This is the brief's first user-visible scenario end to end.
- Paths: `template/.agentic/pm_flow/source_integration.py`,
  `template/.agentic/pm_flow/state_service/jobs.py`,
  `template/.agentic/pm_flow/state_service/cli.py`,
  `tests/database_state/state/integrate_source_recovery/scenario.zsh`,
  `docs/database-state-api.md`.
- Reuse: `merge_section_worktree` and `sync_section_worktree` in
  `template/.agentic/pm_flow/driver.zsh` for the precheck and merge commands
  (`merge-tree --write-tree`, `merge --no-ff --no-edit`, git identity from
  `PM_FLOW_GIT_NAME`/`PM_FLOW_GIT_EMAIL`); T3 lease and completion.
- Behaviour: the job payload carries `repository`, `base`, `branch`,
  `base_head`, `branch_head`. `job run --kind integrate_source` leases,
  commits, then in `source_integration.integrate()` first probes: if
  `git rev-parse base` has a commit whose parents are `base_head` and
  `branch_head`, or `git merge-base --is-ancestor branch_head base` holds, it
  returns that commit as already integrated. Otherwise it runs the precheck and
  merge. Then it sends `job.complete` with `source.integrated` recording
  `result_commit` and `recovered: true|false`. A test-only flag
  `--exit-after-git <code>` makes the worker exit with that code after the
  merge and before completion; production callers never pass it. Only the
  production timeline may target the project's base branch; other timelines
  get `denied_side_effect`.
- Acceptance IDs: A3 (crash between Git operation and completion recovers
  without a second merge).
- Validation: `zsh tests/knowledge_state_test.sh` prints
  `ok integrate_source_recovery` and finishes with `knowledge state tests
  passed`. The scenario creates a git repository with a base branch and a
  section branch, runs `job run --exit-after-git 70`, asserts exit 70, one
  merge commit on base, and the job still `leased`; waits out the lease, runs
  `job run` again, and asserts `git rev-list --count --merges base` is still 1,
  the job is `succeeded`, `recovered` is true and `result_commit` equals the
  existing merge commit.
- Depends on: T3.

## Task T5 — Fixture history, checkpoints and `verify` replay end to end

- Status: pending
- Outcome: a fixture history built only through service requests, containing
  rework, a panel join, a decomposition, a human gate and a crash between
  dispatch and publication, has checkpoints whose stored projection hashes
  `timeline verify` reproduces at every checkpoint and at the head; a
  projection row edited outside the service is detected. This is the brief's
  second user-visible scenario end to end.
- Paths: `template/.agentic/pm_flow/state_service/reducer.py`,
  `template/.agentic/pm_flow/state_service/projection.py`,
  `template/.agentic/pm_flow/state_service/cli.py`,
  `tests/timeline_replay_test.sh`,
  `tests/database_state/replay/fixture_history/scenario.zsh`,
  `tests/database_state/replay/fixture_history/history.jsonl`,
  `docs/database-state-api.md`.
- Reuse: T2 verify; T3 jobs; discovery harness from
  `tests/knowledge_state_test.sh`.
- Behaviour: operations `execution.create`, `execution.complete`,
  `output.publish`, `panel.expect`, `panel.join` (policies `all` and
  `quorum`, membership frozen at join), `decomposition.apply` (child tasks and
  dependencies in one transaction, cycle-checked), `gate.open`,
  `gate.resolve`, `checkpoint.create` (stores `projection_hash` and
  `source_heads_json` at that seq). `verify` walks every checkpoint in seq
  order, replaying up to each and comparing, then the head, printing one line
  per position with `match` or `mismatch`. `history.jsonl` is one request per
  line; the scenario feeds it through `apply`, simulating the crash by leasing
  a job and never completing it before the next request.
- Acceptance IDs: A15.
- Validation: `zsh tests/timeline_replay_test.sh` prints `ok fixture_history`
  and `timeline replay tests passed`; the scenario asserts `verify` exit 0
  with `match` on every checkpoint line and the head, that `state_transactions`
  seq values are contiguous, and that after a raw `UPDATE executions ...`
  `verify` exits non-zero with `mismatch` at the head and names `executions`.
- Depends on: T4.

## Integration and end-to-end validation

- T4 proves user-visible scenario 1 (`zsh tests/knowledge_state_test.sh`) and
  T5 proves scenario 2 (`zsh tests/timeline_replay_test.sh`). Both entry
  points run every discovered scenario, so the final evidence is both commands
  passing on the same commit alongside `zsh tests/store_ledger_test.sh`.

## Risks and rollback

- Migration risk: a partial version-2 apply on a live store. Mitigation:
  backup before DDL, DDL in one transaction, version row bumped last. Rollback:
  restore `<db>.v1.bak`; after version-2 writes this loses evidence and the CLI
  refuses without `--discard-new-state`.
- Hash instability: projection hash depending on wall-clock or row order.
  Mitigation: canonical ordering by primary key, `updated_at` excluded from the
  hash, timestamps supplied by the request when replaying.
- Lease races under WAL: two `BEGIN IMMEDIATE` writers serialise; `busy_timeout`
  already 10 s. Test uses eight processes to exercise it.
- Ownership: other sections add scenario directories under
  `tests/database_state/`; that path is owned here, so their additions need an
  explicit integration assignment.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A3 | T1, T2, T3, T4 | `zsh tests/knowledge_state_test.sh` passes with scenarios schema_migration, transactions, rejections, job_fencing, integrate_source_recovery; job_fencing and integrate_source_recovery use multiple processes |
| A15 | T1, T2, T5 | `zsh tests/timeline_replay_test.sh` passes with fixture_history showing `match` at every checkpoint and head and `mismatch` after an outside edit |
