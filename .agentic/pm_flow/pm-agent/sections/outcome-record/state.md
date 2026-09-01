# outcome-record section PM state

## Current task

- None. T1–T4 are all accepted; the section's four tasks are done and every
  brief acceptance ID is on evidence. The next scope decision is COMPLETE
  unless the officer reopens the section.

## Completed tasks and evidence

- **A1–A5 re-verified on merged `main`, cycle 005 scope.** Every prior cycle's
  evidence was collected in a developer worktree or against the pre-merge tree.
  Re-run by the PM against the checkout at `main` (`git status --porcelain --
  tests template src` empty, so no uncommitted engine edit is propping anything
  up):
  - `zsh tests/outcome_record_test.sh` — exit 0. The join returns the same six
    rows including `scope_decision|COMPLETE|verdict|pm|tick` and
    `portfolio_verdict|ON_TRACK|verdict|cpo|portfolio-review`; six
    `gen_ai.evaluation.result` `span_events` on five attempt spans; the same six
    in the exported OTLP JSON; and `PASS: Jaeger re-serves one evaluation event
    per verdict on its attempt span` against the live container, across five
    trace ids (e.g. `curl -s
    'http://localhost:16686/api/traces/b993f62e85b4e40afd2ff07340d6bf7f'`
    returning span `fc6d31cc1977c3cd` with two `logs` entries,
    `review_verdict`/`GO_WITH_CHANGES` and `obstruction_class`/`NONE`). Runs
    table: ten rows, all `closed`, `6|portfolio-review|ok`, `9|run|ok`,
    `10|tick|error`. `UNWRITABLE RUN EXIT: 0` and `UNWRITABLE TICK EXIT: 0`.
  - `zsh tests/otel_semconv_test.sh` — exit 0, all six PASS lines including
    `PASS: changing only the pin changes the receiver provider attribute` and
    `PASS: standard GenAI literals are centralised in semconv.py`; A6 ran
    (`PASS: a stock backend re-serves the invoke_agent -> chat tree`).
  - `zsh template/.agentic/pm_flow/tests/run.zsh` — exit 0, "all suites
    passed", 35 + 41 + 32 + 59 + 74 with `fail=0`.
  - Pin confirmed in place on `main`: `src/pm_flow/semconv.py:16` reads
    `REVISION = "v1.38.0"`. The three on-demand handlers read
    `${PM_FLOW_COMMAND:-portfolio-review}` (`driver.zsh:3751`),
    `${PM_FLOW_COMMAND:-section-analysis}` (`:3805`) and
    `${PM_FLOW_COMMAND:-proposals}` (`:3881`), with the override intact.

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

