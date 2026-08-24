# store-ledger section PM state

## Current task

- T5 — end-to-end through the installed command (next to assign; A1–A5).
  Its validation carries the two checks the T2 suite cannot see (mixed
  `projects.key` sum, `response_path` byte equality from the real driver).

## Completed tasks and evidence

- T4 — driver stops writing the ledger (cycle 005, GO; A4, A5). Review
  reran everything against the worktree (probes in `cycles/005/`):
  `zsh tests/store_ledger_test.sh` → `store ledger tests passed`, exit 0,
  now asserting: pre-dispatch store shows 7 `ATTEMPT` lines and total
  `12.1650`; one stub `section-analysis` dispatch in `COMMAND_WORK` leaves
  `runs/` holding `pm_flow.db` and no `cost_ledger.tsv`, `git status
  --porcelain` clean of `runs/`, exactly one new `ATTEMPT` line labelled
  `analysis dispatch-check` with cost field `0.5000`, `cost.py total` →
  `12.6650`; with `budget.max_usd 12.66` and no TSV on disk the next
  dispatch prints `project budget exhausted` and the `ATTEMPT` count is
  unchanged; the legacy `total <dir> <tsv>` arity exits 2;
  `grep -c cost_ledger_file driver.zsh` → `0`; `grep -rl cost_ledger
  template` → `cost.py` only. `record_dispatch_cost` is a documented no-op
  (`:`) keeping its name and call (`driver.zsh:1020`, four args);
  `spent_usd` runs `cost.py total "$PROJECT_DIR" "${1:-}"`;
  `dispatch_count` counts `^ATTEMPT` of `cost.py report`; `cost_ledger_file`
  and `totals()` deleted, `ledger_rows` (`cost.py:84`) and the importer's
  TSV read (`:184`) kept. Driver diff hunks: `-439,5 -446,13 -463,3 -467
  -834,3 -838,4`, all inside the authorized `:436-472` / `:834-843`.
  Fixtures: `transitions.zsh:195,316-317` read field 7 of `ATTEMPT` lines
  (`0.5000`/`0.2500`); `governance.zsh` and `on_demand.zsh` each gained one
  `seed_attempt` helper (telemetry run-start/attempt-start/attempt-end);
  governance seeds keys `y1`/`y2`, on_demand seeds `y` after the D2
  baseline. README: only the `:168` ledger paragraph rewritten. Engine
  suites `all suites passed` (35/41/32/58/74) with all nine named
  assertions; `tests/pm_flow_test.sh` 10 `PASS:`; `packaged_layout_test.sh`
  13 `PASS:` (the `cost reports the same spend after migration` check is a
  silent-on-success `assert_equals` at `:1083`, not its own `PASS:` line).
  Mutation (`cycles/005/mutation_check.zsh`, reversible, driver restored
  byte-identical): reintroducing a TSV write in `record_dispatch_cost`
  fails the suite with `FAIL: dispatch wrote cost_ledger.tsv`.

- T3 — `pm-flow cost` reads the store (cycle 003, GO; A2 `pm-flow cost`
  clause, A5 regression). Diff: `git diff --stat` lists exactly `cost.py`
  (-7), `driver.zsh` (+1/-1), `tests/store_ledger_test.sh` (+46/-1);
  `git status --porcelain` shows nothing else; `git diff -U0 -- driver.zsh`
  is one hunk at :471 inside `cmd_cost`. `cost.py` loses only the
  `report <dir> <tsv>` branch and its usage line; `totals()`, the legacy
  `total <dir> <tsv> [section]` arity and `ledger_rows` are untouched.
  `zsh tests/store_ledger_test.sh` → `store ledger tests passed`, exit 0: the
  suite copies the template to `<work>/.agentic/pm_flow`, places the fixture
  at `<flow>/legacy-project` with `.project-key`, and runs
  `zsh -f <flow>/pm_flow.sh cost` from the work dir (no `PM_FLOW_*` set);
  the output equals `python3 cost.py report <same dir>`, contains
  `TOTAL\t12.1650` and
  `ATTEMPT\t…\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5`, and is
  unchanged after `rm` of the TSV; `cost.py report <dir> <tsv>` exits 2; the
  `cmd_cost` body contains `report "$PROJECT_DIR"` and no `cost_ledger_file`.
  Real output captured (`cycles/003/review/review_probe.zsh`): `alpha 3.7900`,
  `beta 8.3750`, `TOTAL 12.1650`, seven `ATTEMPT` lines, the Codex row last.
  Mutations on a temp copy, each failing the suite: `cmd_cost` passing the
  ledger path (exit 2, `cost.py` usage), appending an extra line, hiding
  `ATTEMPT` rows, referencing `cost_ledger_file`, restoring the legacy
  `report` branch (`expected '2', got '0'`), `report` figures from the TSV
  (`report alpha total differs`). Regressions: `tests/pm_flow_test.sh` 10
  `PASS:`, exit 0; `tests/run.zsh` `all suites passed` (35/38/32/58/74) with
  all `F7` lines, `C2 $1.00 of ledger spend passes a $0.75 threshold`, `D1
  the ledger carries the analysis`; `tests/packaged_layout_test.sh` 13
  `PASS:`, exit 0, including `cost reports the same spend after migration`
  (the `installed cost` before/after comparison runs through this
  `cmd_cost`).

