# store-ledger section PM state

## Current task

- None assigned; next is T2 (readers on the store).

## Completed tasks and evidence

- T1 — idempotent legacy import (cycle 001, A1 + A3). `zsh
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
- Import keys on `response_path`; the TSV and the store carry the same
  absolute string, so no normalisation.
- Section identity is `attempts.task_id → tasks.key` (no `section_key`
  column); the project row is `projects.key = basename(project_dir)`.
- Parity: a TSV row is authoritative for its `response_path` even with a blank
  cost; only envelopes absent from the TSV are parsed with `cost_of`.
- Imported rows carry `status = "imported"`; readers (T2) must sum `cost_usd`
  regardless of `status`, because failed dispatches are paid for.

## Blockers

- None.

## Next eligible task

- T2 — readers on the store (depends on T1, now done).
