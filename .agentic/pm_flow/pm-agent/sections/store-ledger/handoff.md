## Outcome

- Reopened by a portfolio review: Owned paths now include
  `template/.agentic/pm_flow/tests/transitions.zsh`, `on_demand.zsh`,
  `governance.zsh` and `template/.agentic/pm_flow/README.md`. No live
  section owned them, and T4 cannot hold A5 green while their ledger lines
  stand. Acceptance is unchanged. T1-T3 are on `main`: `cost.py
  import|total|report` and `pm-flow cost` read the store.

## Decisions

- The product officer decided this in portfolio review 004, against the
  mission and the evidence it probed. Edits to the four added files are
  limited to what the ledger's removal forces: an assertion that read the
  TSV reads the store, a seed that wrote the TSV seeds the store, the README
  describes the store.

## Interfaces

- Unchanged: `cost.py total <dir> [section]`, `report <dir>`,
  `import <dir>`; `pm-flow cost`. `driver.zsh` `record_dispatch_cost`,
  `spent_usd` and `dispatch_count` still go through `runs/cost_ledger.tsv`
  until T4.

## Risks

- `governance.zsh:198-199` seeds two TSV rows sharing response key `y`; a
  store-seeded fixture must keep C2 measuring $1.00 against a $0.75
  threshold with two distinct attempts.
- Once the TSV row no longer closes the window between the envelope landing
  and `attempt-end`, `status|cost` can double-count one dispatch in flight.

## What is unproven

- A4: a dispatch appends nothing under `runs/`, and a project at `max_usd`
  is refused its next dispatch with the store as the source.
- A5 after T4: `zsh template/.agentic/pm_flow/tests/run.zsh` exits 0 with
  the fixtures reading and seeding the store.
- A1 on the live project: `pm-flow cost` after import equals the TSV report
  to the cent on `pm-agent`, not only on the test fixture.
- Non-zero Codex tokens on a live attempt row.

## Next action

- Scope cycle 005: re-run `cycles/004/scope_probe.zsh`, confirm the four
  paths are listed in `owned_paths.txt`, assign T4.
