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
  (`store.default_path`), the same file the driver's `telemetry_store_file`
  names (`RUNS_DIR=$PROJECT_DIR/runs`). `attempts` has no `section_key`
  column: a section is `attempts.task_id → tasks.key`, NULL meaning
  `(project)`; that is how `telemetry.py attempt-start --task <section_key>`
  records live dispatches, and the brief's "`section_key`" means this join.
  The importer's project row is `projects.key = basename(project_dir)`; the
  driver's live rows use `PROJECT_KEY`. Readers therefore never filter on
  `project_id` (per-project DB; a key mismatch would be a read-zero risk) and
  resolve the section through `task_id` alone, which is correct under either
  project row.
- `response_path` is the same absolute string in the TSV's sixth column, in
  `attempts.response_path` written by `telemetry.py attempt-end --response`,
  and in `cost.response_files()` (the driver passes `$response_json` to all
  three), so it keys the import without normalisation.
- Parity rule for A1: the importer reproduces today's `cost.totals()`
  precedence exactly. A TSV row is authoritative for its `response_path`, even
  when its cost column is blank (then `cost_usd` is NULL and the envelope is
  not re-parsed); only envelopes absent from the TSV get `cost_of()`. Any
  "smarter" re-derivation changes the cents and fails A1.
- Readers' sums: `SUM(COALESCE(cost_usd, 0))` over every `attempts` row
  regardless of `status` (failed dispatches are paid for; imported rows carry
  `status='imported'`), section = `COALESCE(tasks.key, '(project)')` via LEFT
  JOIN on `task_id`.
- Interim rule, T2→T3 (revised cycle 002): `cost.py total|report` carry two
  arities until T3.
  - New: `total <project_dir> [section]`, `report <project_dir>` run
    `import_legacy` silently, then compute every figure from `attempts`. A
    legacy project therefore never reads zero, and the import is the single
    legacy absorber.
  - Legacy, kept verbatim until T3 deletes it: `total <project_dir> <ledger>
    [section]`, `report <project_dir> <ledger>`, recognised by the operand
    ending `.tsv`, run today's `totals()` with **no** import side effect. The
    unchanged driver keeps calling this form, so the engine suites stay green
    through T2.
  - Why the legacy arity must not import: `template/.agentic/pm_flow/tests/
    governance.zsh:198-199` seeds two TSV rows that share the response key
    `y` and expects `$1.00` of spend; an import keyed on `response_path`
    dedupes them to `$0.50` and the `$0.75` spend trigger stops firing.
    That fixture is T3's problem to resolve, not T2's.
- `report` output (final shape, unchanged by T3): per-section lines
  `<section>\t<cost .4f>` sorted by section, then `TOTAL\t<cost .4f>`, then one
  line per attempt, oldest first:
  `ATTEMPT\t<started_at as %Y-%m-%dT%H:%M:%SZ>\t<section>\t<role_key>\t<label>\t<cli or ->\t<cost .4f or ->\t<input_tokens or ->\t<output_tokens or ->`.
  `total` prints exactly one number (`spent_usd` parses it). Only the `import`
  subcommand prints `imported=N`.
- `watch.py` never writes: no import, `sqlite3.connect("file:<db>?mode=ro",
  uri=True)`, a missing store is an empty view and no file is created. It may
  under-report a legacy project until the first `cost.py total <project_dir>`
  run imports; display-only, accepted for the one cycle between T2 and T3.

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

- Status: done (cycle 002, GO).
- Outcome: `cost.py total <project_dir> [section]` and `report <project_dir>`
  compute every figure from `attempts` after a silent idempotent import;
  `report` lists each attempt with its tokens; `watch.py` reads the store
  read-only and no longer knows the TSV exists. The legacy `.tsv` arity keeps
  today's behaviour, untouched, for the driver until T3.
- Paths: `template/.agentic/pm_flow/cost.py`, `template/.agentic/pm_flow/watch.py`,
  `tests/store_ledger_test.sh`.