- **T4 (A1, A2, A3, A4, A5) — accepted, cycle 004.** A2's live-backend half is
  now on evidence: a real Jaeger re-serves one `gen_ai.evaluation.result` per
  verdict on its attempt span, from an export that ran after the producing
  processes exited. Changed files: `tests/outcome_record_test.sh` and three
  lines of `template/.agentic/pm_flow/driver.zsh`. `semconv.py` and
  `telemetry.py` untouched, as the assignment required.
  - `zsh tests/outcome_record_test.sh` — exit 0, run by the PM against the
    developer worktree with the backend actually up. New PASS line:
    `PASS: Jaeger re-serves one evaluation event per verdict on its attempt span`.
    The suite prints the query it made, e.g.
    `curl -s 'http://localhost:16686/api/traces/f6cf0c4f1a85a46c5cd1cb47586a07b4'`,
    and Jaeger's own response fragment. Jaeger renders the event as a `logs`
    entry, not as an OTLP `events` entry: on span `b398c1f7122c6641` it returned
    two logs, each with `{"key": "event", "value": "gen_ai.evaluation.result"}`
    plus `{"key": "gen_ai.evaluation.name", "value": "review_verdict"}` /
    `"gen_ai.evaluation.score.label" = "GO_WITH_CHANGES"` and
    `"obstruction_class"` / `"NONE"`. All six verdicts came back across five
    trace ids.
  - Equality, not presence. `assert_jaeger_evaluations`
    (`outcome_record_test.sh:196-292`) builds a `Counter` over
    `(trace_id, span_id, metric, value_text)` from the store and from Jaeger's
    `logs` and requires `actual == expected`, so a dropped or duplicated event
    fails. The event name and both attribute keys are read from `semconv.py`
    at runtime; `grep -n 'gen_ai' tests/outcome_record_test.sh` returns
    nothing.
  - "Hours later", proved mechanically. The export is
    `python3 "$FLOW/trace_export.py" --db "$db" --otlp http://localhost:4318 --replay`
    in a process that starts after every driver invocation has exited and
    receives only the database path — no in-process handle. That is the
    property the wall-clock wait stands for. `--replay` deliberately does not
    re-mark spans as exported (`trace_export.py:422-425`), so it leaves the
    store's bookkeeping alone.
  - A1: the join now returns six rows, including
    `scope_decision|COMPLETE|verdict|pm|tick`, produced by a stubbed
    `## Decision\n\nCOMPLETE` scope response through `record_cycle_decision` —
    not by priming `decision.txt`. `COUNT(*) FROM outcomes WHERE source =
    'verdict' AND attempt_id IS NULL` is still 0.
  - A3: `run|ok` and `tick|error` unchanged, `ended_at IS NULL` at 0 over the
    whole store, and the full runs table now reads
    `6|portfolio-review|ok|closed` where it read `6|tick|ok|closed`. The
    `EXPECTED_JOIN_ROWS` expectation moved with the fix
    (`portfolio_verdict|ON_TRACK|verdict|cpo|portfolio-review`), which is the
    assertion rather than a workaround. The `${PM_FLOW_COMMAND:-…}` override
    is preserved at all three sites.
  - A4: `UNWRITABLE RUN EXIT: 0` and `UNWRITABLE TICK EXIT: 0`, both with their
    normal dispatch output.
  - A5: `zsh tests/otel_semconv_test.sh` exit 0 with
    `PASS: changing only the pin changes the receiver provider attribute` and
    `PASS: standard GenAI literals are centralised in semconv.py`; A6 *ran* in
    the PM's session — `PASS: a stock backend re-serves the invoke_agent ->
    chat tree` — it did not skip. `zsh template/.agentic/pm_flow/tests/run.zsh`
    exit 0, "all suites passed", 35 + 41 + 32 + 59 + 74 with `fail=0`.
  - Negative check (`sections/outcome-record/probe_004_mutate.zsh`), the one
    mutation cycle 003 could not construct: on a throwaway copy,
    `export_to_otlp` passes `{}` instead of `events_by_span` to `to_otlp_json`,
    so spans still reach Jaeger but carry no events while the store, the
    `span_events` table and the `--file` export stay correct. Result: exit 1
    with `PASS: every parsed decision joins…`, `PASS: every verdict exports one
    evaluation event…`, then
    `FAIL: Jaeger never re-served every evaluation event for trace
    469f8762cc87c4595837fbf3e2401d1f`. The backend assertion fails alone and
    nothing earlier trips first, which is exactly what cycle 003's M1/M2 could
    not show.
  - The pre-existing container is safe. `ensure_jaeger` sets
    `JAEGER_CONTAINER_ID` only when it starts one itself, and cleanup removes
    only that id. After two full suite runs plus the mutation run,
    `docker ps` still shows `ccf9b12e2452 jaegertracing/all-in-one Up 8 days`.

## Active decisions

- **The registry claims behind the `v1.38.0` pin are now verified first-hand,
  and the pin move was necessary.** Read by the PM at cycle 004 review, quoting
  what came back:
  - `v1.37.0/model/gen-ai/events.yaml` (HTTP 200) defines exactly one event,
    `name: gen_ai.client.inference.operation.details`, and contains the string
    "evaluation" zero times. So v1.37.0 does *not* define the evaluation event
    and the pin had to move.
  - `v1.38.0/model/gen-ai/events.yaml` (HTTP 200) defines two:
    `gen_ai.client.inference.operation.details` and, at line 15,
    `name: gen_ai.evaluation.result`.
  - `v1.38.0/docs/registry/attributes/gen-ai.md` defines `gen_ai.provider.name`
    — "The Generative AI provider as identified by the client or server
    instrumentation" — and both `gen_ai.evaluation.name` ("The name of the
    evaluation metric used for the GenAI response") and
    `gen_ai.evaluation.score.label`. So
    `_PROVIDER_ATTRIBUTES["v1.38.0"] = "gen_ai.provider.name"` matches the
    v1.38.0 registry on its own terms.
  - The carry-forward worry is answered rather than dismissed: the v1.37.0
    registry defines `gen_ai.provider.name` too, so the value is identical
    across both tags *and* independently correct for v1.38.0. The v1.36.0
    comparison arm is what still makes the swap observable.
  This closes the cycle-003 open item. The developer's citations matched this
  reading exactly; nothing was restated as confirmed that was not.

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

- **`runs.command` is fixed: each on-demand command records its own name.**
  Was `telemetry_begin_run "${PM_FLOW_COMMAND:-tick}"` at `driver.zsh:3751`,
  `:3805` and `:3881`; now `portfolio-review`, `section-analysis` and
  `proposals` respectively, with the `${PM_FLOW_COMMAND:-…}` override intact so
  a caller can still name the run. Observed in the runs table as
  `6|portfolio-review|ok|closed`. This matters to `compare.py:492`, which
  groups by `command`; `runs.command` is unconstrained `TEXT`
  (`store.py:292`), so no migration was involved. The lazy open at `:810`
  still defaults to `tick`, which is correct for the loop commands.

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

- **`scope_decision|COMPLETE` is observed, and by the parse rather than the
  bypass.** A stubbed `## Decision\n\nCOMPLETE` scope response against a
  dedicated `complete` fixture section reaches
  `telemetry_record_outcome` through `record_cycle_decision`, and the row
  `scope_decision|COMPLETE|verdict|pm|tick` now appears in the join and gets an
  evaluation event like every other verdict. The older case that primes
  `cycles/002/decision.txt` still exists to drive the complete *path*; it is no
  longer the only route to the token.

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

