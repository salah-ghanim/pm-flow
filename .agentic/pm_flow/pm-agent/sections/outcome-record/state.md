# outcome-record section PM state

## Current task

- T4 — prove all four scenarios end to end against a real backend.

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
    and both callers (`driver.zsh:2159`, `:2207`) moved to the new signature in
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

- **T3 (A2 store/file-export half, A5) — accepted, cycle 003.** Every verdict
  outcome now also writes a `gen_ai.evaluation.result` `span_events` row on the
  attempt span that produced the response, and it survives to the exported OTLP
  JSON. Changed files: `src/pm_flow/semconv.py`,
  `template/.agentic/pm_flow/telemetry.py`, `tests/outcome_record_test.sh`,
  `tests/otel_semconv_test.sh` (one sed literal). `driver.zsh` untouched.
  - `zsh tests/outcome_record_test.sh` — exit 0, run by the PM against the
    developer worktree. Its raw
    `SELECT a.id || '|' || a.span_id || '|' || se.name || '|' || se.attributes FROM span_events se JOIN attempts a ON a.span_id = se.span_id WHERE se.name = 'gen_ai.evaluation.result' ORDER BY a.id, se.rowid`
    returned exactly five rows on four distinct attempt spans — attempt 1
    `scope_decision/ASSIGN`, attempt 3 `review_verdict/GO_WITH_CHANGES` and
    `obstruction_class/NONE`, attempt 4 `scope_decision/UNPARSED`, attempt 5
    `portfolio_verdict/ON_TRACK`. The attribute keys are literally
    `gen_ai.evaluation.name` and `gen_ai.evaluation.score.label`.
  - The same five appear in the exported OTLP JSON as `events` entries under
    those `spanId`s, with `stringValue` attributes. The suite compares
    `Counter` over `(attempt_id, metric, value_text)` on three sides — outcomes
    rows with `source = 'verdict'`, `span_events`, exported spans — and requires
    equality, so a dropped or duplicated event fails. It also raises if any
    event lands on a span that is not an attempt, or carries any attribute key
    beyond the two.
  - `zsh tests/otel_semconv_test.sh` — exit 0, with
    `PASS: changing only the pin changes the receiver provider attribute` and
    `PASS: standard GenAI literals are centralised in semconv.py`. In the PM's
    run Docker was up, so `PASS: a stock backend re-serves the invoke_agent ->
    chat tree` (A6) also ran, which the developer's run had skipped.
  - `zsh template/.agentic/pm_flow/tests/run.zsh` — exit 0, "all suites passed",
    35 + 41 + 32 + 59 + 74 with `fail=0`.
  - T1 and T2 assertions re-observed unchanged in the same run: the five-row
    join, `section_status|abandoned|derived` and `section_status|complete|derived`,
    `run|ok` then `tick|error`, `ended_at IS NULL` at 0, both unwritable-store
    dispatches at exit 0.
  - Negative checks (`sections/outcome-record/pm_mutation_probe.zsh` and
    `pm_export_probe.zsh`), four mutations on throwaway copies, with an
    unmutated control at exit 0 first:
    - M1, verdict attribute set to a constant `"GO"` instead of `args.text` →
      exit 1, `stored events do not match verdict rows`. The attribute carrying
      the verdict is load-bearing, not just the event's presence.
    - M2, span lookup replaced by `ORDER BY id LIMIT 1` so all five events land
      on attempt 1 → exit 1. Span *association* is asserted, not merely that the
      event sits on some attempt span.
    - M3, `REVISION` swapped to `v1.36.0` → `evaluation_event()` returns `None`
      rather than raising, which is the degradation A5 needs.
    - M4, `trace_export.py` mutated to drop every span event while the store
      stays correct → exit 1 at `exported events do not match verdict rows`.
      Needed because M1/M2 trip the store-side comparison first; M4 is what
      proves the *exported*-JSON half of A2 is independently load-bearing.
  - Independent `grep -rn 'gen_ai\.'` over `template/` and `src/`: hits only
    `semconv.py` and the pre-existing comment at `catalog.py:254`. No literal in
    `driver.zsh`, `telemetry.py` or the suite — the suite reads the name from
    `semconv.py` at runtime.

## Active decisions