- Reuse: T1's `import_legacy` (refactored to return its count; the `import`
  subcommand prints it); `store.connect`/`store.default_path`; `watch.py
  in_flight` unchanged; `telemetry.py run-start|attempt-start|attempt-end`
  and `tests/fixtures/codex_events_real.jsonl` (13937 in / 5 out / 12032
  cached / 13942 total) to put a real Codex-shaped live row in the test store.
- Acceptance IDs: A1, A2.
- Validation: `zsh tests/store_ledger_test.sh` — new-arity totals equal the
  legacy-arity totals and the fixture arithmetic (alpha 3.7500, beta 8.3750,
  total 12.1250) to the cent; a live Codex row written by `telemetry.py`
  appears in `report` as `ATTEMPT\t…\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5`
  and is not re-imported (`imported=0`); deleting the TSV, then rewriting it
  with an inflated cost, changes no figure; `watch.py` prints the store spend
  and the Codex tokens, creates no store for a project without one, and
  `grep -c cost_ledger watch.py` prints `0`; `zsh tests/pm_flow_test.sh` and
  `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0 with the driver
  untouched.
- Depends on: T1.

## Task T3 — Driver stops writing the ledger

- Status: pending.
- Outcome: `record_dispatch_cost` is gone; `spent_usd` and `dispatch_count`
  read the store through `cost.py`; `cmd_cost` calls `cost.py report
  <project_dir>`; the legacy `.tsv` arity and `totals()` are deleted from
  `cost.py`.
- Paths: `template/.agentic/pm_flow/driver.zsh` (the five named functions),
  `template/.agentic/pm_flow/cost.py`, `tests/store_ledger_test.sh`.
- Reuse: T2's commands.
- Acceptance IDs: A4.
- Validation: `zsh template/.agentic/pm_flow/tests/run.zsh` exits 0 including
  F14 (ceiling enforced); `zsh tests/store_ledger_test.sh` — one stub tick
  leaves `runs/` without a TSV and `git status` clean under it; a project
  seeded at its ceiling is refused.
- Known boundary conflict (record for the handoff, resolve before assigning
  T3): `template/.agentic/pm_flow/tests/transitions.zsh:195,311`,
  `on_demand.zsh:158-160,240` and `governance.zsh:198-199` read or seed
  `runs/cost_ledger.tsv` directly. A5 requires `run.zsh` to pass and the brief
  forbids writing the TSV, so those three files must change, and they are
  outside Owned paths. T3 cannot be assigned inside the brief as written.
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
  `zsh tests/packaged_layout_test.sh` exit 0. Two checks the T2 suite cannot
  see (cycle 002 review): a store whose live rows sit under a different
  `projects.key` than the importer's (`basename(project_dir)` vs the driver's
  `PROJECT_KEY`) is summed whole, and the TSV `response_path` string written
  by the real driver matches `cost.response_files()` byte for byte (a
  non-normalised `PROJECT_DIR`, e.g. `a//b`, imports the same envelope twice).
- Depends on: T3.

## Integration and end-to-end validation

- T4 proves scenarios 1–3 through the installed command.

## Risks and rollback

- A wrong import under-reports spend and re-authorises a budget. T1's
  to-the-cent check against the TSV figure is the guard; rollback restores the
  TSV read in `cost.py` without touching stored rows.
- The store lives under `runs/`, which every install ignores
  (`template/.agentic/pm_flow/.gitignore`: `*/runs/*`), so the silent import
  creating `runs/pm_flow.db` never shows in the host's `git status` (A4).

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T4 | Post-import totals equal TSV totals to the cent |
| A2 | T2, T4 | Readers use the store; Codex tokens visible |
| A3 | T1 | Second import adds zero rows |
| A4 | T3, T4 | No write under `runs/`; ceiling still refuses |
| A5 | T3, T4 | Three suites exit 0 |
