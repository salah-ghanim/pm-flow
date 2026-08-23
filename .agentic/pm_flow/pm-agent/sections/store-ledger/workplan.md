# store-ledger workplan

## Design summary

- Move the readers first, behind the same `cost.py` commands, so the driver
  switches data source by dropping one argument. Import legacy rows once,
  keyed on `response_path`. Then stop the TSV write and point the budget
  check and the dispatch counter at `attempts`.

## Interfaces and data changes

- `cost.py total <project_dir> [section]`, `cost.py report <project_dir>`,
  `cost.py import <project_dir>`; `cost.py one` unchanged.
- No schema change.

## Task T1 — Idempotent legacy import

- Status: pending.
- Outcome: `cost.py import <project_dir>` inserts an `attempts` row for every
  TSV row or envelope not already represented, keyed on `response_path`, and
  reports how many it added; a second run adds zero.
- Paths: `template/.agentic/pm_flow/cost.py`, `tests/store_ledger_test.sh`.
- Reuse: `store.py` connection and `attempts` insert; `cost.py cost_of` for
  envelope amounts.
- Acceptance IDs: A1, A3.
- Validation: `zsh tests/store_ledger_test.sh` — a fixture with 5 TSV rows, 2 of
  them also present as envelopes, imports 5 rows; totals equal the
  TSV-computed figure to the cent; second import adds 0; a mutation that keys
  on timestamp instead of `response_path` double-counts and fails.
- Depends on: None.

## Task T2 — Readers on the store

- Status: pending.
- Outcome: `cost.py total|report` and `watch.py` read `attempts` only; a Codex
  attempt row shows its tokens in `report`.
- Paths: `template/.agentic/pm_flow/cost.py`, `template/.agentic/pm_flow/watch.py`,
  `tests/store_ledger_test.sh`.
- Reuse: T1's store access; `watch.py in_flight` unchanged.
- Acceptance IDs: A1, A2.
- Validation: `zsh tests/store_ledger_test.sh` — report on a seeded store
  matches hand-computed totals; a row with `input_tokens=76195` prints those
  tokens; deleting the TSV changes nothing; a mutation restoring the TSV read
  fails.
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
