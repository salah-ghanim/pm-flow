# store-ledger section handoff

## Outcome

- T1 on `main` (`558837f`): `cost.py import <project_dir>` absorbs
  `runs/cost_ledger.tsv` rows and response envelopes into `attempts` once,
  keyed on `response_path`; a second run adds zero (A3).
- T2 on `main` (`cb84e75`): `cost.py total <dir> [section]` and `report
  <dir>` import silently, then answer from `attempts` only; `report` lists
  every attempt with its tokens; `watch.py` reads the store read-only and no
  longer knows the TSV. Equal to the TSV figures to the cent, mutation-probed.
- Not yet: `pm-flow cost`, `status`, the budget check and the dispatch counter
  still go through the driver's TSV arity, and every dispatch still appends
  `runs/cost_ledger.tsv`. T3 (assigned, cycle 003) moves `pm-flow cost`.

## Decisions

- Section identity is `attempts.task_id → tasks.key`; readers never filter on
  `project_id` (importer key `basename(project_dir)`, driver `PROJECT_KEY`).
- Parity: a TSV row is authoritative for its `response_path` even with a blank
  cost; only envelopes the TSV never listed are parsed.
- Sums include every status; a failed dispatch is paid for.
- The legacy `total <dir> <tsv>` arity stays, without import, until the driver
  leaves the TSV (T4).

## Interfaces

- `cost.py total <dir> [section]`, `cost.py report <dir>`, `cost.py import
  <dir>` (prints `imported=N`); the ledger-path argument is retired per
  command as its caller moves.
- `report` lines: `<section>\t<usd>`, `TOTAL\t<usd>`, then
  `ATTEMPT\t<utc>\t<section>\t<role>\t<label>\t<cli>\t<usd>\t<in>\t<out>`.

## Risks

- Boundary conflict, decision needed: A4 forbids the TSV write and A5 requires
  `template/.agentic/pm_flow/tests/run.zsh` green, but `transitions.zsh:195,311`,
  `on_demand.zsh:158-160` and `governance.zsh:198-199` read or seed
  `runs/cost_ledger.tsv`. Five lines must change; the files are outside Owned
  paths and no live section owns `template/.agentic/pm_flow/tests/`
  (`green-suite` and `worktree-isolation` owned `tests/**`; both done).
  Unblock: add the three files to this brief's Owned paths. Without that the
  section blocks after T3.
- After the TSV write goes, an operator `status`/`cost` between the envelope
  landing and `attempt-end` (`driver.zsh:1041-1056`) can import that envelope
  a second time; today the TSV row at `:1036` closes the window.
- With telemetry off, a dispatch's cost survives only through its envelope:
  role `unknown`, label = file name.

## What is unproven

- `pm-flow cost` through the installed command (T3).
- A4: no write under `runs/`, ceiling refused from the store (T4, blocked as
  above).
- A store with mixed `projects.key`s and a non-canonical `PROJECT_DIR` through
  the real driver (T5).

## Next action

- T3: `cmd_cost` → `cost.py report "$PROJECT_DIR"`, legacy `report` arity
  deleted, `pm_flow.sh cost` driven in `tests/store_ledger_test.sh`.
- Then T4 needs the ownership decision above.
