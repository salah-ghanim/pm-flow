## Objective

- The store is the cost ledger. No dispatch writes a per-dispatch text file
  into the host repository, and every cost question is answered from
  `attempts`.

## Current baseline

- `driver.zsh record_dispatch_cost` appends one row per dispatch to
  `runs/cost_ledger.tsv`; `spent_usd`, `cmd_cost` and `dispatch_count` read it,
  and `cost.py total|report` re-parse it plus every response envelope.
- `watch.py ledger_rows` reads the same file.
- `attempts` already holds every fact the TSV holds, plus tokens, duration,
  attempt count and span.

## Deliverables

- `cost.py` and `watch.py` reading `attempts`; a one-time, idempotent importer
  for legacy TSV rows and envelopes.
- `driver.zsh` no longer writing the TSV; budget enforcement and dispatch
  counting read the store.
- `tests/store_ledger_test.sh`.

## User-visible scenarios

1. `pm-flow cost` on a project that has spent money prints per-section and
   total spend from the store, with a row for a Codex attempt showing its
   tokens.
2. A project carrying a legacy `cost_ledger.tsv` and no store attempts runs
   `pm-flow cost` and sees the same totals it saw before, to the cent.
3. After one dispatch, `git status` in the host repository shows no change
   under `runs/`.

## Interfaces produced

- `cost.py total|report` read `<project_dir>`'s store; the ledger-path argument
  is gone.
- `cost.py import <project_dir>`: idempotent legacy import.

## Interfaces consumed

- `attempts` columns (`cost_usd`, token columns, `section_key`, `status`,
  `response_path`).

## Scope

- In: the readers, the importer, the driver's ledger functions, the budget
  check's data source, the test.
- Out: telemetry emission, attribute naming, the `cost` command's routing in
  `pm_flow.sh` (unchanged).

## Non-goals

- A new accounting table or a second cost parser.
- Migrating the driver's file-derived state machine to SQLite.

## Priority

- must-have: the per-dispatch TSV write is the churn the store exists to
  remove, and the plan's completion criteria name its removal.

## Owned paths

- `template/.agentic/pm_flow/cost.py`
- `template/.agentic/pm_flow/watch.py`
- `template/.agentic/pm_flow/driver.zsh`
- `tests/store_ledger_test.sh`
- `template/.agentic/pm_flow/tests/transitions.zsh`
- `template/.agentic/pm_flow/tests/on_demand.zsh`
- `template/.agentic/pm_flow/tests/governance.zsh`
- `template/.agentic/pm_flow/README.md`

## Dependencies

- None.

## Constraints and fixed decisions

- `driver.zsh` edits are limited to `cost_ledger_file`, `record_dispatch_cost`,
  `spent_usd`, `cmd_cost` and `dispatch_count`; anything wider is a boundary
  conflict to report.
- The importer keys on `response_path` so a dispatch present in both the TSV
  and an envelope is counted once.
- Budget enforcement must never read zero for a project that has spent.

## Acceptance

- A1: On a project with a legacy TSV, `pm-flow cost` after import prints the
  same per-section and total figures the TSV-based report printed, to the
  cent.
- A2: `pm-flow cost` and `watch.py` read only the store; a Codex attempt's row
  shows its non-zero input and output tokens.
- A3: Running the import twice on a project with both TSV rows and envelopes
  leaves totals unchanged the second time.
- A4: A dispatch appends nothing under `runs/`; a project at its `max_usd`
  ceiling is still refused its next dispatch with the store as the source.
- A5: `zsh tests/store_ledger_test.sh`, `zsh tests/pm_flow_test.sh` and
  `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0.

## Rejection conditions

- Budget enforcement reads zero for a project that has spent money.
- A dispatch is double-counted from TSV and envelope.
- `cost_ledger.tsv` is still written, under any name.
- A file outside Owned paths is modified, or a driver function outside the
  five named is changed.

## Open questions

- None.

## Boundary extended, authorized 2026-08-24

- Added to Owned paths: `template/.agentic/pm_flow/tests/transitions.zsh`,
  `template/.agentic/pm_flow/tests/on_demand.zsh`,
  `template/.agentic/pm_flow/tests/governance.zsh` and
  `template/.agentic/pm_flow/README.md`. No live section owned them, and
  their lines that read, seed or document `runs/cost_ledger.tsv` cannot
  survive A4.
- Acceptance is unchanged. Edits to these four files are limited to what the
  ledger's removal forces: an assertion that read the TSV reads the store, a
  seed that wrote the TSV seeds the store, the README describes the store.
- Rejection condition, binding the reviewer: work is not rejected for
  modifying these four files within that limit.
