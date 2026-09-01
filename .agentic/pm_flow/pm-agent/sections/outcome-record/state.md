# outcome-record section PM state

## Current task

- T3 — emit a `gen_ai.evaluation.result` span event per decision.

## Completed tasks and evidence

- **T1 (A1) — accepted, cycle 001.** Every parsed decision is written as an
  `outcomes` row at its parse site, joined to the attempt and run that produced
  it.
  - `zsh tests/outcome_record_test.sh` — exit 0. Its raw
    `SELECT ... FROM outcomes o JOIN attempts a ON a.id = o.attempt_id JOIN runs r ON r.id = o.run_id AND r.id = a.run_id`
    returned exactly five rows, one per decision the stubbed ticks produced:
    `obstruction_class|NONE|verdict|pm|tick`,
    `portfolio_verdict|ON_TRACK|verdict|cpo|tick`,
    `review_verdict|GO_WITH_CHANGES|verdict|pm|tick`,
    `scope_decision|ASSIGN|verdict|pm|tick`,
    `scope_decision|UNPARSED|verdict|pm|tick`. A second assertion holds
    `COUNT(*) FROM outcomes WHERE source = 'verdict' AND attempt_id IS NULL` at 0.
  - `zsh template/.agentic/pm_flow/tests/run.zsh` — exit 0, "all suites passed"
    (35 + 41 + 32 + 59 + 74 assertions), so the `telemetry_record_outcome`
    signature change and the edits inside `record_cycle_decision` did not
    disturb scheduling or control flow.
  - `section_status` is untouched: the derived SELECT still returns
    `section_status|abandoned|derived` and `section_status|complete|derived`,
    and both callers (`driver.zsh:2152`, `:2200`) moved to the new signature in
    the same edit.
  - Negative check (`sections/outcome-record/mutation_check.zsh`): on a throwaway
    copy of the tree with `args+=(--attempt "$TELEMETRY_LAST_ATTEMPT_ID")`
    removed, the suite fails — the join returns the empty set. The assertion is
    load-bearing, not incidentally green.
  - Swallow-and-exit-0 probe (`sections/outcome-record/probe_swallow.zsh`): with
    `demo/runs` at mode 500 and the store at 444, the review tick still printed
    `result=review 001 -> GO_WITH_CHANGES (developer said DELIVERED; ...)`,
    wrote `decision.txt=GO_WITH_CHANGES` and `obstruction.txt=NONE`, and exited
    0. The only extra output is the pre-existing `cost.py` warning from
    `driver.zsh:464`, which an unreadable store already produced.

- **T2 (A3, A4) — accepted, cycle 002.** Every dispatching command now closes
  its own `runs` row on every exit path, including the ones where `fail` exits
  the process. Both candidate leaks were real and both are fixed.
  - `zsh tests/outcome_record_test.sh` — exit 0 (`SUITE_EXIT=0`). Its raw
    `SELECT command || '|' || status FROM runs WHERE id > 7 ORDER BY id`
    returned `run|ok` then `tick|error`, and
    `SELECT COUNT(*) FROM runs WHERE id > 7 AND ended_at IS NULL` returned `0`.
    A third assertion holds `COUNT(*) FROM runs WHERE ended_at IS NULL` at 0
    over the whole store, which covers the on-demand `portfolio-review` the
    suite runs earlier.
  - `zsh template/.agentic/pm_flow/tests/run.zsh` — exit 0, "all suites
    passed", `fail=0` in all five suites (35 + 41 + 32 + 59 + 74). An `EXIT`
    trap at driver source scope is the change most able to break dispatch
    output or an exit status, and it did not.
  - Negative check (`sections/outcome-record/review_002/mutation_check.zsh`),
    two mutations on throwaway copies:
    - delete `trap 'telemetry_end_run error' EXIT` → the budget-aborted tick
      reads `tick|running`, suite exits 1. The trap is what closes the abort
      path; nothing else was doing it. This is also the direct observation of
      candidate leak (b), which the developer's own `LIMIT 1` query had not
      isolated.
    - drop `--only-open` → the completed run reads `run|error`, suite exits 1.
      The store-side guard is the only thing stopping the trap from
      overwriting a terminal status, which is exactly A3's rejection
      condition.
  - Swallow-and-exit-0 (`review_002/probe_trap_output2.zsh`): with `demo/runs`
    at mode 500 and the store at 444, the 17-line dispatch block from `run` and
    `tick` is byte-identical with the trap installed and with it deleted, and
    both exit 0. The fail-aborted tick's combined streams are likewise
    identical: `section=closure`, `action=develop`,
    `ERROR: project budget exhausted`, exit 1. The trap adds no line and
    changes no exit code.
  - `section_status` and the T1 five-row join are unchanged, re-observed in the
    same run.

## Active decisions

- **The trap's status is `error`, and that is deliberate.** A process leaving
  through `fail` under `set -euo pipefail` did not finish its work, so `error`
  is the honest value; `ok` would launder every abort into a success. The
  developer chose this and could not write it here — `state.md` is not in a
  developer's writable paths, which is an assignment-authoring slip, not a
  deficiency in the work.

- **The trap is the owning process, not a sweeper.** It runs in the process
  that opened the row, closes only `TELEMETRY_RUN_KEY`, and `--only-open` adds
  `AND ended_at IS NULL` inside the UPDATE rather than as a shell-side read
  then write, so a concurrent close cannot race past it. No pass ever touches
  another process's row. The brief's rejected sweeper stays rejected.

