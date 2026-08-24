# store-ledger workplan

## Design summary

- Move the readers first, behind the same `cost.py` commands, so the driver
  switches data source by dropping one argument. Import legacy rows once,
  keyed on `response_path`. Then move the driver's ledger functions off the
  TSV one command at a time: `pm-flow cost` first, because it lives inside
  Owned paths and no engine fixture reads its output; then the budget check,
  the dispatch counter and the TSV write itself, which cannot land until the
  three engine fixtures that read or seed `runs/cost_ledger.tsv` are owned.

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
- Interim rule, T2→T4 (revised cycle 003): `cost.py total` carries two
  arities until T4.
  - New: `total <project_dir> [section]`, `report <project_dir>` run
    `import_legacy` silently, then compute every figure from `attempts`. A
    legacy project therefore never reads zero, and the import is the single
    legacy absorber.
  - Legacy, kept verbatim until T4 deletes it: `total <project_dir> <ledger>
    [section]`, recognised by the operand ending `.tsv`, runs today's
    `totals()` with **no** import side effect. `spent_usd` keeps calling it,
    so `template/.agentic/pm_flow/tests/governance.zsh:198-199` (two TSV rows
    sharing the response key `y`, expecting `$1.00`) stays green: an import
    keyed on `response_path` dedupes them to `$0.50`.
  - The legacy `report <project_dir> <ledger>` arity is deleted by T3;
    `cmd_cost` was its only caller.
  - After T3, `pm-flow cost` (store) and `pm-flow status` (TSV) can disagree
    only on a project whose TSV repeats a `response_path`. No real dispatch
    does; the governance fixture does. Accepted until T4.
- `report` output (final shape): per-section lines `<section>\t<cost .4f>`
  sorted by section, then `TOTAL\t<cost .4f>`, then one line per attempt,
  oldest first:
  `ATTEMPT\t<started_at as %Y-%m-%dT%H:%M:%SZ>\t<section>\t<role_key>\t<label>\t<cli or ->\t<cost .4f or ->\t<input_tokens or ->\t<output_tokens or ->`.
  `total` prints exactly one number (`spent_usd` parses it). Only the `import`
  subcommand prints `imported=N`.
- `watch.py` never writes: no import, `sqlite3.connect("file:<db>?mode=ro",
  uri=True)`, a missing store is an empty view and no file is created. It may
  under-report a legacy project until the first `cost.py total|report
  <project_dir>` run imports; display-only, accepted until T4.
- Driver call order that T4 must respect (`driver.zsh:1023-1056`):
  `telemetry_begin_attempt` → `agent_exec.sh` writes the envelope →
  `record_dispatch_cost` (:1036) → `telemetry_end_attempt` records the
  `response_path` (:1038 on error, :1056 on success). Nothing before :1056
  may import: the envelope is on disk and its path is not yet in `attempts`,
  so an import there inserts it a second time.

## Task T1 — Idempotent legacy import

- Status: done (cycle 001, GO, merged as `558837f`).
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

- Status: done (cycle 002, GO, merged as `cb84e75`).
- Outcome: `cost.py total <project_dir> [section]` and `report <project_dir>`
  compute every figure from `attempts` after a silent idempotent import;
  `report` lists each attempt with its tokens; `watch.py` reads the store
  read-only and no longer knows the TSV exists. The legacy `.tsv` arities keep
  today's behaviour, untouched, for the driver.
- Paths: `template/.agentic/pm_flow/cost.py`, `template/.agentic/pm_flow/watch.py`,
  `tests/store_ledger_test.sh`.
- Reuse: T1's `import_legacy` (returns its count; the `import` subcommand
  prints it); `store.connect`/`store.default_path`; `watch.py in_flight`
  unchanged; `telemetry.py run-start|attempt-start|attempt-end` and
  `tests/fixtures/codex_events_real.jsonl` (13937 in / 5 out / 12032 cached /
  13942 total) to put a real Codex-shaped live row in the test store.
- Acceptance IDs: A1, A2 (at the `cost.py` level; the installed command is T3).
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

## Task T3 — `pm-flow cost` reads the store