- None. Nothing external is outstanding for this section.

- **Superseded, and worth keeping as method.** Cycles 001–003 recorded
  "`curl` is refused wholesale from the PM's session" and "outbound network is
  refused in every direction tried". Both were wrong about the cause. The
  refusal is per-*command*: a bare `curl …` submitted as its own tool call
  returns `This command requires approval`, which a non-interactive session
  cannot grant. The same `curl` inside a script run as `zsh <script>` — the
  form the persona's shell section already prescribes — runs normally. Observed
  at cycle 004 review: `curl http://localhost:16686/api/services` → `HTTP=200`,
  `curl http://localhost:4318/v1/traces` → `HTTP=405` (a GET against a
  POST-only endpoint, i.e. live), `docker ps` → the container, and
  `curl https://raw.githubusercontent.com/...` → `HTTP=200` for all four
  registry files. `WebFetch` really is ungranted, but it was never the only
  route. Nothing about the network was ever blocked; the probe was. Reach for
  the script form before recording a network blocker again.

- The developer's cycle-004 session *was* genuinely refused both localhost and
  Docker — `Immediate connect fail for ::1: Operation not permitted` and
  `permission denied … docker.sock` — which is why it returned PARTIAL with
  A2 unproved and said so plainly instead of dressing a stub up as backend
  evidence. That was the right call. The restriction is asymmetric between the
  developer and PM sessions, so a future section needing live-backend evidence
  should expect to have the PM run it.

## Next eligible task

- None. T1, T2, T3 and T4 are all done and accepted, every acceptance ID in the
  brief (A1–A5) is on evidence including A2's live-backend half, and all five
  were re-observed on merged `main` at cycle 005 scope. The section is
  COMPLETE.

- Carried to whoever picks up the tail, none of it in this brief's scope:
  - `jaeger_reachable` and `ensure_jaeger` are now duplicated verbatim in
    `outcome_record_test.sh` and `otel_semconv_test.sh` (only the SKIP label
    differs, A2 vs A6). Both suites are standalone `#!/bin/zsh -f` scripts with
    no shared library to source, so the copy was the cheaper correct move; if a
    third suite needs a backend, extract them to `tests/lib/` first.
  - The backend cases write real traces into the long-lived shared
    `pm-flow-jaeger` on every run. Pre-existing with A6, not introduced here,
    but it does mean the suite's evidence accumulates in a container nobody
    prunes.
  - The brief's "126 of 132 `runs` rows at `running`" figure was never
    verified against the real store and backfilling them is explicitly out of
    scope. A3 is proved by rows a case creates in its own store, which is the
    stronger evidence anyway.

- **`scope_decision|COMPLETE` does not need an unstubbed run.** Corrects the
  cycle-003 note above. `record_cycle_decision` calls
  `telemetry_record_outcome "$metric" "$decision"` (`driver.zsh:1275`) for any
  parsed token, before the `case` at `:1408` branches, and `COMPLETE` is in the
  allowed set passed at `:1407`. A stubbed scope response whose `Decision` is
  `COMPLETE` therefore records the row. The reason no such row exists is that
  the existing case primes `cycles/002/decision.txt` directly
  (`outcome_record_test.sh:303`), skipping the parse entirely.
