# state-service section PM state

## Current task

- T2 (next cycle): transaction service, reducer, projection hash and
  rejections.

## Completed tasks and evidence

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
  without `--discard-new-state` and is deferred until a write path exists (T2).

## Blockers

- None observed.

## Next eligible task

- T2.