- **The registry check behind the pin move is reported but not independently
  verified, and T4 must close that.** Outbound network is refused from the PM's
  shell (`curl`) and from its fetch tool, so the developer's citations are the
  only direct reading: `v1.37.0/model/gen-ai/events.yaml` defines only
  `gen_ai.client.inference.operation.details`; the `v1.38.0` release note says
  "Introducing `Evaluation Event` in GenAI Semantic Conventions"; the `v1.38.0`
  registry defines `gen_ai.evaluation.name` and `gen_ai.evaluation.score.label`.
  That matches what is known of v1.38.0 independently, and the pin move is
  self-consistent in-tree (the v1.36.0 comparison arm still swaps and still
  observes the provider rename). Two things stay unverified from here: that
  `v1.38.0` really is the first revision defining the event, and that
  `_PROVIDER_ATTRIBUTES["v1.38.0"] = "gen_ai.provider.name"` matches the
  v1.38.0 registry rather than being carried over from v1.37.0. Re-read both
  from a networked host during T4 before this pin ships.

- **The event is keyed on `source = 'verdict'`, not on a metric allowlist.**
  `cmd_outcome` emits for any outcome whose source is `verdict` and whose
  `--attempt` resolves to a span. `section_status` is `derived`, so it is
  excluded structurally rather than by name, and a future verdict metric gets an
  event without a second edit. The suite's three-way `Counter` equality is what
  holds this honest: a `derived` row that started emitting would break it.

- **The evaluation event degrades in four ways, all silent.** `cmd_outcome`
  writes and commits the outcomes row first, then returns `0` without an event
  when `SEMCONV` is `None` (`getattr(SEMCONV, "evaluation_event", None)`), when
  the revision defines no names, when `--attempt` is absent or `--source` is not
  `verdict`, or when the attempt has no `span_id`. Anything that still raises is
  caught by `telemetry.py:893-897`, which prints to stderr and exits 0. So no
  path exists where the row is lost because the event failed.

- **`outcome_record_test.sh` puts `semconv.py` beside the engine on purpose, and
  that is the packaged layout.** `_load_semconv`'s first candidate is
  `<engine>/../semconv.py` (`telemetry.py:55`); the second is
  `../../../src/pm_flow/semconv.py`, the checkout. `pyproject.toml:51` maps
  `template/.agentic/pm_flow` to `pm_flow/engine`, so an installed wheel has
  `pm_flow/engine/telemetry.py` next to `pm_flow/semconv.py` — candidate one,
  exactly. The suite's `cp ... "$WORK/.agentic/semconv.py"` reproduces the
  packaged relationship in a temp tree that has no `src/` above it; the dogfood
  editable install resolves through candidate two. Both live paths load
  `SEMCONV`, so the event is reachable in production, not only under test.

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
  `TELEMETRY_ATTEMPT_SPAN` (`driver.zsh:860-861`) inside `dispatch_role`, which
  returns before `record_cycle_decision` runs at all three call sites
  (`:1407`, `:1537`, `:3468`). Without the stash at `:858-859`, an outcome row
  cannot carry `attempt_id` and A1's join is impossible.

- **`gen_ai.` literals stay in `semconv.py`.**
  `tests/otel_semconv_test.sh:819-836` greps `template/` and `src/` for
  `gen_ai\.` and fails on any hit outside `src/pm_flow/semconv.py` (one
  comment-only `catalog.py` exemption). The evaluation event name and its
  attribute keys must therefore be resolved inside `telemetry.py` from
  `semconv.py`; `driver.zsh` may never spell them.

- **The comparison pin runs a real dispatch, so T3's code executes under
  `v1.36.0`.** `otel_semconv_test.sh:805` sed-swaps `REVISION` to `v1.36.0` in
  a second tree, then `drive_dispatch` (`:385`) runs `pm-flow tick`, which
  reaches a scope decision. `telemetry.py` also tolerates `SEMCONV is None`
  (`:73`, guarded at `:628`). Both paths must skip the evaluation event and
  still write the outcomes row; raising would convert an additive record into a
  dispatch failure and break A5.

- **New metrics cannot disturb `pm-flow compare`.** Both outcome queries in
  `compare.py` (`:468`, `:488`) filter `metric = 'section_status'` explicitly,
  so `review_verdict`, `scope_decision`, `portfolio_verdict` and
  `obstruction_class` rows are inert to `cycles_to_done` and `abandoned`.
  `compare.py:492` computes `wall_clock` as `SUM(ended_at - started_at)` over
  `runs`, which is why A3 matters beyond tidiness.

