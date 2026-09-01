# outcome-record section PM state

## Current task

- T2 — close every run on every exit path, and find the leak that leaves 126 of
  132 `runs` rows at `running` with a NULL `ended_at`.

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

## Active decisions

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

## Blockers

- None observed.

## Next eligible task

- T2 — close every run on every exit path, and fix the leak. Its two candidate
  causes are named in the workplan and must be confirmed by observation before
  either is fixed.