- **The explicit closes in the on-demand commands are load-bearing, not
  belt-and-braces.** Because the trap's status is a fixed `error`, a successful
  `portfolio-review` that relied on the trap alone would be recorded as a
  failure. Observed (`review_002/probe_run_statuses.zsh`): the full runs table
  after the suite is seven `tick|ok|closed`, one `run|ok|closed`, one
  `tick|error|closed` — the on-demand review among the `ok` rows. Do not
  "simplify" the three `telemetry_end_run ok` calls away in a later task.

- **`runs.command` mislabels the on-demand commands as `tick`.**
  `PM_FLOW_COMMAND` is set nowhere in the tree, so
  `telemetry_begin_run "${PM_FLOW_COMMAND:-tick}"` records
  `portfolio-review`, `section-analysis` and `proposals` as `tick`. This is
  pre-existing — the lazy open at `:810` already did it — and T2 neither caused
  nor widened it. It matters to `compare.py:492`, which sums `wall_clock` over
  `runs`, and to anything that groups by `command`. Out of T2's scope; raise it
  in T4 or as its own task rather than folding it into T3.

- **`tests/run.zsh` in the brief means the engine runner at
  `template/.agentic/pm_flow/tests/run.zsh`.** There is no `tests/run.zsh` at
  the repository root (`ls /Users/salah/code/personal/pm-flow/tests` lists only
  `*_test.sh` suites plus `fixtures/`). The engine runner enumerates five
  hardcoded stubbed suites in its own directory (`run.zsh:28`) and no
  repository-root suite is wired into it; the brief's owned paths do not
  include it either. So `tests/outcome_record_test.sh` is a standalone suite
  run directly, like every other section's, and A5's "`tests/run.zsh` runs to
  completion" is a regression guard on the engine runner, not a wiring
  requirement. The engine runner is not an owned path and is not to be edited.

- **The attempt handle must be stashed by the dispatcher.**
  `telemetry_end_attempt` clears `TELEMETRY_ATTEMPT_ID` and
  `TELEMETRY_ATTEMPT_SPAN` (`driver.zsh:843-844`) inside `dispatch_role`, which
  returns before `record_cycle_decision` runs at all three call sites
  (`:1376`, `:1505`, `:3433`). Without a stashed copy, an outcome row cannot
  carry `attempt_id` and A1's join is impossible.

- **`gen_ai.` literals stay in `semconv.py`.**
  `tests/otel_semconv_test.sh:820-836` greps `template/` and `src/` for
  `gen_ai\.` and fails on any hit outside `src/pm_flow/semconv.py` (one
  comment-only `catalog.py` exemption). The evaluation event name and its
  attribute keys must therefore be resolved inside `telemetry.py` from
  `semconv.py`; `driver.zsh` may never spell them.

- **New metrics cannot disturb `pm-flow compare`.** Both outcome queries in
  `compare.py` (`:468`, `:488`) filter `metric = 'section_status'` explicitly,
  so `review_verdict`, `scope_decision`, `portfolio_verdict` and
  `obstruction_class` rows are inert to `cycles_to_done` and `abandoned`.
  `compare.py:492` computes `wall_clock` as `SUM(ended_at - started_at)` over
  `runs`, which is why A3 matters beyond tidiness.

- **The stashed handle is cleared at the start of every dispatch.**
  `telemetry_begin_attempt` now zeroes `TELEMETRY_LAST_ATTEMPT_ID` and
  `TELEMETRY_LAST_ATTEMPT_SPAN` (`driver.zsh:797-800`), and
  `telemetry_record_outcome` returns without writing a verdict row when the
  handle is empty. So a decision parsed after a dispatch whose attempt never
  opened is dropped rather than attributed to the previous dispatch. T3 depends
  on the same pair for its span.

- **`COMPLETE` as a scope decision is not yet observed as an outcome row.** It
  travels the same `record_cycle_decision` line as `ASSIGN`, but the suite
  primes `cycles/002/decision.txt` directly to reach the complete path, so no
  `scope_decision|COMPLETE` row exists in the evidence. Cover it in T4's real
  run rather than adding a case that re-proves the same line.

- **No store schema change is needed.** `outcomes` (`store.py:369-382`)
  already carries `run_id`, `project_id`, `task_id`, `attempt_id`, `metric`,
  `value_num`, `value_text`, `source`, and `telemetry.py`'s `outcome` parser
  (`:839-844`) already exposes every one of them.

- **`set -euo pipefail` still routes aborts around every straight-line close,
  and the trap is the only thing covering them.** `pm_flow.sh:2` sets
  `-euo pipefail` and `fail()` (`:84`) exits, so `assert_within_budget`
  (`driver.zsh:2851`, `:2929`), `resolve_section_dir` (`:2811`, `:2896`) and
  the unguarded `perform_action | sed` at `:2931` all terminate the process
  before `telemetry_end_run` at `:2866`/`:2958`. That was candidate leak (b),
  now observed by mutation and covered. Any future early exit added to
  `cmd_tick` or `cmd_run` is covered by construction; do not add a second
  straight-line close for it.

## Blockers

- None observed. Note: `sqlite3` and `python3` probes against the real
  `runs/pm_flow.db` are still refused by this session's sandbox, so the brief's
  "126 of 132 rows at `running`" figure remains carried forward unverified.
  It is background motivation, not acceptance evidence, and the brief puts
  backfilling those historical rows out of scope. A3 is proved by the two rows
  a T2 case creates inside its own store.

## Next eligible task

- T3 — emit a `gen_ai.evaluation.result` span event per decision, reusing
  T1's stashed `TELEMETRY_LAST_ATTEMPT_SPAN`. Its unresolved question is the
  pin: verify against the `semantic-conventions` repository whether v1.37.0
  already defines the evaluation event, and move `REVISION` to v1.38.0 only if
  it does not. T2 left `telemetry.py` with one new flag and no schema change,
  so nothing in T3 is blocked by it.
