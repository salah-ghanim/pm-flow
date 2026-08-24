# store-ledger workplan

## Design summary

- Move the readers first, behind the same `cost.py` commands, so the driver
  switches data source by dropping one argument. Import legacy rows once,
  keyed on `response_path`. Then stop the TSV write and point the budget
  check and the dispatch counter at `attempts`.

## Interfaces and data changes

- `cost.py total <project_dir> [section]`, `cost.py report <project_dir>`,
  `cost.py import <project_dir>`; `cost.py one` unchanged.
- No schema change. The store is `<project_dir>/runs/pm_flow.db`
  (`store.default_path`). `attempts` has no `section_key` column: a section is
  `attempts.task_id → tasks.key`, NULL meaning `(project)`; that is how
  `telemetry.py attempt-start --task <section_key>` records live dispatches,
  and the brief's "`section_key`" means this join. The project row is
  `projects.key = basename(project_dir)` (the driver runs projects at
  `$FLOW_DIR/<key>`).
- `response_path` is the same absolute string in the TSV's sixth column and in
  `attempts.response_path` (the driver passes `$response_json` to both), so it
  keys the import without normalisation.
- Parity rule for A1: the importer reproduces today's `cost.totals()`
  precedence exactly. A TSV row is authoritative for its `response_path`, even
  when its cost column is blank (then `cost_usd` is NULL and the envelope is
  not re-parsed); only envelopes absent from the TSV get `cost_of()`. Any
  "smarter" re-derivation changes the cents and fails A1.
- Interim safety (decided cycle 002): `cost.py total|report` run the T1 import
  silently before reading `attempts`, so a legacy project never reads zero at
  any point in the T2→T4 sequence, and the driver's TSV-seeded budget tests
  stay green while `spent_usd` still passes the ledger path. The readers'
  *figures* come from `attempts` only; the import is the single legacy
  absorber. A trailing operand ending `.tsv` is recognised as the legacy
  ledger argument and ignored (the unchanged driver keeps calling with it
  until T3, which deletes the shim).

## Task T1 — Idempotent legacy import

- Status: done (cycle 001, GO).
- Outcome: `cost.py import <project_dir>` inserts an `attempts` row for every
  TSV row or envelope not already represented, keyed on `response_path`, and
  reports how many it added; a second run adds zero.
- Paths: `template/.agentic/pm_flow/cost.py`, `tests/store_ledger_test.sh`.
- Reuse: `store.connect(store.default_path(project_dir))`; the column list
  `telemetry.py cmd_attempt_start` / `cmd_attempt_end` write; `cost_of`,
  `section_of`, `response_files`, `ledger_rows` already in `cost.py`;
  `telemetry.usage_from_response` for token columns.
- Row shape: `project_id` from `projects.key = basename(project_dir)` (insert
  if absent); `task_id` from `tasks (project_id, key=section)` (insert if
  absent), NULL for `(project)`; `role_key` = TSV column 3 or `"unknown"` for
  an envelope-only row; `label` = TSV column 4; `started_at` = TSV column 1
  parsed as UTC, else the envelope's mtime; `status = "imported"`;
  `cost_usd` per the parity rule; `response_path` = the absolute string;
  `metadata = {"source": "cost_ledger.tsv"|"envelope"}`.
- Acceptance IDs: A1, A3.
- Validation: `zsh tests/store_ledger_test.sh` — a fixture with 5 TSV rows (one
  with a blank cost), 2 of them also present as envelopes, plus 1 envelope
  absent from the TSV, imports 6 rows; the store total equals `cost.py total
  <dir> <tsv>` to the cent; second import prints `imported=0` and the row
  count is unchanged; a row's section is readable via `tasks.key`.
- Depends on: None.

## Task T2 — Readers on the store

- Status: assigned (cycle 002).
- Outcome: `cost.py total|report` compute all figures from `attempts` (after a
  silent idempotent import); `watch.py` reads the store read-only; a Codex
  attempt row shows its non-zero tokens in `report`. Final CLI arity lands
  now: `total <project_dir> [section]`, `report <project_dir>`, with the
  `.tsv`-operand shim from the interim-safety note.
- Paths: `template/.agentic/pm_flow/cost.py`, `template/.agentic/pm_flow/watch.py`,
  `tests/store_ledger_test.sh`.
- Reuse: T1's `import_legacy` (refactored to return its count; only the
  `import` subcommand prints `imported=N` — `spent_usd` parses `total` stdout
  as one number); `store.connect`/`store.default_path`; `watch.py in_flight`
  unchanged.
- Query shape: sum `COALESCE(cost_usd, 0)` over all attempts regardless of
  `status`, no project-id filter (per-project DB; a key-mismatch filter is a
  read-zero risk); section is `COALESCE(tasks.key, '(project)')` via LEFT
  JOIN. `watch.py` never writes: no import, `mode=ro` connection, missing DB
  is an empty view (may under-report until the first `cost` run imports;
  display-only, accepted).
- Acceptance IDs: A1, A2.
- Validation: `zsh tests/store_ledger_test.sh` — totals match figures computed
  independently from the fixture files; old and new arity agree; a row with
  `input_tokens=76195` prints those tokens; deleting the TSV after the first
  read changes nothing; inflating an already-imported TSV row's cost changes
  nothing (the TSV is not a summing source); `grep cost_ledger watch.py` finds
  nothing.
- Depends on: T1.

## Task T3 — Driver stops writing the ledger

- Status: pending.
- Outcome: `record_dispatch_cost` is gone; `spent_usd` and `dispatch_count`
  read the store through `cost.py`; `cmd_cost` calls `cost.py report
  <project_dir>`.
- Paths: `template/.agentic/pm_flow/driver.zsh` (the five named functions),
  `tests/store_ledger_test.sh`.
- Reuse: T2's commands.
- Acceptance IDs: A4.
- Validation: `zsh template/.agentic/pm_flow/tests/run.zsh` exits 0 including
  F14 (ceiling enforced); `zsh tests/store_ledger_test.sh` — one stub tick
  leaves `runs/` without a TSV and `git status` clean under it; a project
  seeded at its ceiling is refused.
- Depends on: T2.

## Task T4 — End-to-end through the installed command

- Status: pending.
- Outcome: a packaged install with a legacy TSV runs `pm-flow cost` before and
  after import with equal totals, dispatches once, and shows the new attempt
  with no file written under `runs/`.
- Paths: `tests/store_ledger_test.sh`.
- Reuse: the packaged-layout harness in `tests/packaged_layout_test.sh`.
- Acceptance IDs: A1–A5.
- Validation: `zsh tests/store_ledger_test.sh`, `zsh tests/pm_flow_test.sh`,
  `zsh tests/packaged_layout_test.sh` exit 0.
- Depends on: T3.

## Integration and end-to-end validation

- T4 proves scenarios 1–3 through the installed command.

## Risks and rollback

- A wrong import under-reports spend and re-authorises a budget. T1's
  to-the-cent check against the TSV figure is the guard; rollback restores the
  TSV read in `cost.py` without touching stored rows.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T4 | Post-import totals equal TSV totals to the cent |
| A2 | T2, T4 | Readers use the store; Codex tokens visible |
| A3 | T1 | Second import adds zero rows |
| A4 | T3, T4 | No write under `runs/`; ceiling still refuses |
| A5 | T3, T4 | Three suites exit 0 |