- T2 — readers on the store (cycle 002, GO, merged `cb84e75`; A1, A2 at the
  `cost.py` level). Only `cost.py`, `watch.py`, `tests/store_ledger_test.sh`
  changed; `driver.zsh`, `telemetry.py`, `store.py` diff empty. `zsh
  tests/store_ledger_test.sh` → `store ledger tests passed`, exit 0: new-arity
  `total <dir>` / `<dir> alpha` / `<dir> beta` equal the legacy `<dir> <tsv>`
  figures and `12.1250` / `3.7500` / `8.3750`; deleting then inflating the
  TSV changes nothing; a `telemetry.py`-written Codex row reports as
  `ATTEMPT\t…\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5` and
  `import` after it prints `imported=0`; watch shows the store spend and
  `13937in/5out`, creates no `runs/` for an empty project;
  `grep -c cost_ledger watch.py` → `0`. Mutations (temp copies,
  `cycles/002/review/review_probe.zsh`): reader on TSV (`107.4020`), legacy
  arity importing (`imported=0`), `status` filter (`0.0000`), `total`
  printing `imported=`, tokens dropped from `report` or watch, section not
  via `task_id`, watch opening writable — each fails the suite. Direct
  probes: legacy arity on a governance-shaped TSV (two rows keyed `y`) prints
  `1.0000` and creates no store; new arity prints one line; a store with rows
  under two `projects.key`s sums to `1.2900` (no `project_id` filter).
  Regressions: `tests/pm_flow_test.sh` 10 `PASS:`, exit 0; `tests/run.zsh`
  `all suites passed` (35/38/32/56/74) including `C2 $1.00 of ledger spend
  passes a $0.75 threshold` and all F7 lines.

- T1 — idempotent legacy import (cycle 001, GO, merged `558837f`; A1, A3).
  `zsh tests/store_ledger_test.sh`: `imported=6` on a fixture of 5 TSV rows
  (one blank cost) + 1 envelope-only response; store `SUM(cost_usd)` =
  `12.1250` equals the pre-import `cost.py total` output; blank-cost row stays
  NULL despite its envelope carrying `7.777`; second run prints `imported=0`,
  row count unchanged, one attempt per `response_path`. Mutation probes
  (`cycles/001/review_probe.zsh`): back-filling the blank cost, dropping the
  dedupe, removing the transaction each fail the suite. Empty project →
  `imported=0`, exit 0. Regressions: `tests/pm_flow_test.sh`,
  `template/.agentic/pm_flow/tests/run.zsh`, `tests/packaged_layout_test.sh`
  all pass.

## Active decisions

- `driver.zsh` is owned for its five ledger functions only; the call to
  `record_dispatch_cost` at `driver.zsh:1036` is outside them, so T4 keeps the
  function as a no-op rather than deleting it.
- Import keys on `response_path`; the TSV, `telemetry.py attempt-end` and
  `cost.response_files()` all carry the same absolute string, so no
  normalisation.
- Section identity is `attempts.task_id → tasks.key` (no `section_key`
  column). Readers never filter on `project_id`: the importer keys the project
  row on `basename(project_dir)` and the driver on `PROJECT_KEY`, and a
  mismatch filter would read zero.
- Parity: a TSV row is authoritative for its `response_path` even with a blank
  cost; only envelopes absent from the TSV are parsed with `cost_of`.
- Readers sum `COALESCE(cost_usd, 0)` regardless of `status`, because failed
  dispatches are paid for and imported rows carry `status='imported'`.
- The interim T2→T4 dual-arity rule is retired: T4 (cycle 005) deleted
  `totals()` and the legacy `total <dir> <tsv>` arity; every reader —
  `pm-flow cost`, `spent_usd`, `dispatch_count`, `watch.py` — now answers
  from `attempts` after the silent import.
- Nothing in the driver may import before `telemetry_end_attempt` at
  `driver.zsh:1056` records the `response_path`: the envelope is already on
  disk and an import in that window inserts it a second time.
- `watch.py` is read-only against the store (`mode=ro`, no import, no file
  creation).

## Open risks carried to T5

- The T2 suite cannot see a `project_id` filter: its importer key and its
  telemetry key are both `legacy-project`. The code has none (probe: two keys
  sum to `1.2900`); T5's validation requires a mixed-key check.
- T1 keys the import on the raw `response_path` string. `Path.glob` normalises
  `//` and the TSV does not, so a non-canonical `PROJECT_DIR` (only reachable
  through a `PM_FLOW_FLOW_DIR` override; the default is `pwd -P`) imports the
  same envelope twice. T5 checks the real driver's strings match.
- `watch.py` returns an empty view on any `sqlite3.Error` (old schema,
  read-only `runs/` with no `-shm`), so it can show `$0.00` for a project that
  has spent. Display only; the budget check never reads watch.
- An operator `pm-flow status|cost` between the envelope landing and
  `attempt-end` (`driver.zsh:1041-1056`) double-counts that dispatch; the
  TSV row that used to close the window is gone as of T4. A few
  milliseconds wide, not deterministically testable. Recorded, not fixed.
- Telemetry off or `attempt-start` failing leaves only the envelope: cost
  kept, role `unknown`, label = file name.

## Blockers

- None. The cycle 003/004 ownership conflict (engine fixtures read or seed
  the TSV outside Owned paths) was resolved by portfolio review 004
  (`ec8e4dc`); the boundary extension is recorded in `brief.md`.

## Next eligible task

- T5 — end-to-end through the installed command, the last workplan task. Its
  validation carries the two checks the T2 suite cannot see (mixed
  `projects.key` sum, `response_path` byte equality from the real driver).