- Status: done (cycle 003, GO; merge by the driver).
- Outcome: `cmd_cost` in `driver.zsh` runs `cost.py report "$PROJECT_DIR"`
  and nothing else; the legacy `report <project_dir> <ledger>` arity and its
  usage line are gone from `cost.py` (`totals()` and the legacy `total`
  arity stay for `spent_usd`); `pm-flow cost` through `pm_flow.sh`, on a
  project carrying a legacy TSV and a telemetry-written Codex attempt, prints
  the store report with that attempt's tokens, and prints the same report
  after the TSV is deleted. Scenario 1 becomes true through the installed
  command; this is A2's `pm-flow cost` clause.
- Paths: `template/.agentic/pm_flow/driver.zsh` (`cmd_cost` only, lines
  470-472), `template/.agentic/pm_flow/cost.py`, `tests/store_ledger_test.sh`.
- Reuse: T2's `report_store`; the suite's existing legacy fixture and its
  telemetry-written Codex row; the engine fixture layout in
  `template/.agentic/pm_flow/tests/transitions.zsh:21-35` (copy the template
  to `<work>/.agentic/pm_flow`, write `.project-key`, create
  `<key>/{project_state,sections,runs}`, `<key>/project.json`,
  `<key>/task_contract.md`, `<key>/project_state/plan.md`) so that
  `zsh -f <copy>/pm_flow.sh cost` resolves `PROJECT_DIR=<copy>/<key>`
  (`pm_flow.sh:17-23,548-556`); the watch check's symlink trick
  (`ln -s "$PROJECT_DIR" "$FLOW/<key>"`) to point that project at the
  suite's fixture; `pm_flow.sh:1935-1937` routes `cost` to `cmd_cost`.
- Acceptance IDs: A2; A5 as regression.
- Validation: `zsh tests/store_ledger_test.sh` → `store ledger tests
  passed`, exit 0, now also asserting: `pm_flow.sh cost` on the fixture
  project equals `python3 cost.py report <same project dir>` byte for byte
  and contains `ATTEMPT\t…\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5`
  and `TOTAL\t12.1650`; after `rm` of the TSV a second `pm_flow.sh cost` is
  identical; `python3 cost.py report <dir> <tsv>` exits 2; the `cmd_cost`
  body (`sed -n '/^cmd_cost()/,/^}/p' driver.zsh`) contains
  `report "$PROJECT_DIR"` and no `cost_ledger_file`. `zsh
  tests/pm_flow_test.sh` (10 `PASS:`), `zsh
  template/.agentic/pm_flow/tests/run.zsh` (`all suites passed`) and `zsh
  tests/packaged_layout_test.sh` (`cost reports the same spend after
  migration`) exit 0. `git diff --stat` lists only the three paths and the
  `driver.zsh` diff is one hunk inside `cmd_cost`.
- Depends on: T2.

## Task T4 — Driver stops writing the ledger

- Status: next; blocked on ownership (see the boundary conflict below); not
  assignable as the brief stands.
- Outcome: `record_dispatch_cost` writes nothing — its call at
  `driver.zsh:1036` is outside the five named functions and stays, so the
  body becomes a documented no-op and must not import (call order above);
  `spent_usd` runs `cost.py total "$PROJECT_DIR" [section]`;
  `dispatch_count` counts `ATTEMPT` lines of `cost.py report "$PROJECT_DIR"`
  (`grep -c '^ATTEMPT' || true`, since zero matches exits 1); `cost_ledger_file`
  is deleted; `totals()`, the legacy `.tsv` arity and its usage lines are
  deleted from `cost.py` (`ledger_rows` stays for the importer).
- Fixture edits, outside Owned paths today: `transitions.zsh:195,311` read
  the priced row (`0.5000`, `0.2500`) from an `ATTEMPT` line of `"$FLOWSH"
  cost` instead of `cat runs/cost_ledger.tsv`; `on_demand.zsh:158-160` read
  the `analysis alpha` attempt and its section from that line;
  `governance.zsh:198-199` seed two distinct response keys (`y1`, `y2`) so
  both rows import and `$1.00` / two dispatches still hold;
  `on_demand.zsh:240` needs no change (`y` is unique in that project and a
  seeded TSV row is a legacy-import scenario the importer absorbs).
- Paths: `template/.agentic/pm_flow/driver.zsh` (the five named functions),
  `template/.agentic/pm_flow/cost.py`, `tests/store_ledger_test.sh`, plus
  the three engine test files once owned.
