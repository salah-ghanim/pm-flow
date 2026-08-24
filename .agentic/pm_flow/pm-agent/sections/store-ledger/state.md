# store-ledger section PM state

## Current task

- None assigned. T2 accepted in cycle 002; T3 is next once its boundary
  conflict (below) is resolved.

## Completed tasks and evidence

- T2 — readers on the store (cycle 002, GO; A1, A2). Only `cost.py`,
  `watch.py`, `tests/store_ledger_test.sh` changed; `driver.zsh`,
  `telemetry.py`, `store.py` diff empty. `zsh tests/store_ledger_test.sh` →
  `store ledger tests passed`, exit 0: new-arity `total <dir>` / `<dir> alpha`
  / `<dir> beta` equal the legacy `<dir> <tsv>` figures and `12.1250` /
  `3.7500` / `8.3750`; deleting then inflating the TSV changes nothing; a
  `telemetry.py`-written Codex row reports as
  `ATTEMPT\t…\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5` and
  `import` after it prints `imported=0`; watch shows the store spend and
  `13937in/5out`, creates no `runs/` for an empty project;
  `grep -c cost_ledger watch.py` → `0`. Mutations (temp copies,
  `cycles/002/review/review_probe.zsh`): reader on TSV (`107.4020`), legacy
  arity importing (`imported=0`), `status` filter (`0.0000`), `total` printing
  `imported=`, tokens dropped from `report` or watch, section not via
  `task_id`, watch opening writable — each fails the suite. Direct probes:
  legacy arity on a governance-shaped TSV (two rows keyed `y`) prints `1.0000`
  and creates no store; new arity prints one line; a store with rows under two
  `projects.key`s sums to `1.2900` (no `project_id` filter). Regressions:
  `tests/pm_flow_test.sh` 10 `PASS:`, exit 0; `tests/run.zsh` `all suites
  passed` (35/38/32/56/74) including `C2 $1.00 of ledger spend passes a $0.75
  threshold` and all F7 lines.

- T1 — idempotent legacy import (cycle 001, GO, merged as `558837f`). `zsh
  tests/store_ledger_test.sh` in the cycle worktree: `imported=6` on a fixture
  of 5 TSV rows (one blank cost) + 1 envelope-only response; store
  `SUM(cost_usd)` = `12.1250` equals the pre-import `cost.py total` output;
  blank-cost row stays NULL despite its envelope carrying `7.777`; second run
  prints `imported=0`, row count unchanged, one attempt per `response_path`.
  Mutation probes (temp copies, `cycles/001/review_probe.zsh`): back-filling
  the blank cost from the envelope, dropping the dedupe, and removing the
  transaction each fail the suite. Empty project → `imported=0`, exit 0.
  Regressions: `tests/pm_flow_test.sh`, `template/.agentic/pm_flow/tests/run.zsh`
  and `tests/packaged_layout_test.sh` all pass.

## Active decisions

- `driver.zsh` is owned for its five ledger functions only.
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
- Interim rule T2→T3 (cycle 002): the new arity (`total <dir> [section]`,
  `report <dir>`) imports silently then reads `attempts`; the legacy `.tsv`
  arity keeps today's `totals()` with no import side effect until T3 deletes
  it. Reason: `governance.zsh:198-199` seeds two TSV rows sharing the
  response key `y`; importing under the legacy arity would dedupe `$1.00` to
  `$0.50` and break the spend-trigger test while the driver is still on the
  TSV.
- `watch.py` is read-only against the store (`mode=ro`, no import, no file
  creation); a legacy project may under-report in the watch view for the one
  cycle before T3. Accepted.

## Open risks carried to T3/T4

- The T2 suite cannot see a `project_id` filter: its importer key and its
  telemetry key are both `legacy-project`. The code has none (probe: two keys
  sum to `1.2900`); T4's validation now requires a mixed-key check.
- T1 keys the import on the raw `response_path` string. `Path.glob` normalises
  `//` and the TSV does not, so a non-canonical `PROJECT_DIR` (only reachable
  through a `PM_FLOW_FLOW_DIR` override; the default is `pwd -P`) imports the
  same envelope twice. T4 checks the real driver's strings match.
- `watch.py` returns an empty view on any `sqlite3.Error` (old schema,
  read-only `runs/` with no `-shm`), so it can show `$0.00` for a project that
  has spent. Display only; the budget check never reads watch.
- New-arity `total`/`report` on the governance-shaped fixture (two TSV rows
  sharing `y`) reads `0.5000` where the legacy arity reads `1.0000`. Expected
  under the interim rule; T3 must resolve that fixture.

## Blockers

- None open. Recorded for T3 (not yet external, not yet assigned): three
  engine test files outside Owned paths read or seed `runs/cost_ledger.tsv`
  (`transitions.zsh:195,311`, `on_demand.zsh:158-160,240`,
  `governance.zsh:198-199`). A5 and the "TSV is still written" rejection
  cannot both hold without editing them; this goes in the handoff as a
  boundary conflict before T3 is assigned.

## Next eligible task

- T3, blocked on the boundary conflict above: the next scope must either get
  `transitions.zsh`, `on_demand.zsh` and `governance.zsh` added to Owned paths
  (handoff) or find a T3 shape that leaves those fixtures reading true.
