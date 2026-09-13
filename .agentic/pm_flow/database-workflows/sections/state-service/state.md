# state-service section PM state

## Current task

- None assigned. T3 is next.

## Completed tasks and evidence

- T2 (cycle 002, accepted 2026-09-13) — A3 (invalid references,
  cross-project access, cyclic dependencies, stale updates), A15 (contiguous
  sequence, outside-mutation detection). `state_service/service.py apply`,
  `reducer.py` (seven v1 operations, `(op, op_version)` table, extension
  merge), `projection.py` (`digests`, `hash_projection`, `replay`, `verify`),
  `errors.py` (twelve codes), `extensions.py`, `cli.py apply` and `timeline
  log|projection|verify`. Contract in `docs/database-state-api.md`.
  - `zsh tests/knowledge_state_test.sh` → `ok rejections` (nine codes
    matched by exact `"error": "<code>"` string), `ok schema_migration`,
    `ok transactions` (seq 1 2 3 4 5; replay of seq 3 returns transaction 3
    with 5 rows; verify match true; after raw `UPDATE tasks` exit 1 with
    `mismatched_tables ["tasks"]`), `knowledge state tests passed`, exit 0.
  - `zsh tests/store_ledger_test.sh`, `zsh tests/outcome_record_test.sh`,
    `zsh tests/trace_commands_test.sh` → exit 0 unchanged;
    `zsh template/.agentic/pm_flow/tests/run.zsh` → `all suites passed`.
  - Independent check (cycles/002/review_probe.zsh): same request file twice
    on a fresh store differs only by `"idempotent_replay": true`, 1 log row and
    2 change rows; `expected_version` one behind → `conflict`, rows and
    head unchanged; same key with a different body → `conflict`; a two-op
    request whose second op is `a→a` leaves no task from the first op; raw
    `UPDATE timelines SET head_seq` → verify exit 1 naming `timelines`.
  - Mutation checks on engine copies, each re-running the scenario: drop cycle
    check → rejections fails at `b depends on a`; drop scope check → fails at
    `task key outside scope`; exclude `tasks.status` from the hash →
    transactions fails at "verify exited 0 after a raw UPDATE"; replace the
    replayed digest with the stored one → fails at `mismatched tables`.
    Unmutated copies pass.

- T1 (cycle 001, accepted 2026-09-13) — A3, A15 schema foundation.
  Store at schema version 2: `store._migrate` is a per-version ladder that
  backs up to `<db>.v<n>.bak` through a second connection under
  `BEGIN IMMEDIATE`, verifies the copy (version row and `quick_check`) before
  renaming it into place, then runs the step DDL and bumps the version in one
  transaction. `state_service/schema.py` holds STEP_2 (principals, timelines,
  state_transactions, state_changes, jobs, checkpoints, timeline_sources,
  experiment_arms, experiment_replicates, task_revisions, task_assignments,
  executions, environment_revisions, human_gates; column adds on projects,
  tasks, task_dependencies). `state_service/cli.py migrate --dry-run|--apply`.
  Contract in `docs/database-state-api.md`.
  - `zsh tests/knowledge_state_test.sh` → `ok schema_migration`,
    `knowledge state tests passed`, exit 0.
  - `zsh tests/store_ledger_test.sh`, `zsh tests/outcome_record_test.sh`,
    `zsh tests/trace_commands_test.sh` → exit 0 unchanged.
  - `zsh template/.agentic/pm_flow/tests/run.zsh` → `all suites passed`,
    exit 0.
  - Independent check: v1 store built from `HEAD:store.py`; `cli.py migrate
    --dry-run` printed current 1, target 2, 14 tables, backup path; file stayed
    at version 1 with no backup; `--apply` reached version 2, ids unchanged,
    `.v1.bak` at version 1; version 99 refused with `{"error":
    "migration_failed"}` exit 1.
  - Mutation checks on engine copies: removing the backup call → scenario
    fails at "left no .v1.bak"; removing `jobs(timeline_id, idempotency_key)`
    index → fails at "no unique index"; swapping DDL before backup → scenario
    still passes because the step transaction rolls back and the backup reads
    the committed snapshot, so the order is observably equivalent (order
    verified by reading `store.py`).

## Active decisions

- Extend `store.py` schema to version 2 through a per-version ladder in
  `_migrate`; backup with `sqlite3.Connection.backup` before each step.
- Schema steps live in `state_service/schema.py` and are loaded by path
  relative to `store.py`, lazily, so a store already at the target version
  never needs the file.
- `principals` (spec 5.1) is in step 2 as the parent of
  `state_transactions.actor_id`; columns whose parent table a later section
  creates (`jobs.workflow_run_id`, execution workflow-run/node columns,
  `experiment_arms.experiment_id`) are added by that section's step, because
  SQLite refuses inserts into a table whose foreign key names a missing table.
- Lease metadata (`lease_owner`, `lease_until`) is excluded from the projection
  hash; `fencing_epoch` and job state are included. `job.lease` is a logged
  transaction; heartbeat is not.
- Legacy rows (NULL `timeline_id`) are outside every projection hash;
  `projects.authority_mode` defaults to `legacy` and this section never flips it.
- Test entry points discover `tests/database_state/{state,replay}/*/scenario.zsh`.
  The schema_migration scenario walks `git rev-list` back to the newest
  committed `store.py` at `SCHEMA_VERSION = 1`, so it keeps working after this
  migration is committed.
- Rollback after version-2 writes is lossy; a restore command must refuse
  without `--discard-new-state`. The write path now exists but the command is
  not in any workplan task; fold it into T5 or an integration assignment.
- Replay results are recomputed from the log row, not stored:
  `timeline_version = version - (head_seq - seq)`, valid because every
  transaction advances both by one and both are in the hash.
- Change payloads are `{"args", "bound"}`; `bound` carries allocated row ids
  (and project id and key for `timeline.create`) so replay reproduces ids.
  Reducers read only `context.at` (the transaction's `committed_at`).
- A log row for a timeline-creating request is inserted right after
  `timeline.create` runs, still inside the same `BEGIN IMMEDIATE`.
- `tasks` is unique on `(project_id, key)` across timelines and legacy rows;
  experiment or replay timelines that reuse task keys need a later schema step.
- Extension registrations are process-local and the CLI loads no plugins; a
  separate `verify` process cannot replay extension operations until a loader
  exists (T3 or later).
- `verify` requires stored, replayed and live hashes all equal;
  `mismatched_tables` compares live to replayed per table.

## Blockers

- None observed.

## Next eligible task

- T3.