- Reuse: T2's commands; `assert_within_budget` (`driver.zsh:610-624`) is
  unchanged and reads `spent_usd`.
- Acceptance IDs: A4, A5.
- Validation: `zsh template/.agentic/pm_flow/tests/run.zsh` → `all suites
  passed`, including `F7 the run refuses to spend past budget.max_usd`, `F14
  the configured ceiling is enforced`, `C2 $1.00 of ledger spend passes a
  $0.75 threshold`, `C2 two recorded dispatches arm the review`, `D1 the
  ledger carries the analysis`; `zsh tests/store_ledger_test.sh` — one stub
  tick on a fixture flow leaves `runs/` holding `pm_flow.db` and no
  `cost_ledger.tsv`, `git status --porcelain` in the work tree shows nothing
  under `runs/`, and a project seeded at `budget.max_usd` is refused its next
  dispatch with `project budget exhausted`; `git grep -n cost_ledger --
  template` → only the importer's lines in `cost.py`.
- Boundary conflict (reported in `handoff.md`, cycle 003): A4 forbids the TSV
  write and A5 requires `run.zsh` green, but
  `template/.agentic/pm_flow/tests/{transitions,on_demand,governance}.zsh`
  read or seed the TSV at the lines above. They are outside Owned paths and
  no live section owns `template/.agentic/pm_flow/tests/` (`green-suite` and
  `worktree-isolation` owned `tests/**` and are done). Unblocked by the brief's
  Owned paths gaining the three files. If the brief is unchanged at the cycle
  004 scope, that scope is `BLOCKED_EXTERNAL` naming this.
- Depends on: T3.

## Task T5 — End-to-end through the installed command

- Status: pending.
- Outcome: a packaged install with a legacy TSV runs `pm-flow cost` before and
  after import with equal totals, dispatches once, and shows the new attempt
  with no file written under `runs/`.
- Paths: `tests/store_ledger_test.sh`.
- Reuse: the packaged-layout harness in `tests/packaged_layout_test.sh`
  (`legacy_engine`/`installed` at lines 972 and 1073).
- Acceptance IDs: A1–A5.
- Validation: `zsh tests/store_ledger_test.sh`, `zsh tests/pm_flow_test.sh`,
  `zsh tests/packaged_layout_test.sh` exit 0. Two checks the T2 suite cannot
  see (cycle 002 review): a store whose live rows sit under a different
  `projects.key` than the importer's (`basename(project_dir)` vs the driver's
  `PROJECT_KEY`) is summed whole, and the TSV `response_path` string written
  by the real driver matches `cost.response_files()` byte for byte (a
  non-normalised `PROJECT_DIR`, e.g. `a//b`, imports the same envelope twice).
- Depends on: T4.

## Integration and end-to-end validation

- T5 proves scenarios 1–3 through the installed command.

## Risks and rollback

- A wrong import under-reports spend and re-authorises a budget. T1's
  to-the-cent check against the TSV figure is the guard; rollback restores the
  TSV read in `cost.py` without touching stored rows.
- The store lives under `runs/`, which every install ignores
  (`template/.agentic/pm_flow/.gitignore`: `*/runs/*`), so the silent import
  creating `runs/pm_flow.db` never shows in the host's `git status` (A4).
- Reader race after T4: an operator `pm-flow status|cost` running between the
  envelope landing on disk and `telemetry_end_attempt` recording its path
  (`driver.zsh:1041-1056`) imports the envelope as a second row. Today the
  TSV row at :1036 closes that window; after T4 it is a few milliseconds
  wide and not deterministically testable. Recorded, not fixed.
- Telemetry off (`telemetry.enabled=0`) or `attempt-start` failing: no live
  row, so the cost survives only through the envelope, absorbed by the next
  `spent_usd` import with role `unknown` and the file name as label. Cost is
  never lost; attribution degrades.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T5 | Post-import totals equal TSV totals to the cent |
| A2 | T2, T3, T5 | `pm-flow cost` and `watch.py` use the store; Codex tokens visible through the command |
| A3 | T1 | Second import adds zero rows |
| A4 | T4, T5 | No write under `runs/`; ceiling still refuses |
| A5 | T3, T4, T5 | Three suites exit 0 |