- **The stashed handle is cleared at the start of every dispatch.**
  `telemetry_begin_attempt` now zeroes `TELEMETRY_LAST_ATTEMPT_ID` and
  `TELEMETRY_LAST_ATTEMPT_SPAN` (`driver.zsh:806-807`), and
  `telemetry_record_outcome` (`:865`) returns without writing a verdict row
  when the handle is empty (`:878`). So a decision parsed after a dispatch whose attempt never
  opened is dropped rather than attributed to the previous dispatch. T3 depends
  on the same pair for its span.

- **`COMPLETE` as a scope decision is not yet observed as an outcome row.** It
  travels the same `record_cycle_decision` line as `ASSIGN`, but the suite
  primes `cycles/002/decision.txt` directly to reach the complete path, so no
  `scope_decision|COMPLETE` row exists in the evidence. Cover it in T4's real
  run rather than adding a case that re-proves the same line.

- **No store schema change is needed, for the row or the event.** `outcomes`
  (`store.py:369-382`) already carries `run_id`, `project_id`, `task_id`,
  `attempt_id`, `metric`, `value_num`, `value_text`, `source`, and
  `telemetry.py`'s `outcome` parser (`:843-848`) already exposes every one of
  them. `span_events (span_id, at, name, attributes)` already exists and
  `trace_export.py:142-148` already emits every row in it as an OTLP span
  event, so T3 needs a caller and a name, not an exporter.

- **`cmd_outcome` can resolve the span itself.** It already receives
  `--attempt` (`telemetry.py:756`) and `attempts.span_id` is the `invoke_agent`
  parent span written at `:625`. So the evaluation event needs no new handle
  passed from `driver.zsh` and no second subprocess.

- **`set -euo pipefail` still routes aborts around every straight-line close,
  and the trap is the only thing covering them.** `pm_flow.sh:2` sets
  `-euo pipefail` and `fail()` (`:84`) exits, so `assert_within_budget`
  (`driver.zsh:2851`, `:2929`), `resolve_section_dir` (`:2811`, `:2896`) and
  the unguarded `perform_action | sed` at `:2931` all terminate the process
  before `telemetry_end_run` at `:2866`/`:2958`; the trap is at `:779`. That
  was candidate leak (b), now observed by mutation and covered. Any future early exit added to
  `cmd_tick` or `cmd_run` is covered by construction; do not add a second
  straight-line close for it.

- **The three new `telemetry_begin_run` calls carry no open-run guard.**
  Unlike the lazy open at `driver.zsh:810`, the calls at `:3751`, `:3805` and
  `:3881` lack `[[ -n "$TELEMETRY_RUN_KEY" ]] ||`. All three are top-level
  command handlers, so nothing today can reach them with a run already open; a
  future caller that did would orphan the first row. Recorded in cycle 002's
  review, not worth a change on its own.

- **`--only-open` now makes every run close first-close-wins.** All thirteen
  `telemetry_end_run` sites close once per path, so nothing depends on a later
  close overwriting an earlier one. A future path that closes twice and expects
  the second to win would silently lose it.

## Blockers

- None observed. Note: `sqlite3` and `python3` probes against the real
  `runs/pm_flow.db` are still refused by this session's sandbox, so the brief's
  "126 of 132 rows at `running`" figure remains carried forward unverified.
  It is background motivation, not acceptance evidence, and the brief puts
  backfilling those historical rows out of scope. A3 is proved by the two rows
  a T2 case creates inside its own store.

- Not a blocker, and it outlived T3: outbound network is refused from the PM's
  session in both directions tried — `curl` to `raw.githubusercontent.com` was
  denied at scope time, and the fetch tool was denied at review time. The
  developer's session had it too ("Could not resolve host") and used a browser
  fetch instead. So every claim about the `semantic-conventions` registry in
  this section rests on the developer's reading, quoted in cycle 003's
  `result.md` and carried into Active decisions above. T4 runs against a real
  backend and is the place to re-read the registry from a networked host.

## Next eligible task

- T4 — prove all four scenarios end to end against a real backend. It is now
  the only pending task. Three things fold into it that earlier cycles
  deliberately deferred: the first observation of a `scope_decision|COMPLETE`
  row, which no stubbed case produces; `runs.command` mislabelling the three
  on-demand commands as `tick` (fix at `driver.zsh:3751`, `:3805`, `:3881` or
  record as accepted, since `compare.py:492` groups by it); and the registry
  re-read behind the `v1.38.0` pin. Docker was up during cycle 003's review and
  `otel_semconv_test.sh`'s Jaeger assertion (A6) passed, so the backend T4 needs
  is available on this host.
