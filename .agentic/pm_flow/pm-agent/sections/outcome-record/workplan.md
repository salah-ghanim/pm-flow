# outcome-record workplan

## Design summary

Every piece of plumbing this section needs already exists and is unused at the
decision call sites. The work is wiring, not new machinery.

- `telemetry.py outcome` (`template/.agentic/pm_flow/telemetry.py:753`, parser
  `:839`) already accepts `--run --task --attempt --metric --num --text
  --source` and inserts a full `outcomes` row. It needs no change for T1.
- `telemetry.py event` (`:504`) already inserts into `span_events`, and
  `trace_export.py:141-147` already emits every `span_events` row as an OTLP
  span event. An evaluation event needs a caller and a name, not an exporter.
- `telemetry_record_outcome` (`driver.zsh:848`) is the only outcome caller and
  hardcodes `--metric section_status` with no `--attempt`. Generalising its
  signature is the whole of T1's driver surface.
- `record_cycle_decision` (`driver.zsh:1221`) is the single funnel every parsed
  verdict passes through: scope (`:1376`), review (`:1505`), portfolio review
  (`:3433`). The obstruction class is parsed separately at `:1513-1516`.

Two facts discovered by reading the code decide the shape of the work:

1. **The attempt handle is destroyed before the decision is parsed.**
   `telemetry_end_attempt` clears `TELEMETRY_ATTEMPT_ID` and
   `TELEMETRY_ATTEMPT_SPAN` (`driver.zsh:843-844`), and it runs inside
   `dispatch_role`, which returns *before* `record_cycle_decision` is called at
   every one of the three call sites. Tying an outcome row or a span event to
   the attempt that produced it therefore requires the dispatcher to stash the
   handle on the way out. Nothing else in the driver can recover it.

2. **`gen_ai.` literals are forbidden outside `semconv.py`.**
   `tests/otel_semconv_test.sh:820-836` greps `template/` and `src/` for
   `gen_ai\.` and fails on any hit outside `src/pm_flow/semconv.py` (one
   comment-only exemption in `catalog.py`). So `gen_ai.evaluation.result` may
   never be spelled in `driver.zsh`, and `telemetry.py` must obtain the event
   name and its attribute keys from `semconv.py`. This is a pre-existing,
   load-bearing assertion; it is not to be relaxed.

Ordering follows evidence cost: the store row (T1) is cheap and proves the
call-site wiring; run closure (T2) is independent and unblocks `compare`'s
`wall_clock`; the span event (T3) reuses T1's stashed attempt span; the real
backend (T4) is the only step needing external infrastructure, so it is last.

## Interfaces and data changes

- New `outcomes.metric` values, all `source = 'verdict'`, `value_text` carrying
  the token verbatim:
  - `review_verdict` — `GO` | `GO_WITH_CHANGES` | `NO_GO` | `UNPARSED`
  - `scope_decision` — `ASSIGN` | `COMPLETE` | `BLOCKED_EXTERNAL` | `UNPARSED`
  - `portfolio_verdict` — `ON_TRACK` | `OFF_TRACK` | `UNPARSED`
  - `obstruction_class` — `NONE` | `HARNESS` | `TASK`
  The existing `section_status` metric (`complete` | `abandoned`, source
  `derived`) is unchanged. `compare.py:468` and `:488` filter on
  `metric = 'section_status'` explicitly, so new metrics cannot perturb
  `cycles_to_done` or `abandoned`.
- No store schema change. `outcomes` (`store.py:369-382`) already has
  `run_id`, `task_id`, `attempt_id`, `metric`, `value_text`, `source`.
- `telemetry_record_outcome` signature changes from
  `(section_key, value)` to `(metric, value, [section_key])`; its two existing
  callers (`driver.zsh:2124`, `:2172`) move with it.
- New driver globals `TELEMETRY_LAST_ATTEMPT_ID` and
  `TELEMETRY_LAST_ATTEMPT_SPAN`, set by `telemetry_end_attempt` before it
  clears the live pair.
- `gen_ai.evaluation.result` event shape, defined in T3 and exported by the
  existing generic path.

## Task T1 — Record every parsed cycle decision as an outcomes row

- Status: done (cycle 001, accepted)
- Outcome: after a stubbed tick that carries a scope and a review to their
  verdicts, the store holds one `outcomes` row per decision, each with a
  non-NULL `attempt_id` joining to the attempt that produced the response and a
  `run_id` joining to that tick's run. A new suite proves it.
- Paths: `template/.agentic/pm_flow/driver.zsh`,
  `tests/outcome_record_test.sh`, `tests/fixtures/outcome_record/**`
- Reuse: `telemetry.py outcome` and its parser as-is (no telemetry.py edit
  needed); `telemetry_record_outcome` (`driver.zsh:848`) as the single writer;
  `record_cycle_decision` (`:1221`) as the funnel; `telemetry_end_attempt`
  (`:831`) for the stashed handle; `tests/boundary_schema_test.sh:1-45` for the
  suite preamble (PM_FLOW_* scrub, guarded mktemp, `fail`/`assert_eq`);
  `template/.agentic/pm_flow/tests/transitions.zsh` for the `PM_FLOW_STUB`
  dispatch-stub pattern.
- Acceptance IDs: A1
- Validation: `zsh tests/outcome_record_test.sh` exits 0 and prints a PASS line
  for the join; inside it, a `sqlite3` SELECT joining `outcomes` to `attempts`
  and `runs` returns exactly one row per decision with the expected
  `metric`/`value_text` pair.
- Depends on: None.

## Task T2 — Close every run on every exit path, and fix the leak

- Status: done (cycle 002, accepted)
- Outcome: after a completed `run` and a deliberately failed `tick`, both new
  `runs` rows carry a terminal status (`ok` or `error`) and a non-NULL
  `ended_at`; no dispatching command leaves a row at `running`. The specific
  leak is named in `state.md` with the observation that identified it.
- Paths: `template/.agentic/pm_flow/driver.zsh`,
  `template/.agentic/pm_flow/telemetry.py`, `tests/outcome_record_test.sh`
- Reuse: `telemetry_begin_run` (`:724`) and `telemetry_end_run` (`:757`);
  the existing close calls in `cmd_tick` (`:2779-2833`) and `cmd_run`
  (`:2916-2923`); `cmd_run_end` (`telemetry.py:467`).
- Resolved: both candidate leaks were real. (a) is closed by explicit
  `telemetry_begin_run`/`telemetry_end_run ok` pairs in the three on-demand
  commands; (b) by an owner-process `EXIT` trap at driver source scope
  (`driver.zsh:779`) that closes as `error`, guarded store-side by a new
  `--only-open` flag on `telemetry.py run-end` so it can never replace a
  terminal status the command already wrote.
- Investigate, do not assume: the two candidate leaks are (a) the lazy open at
  `driver.zsh:797`, where `telemetry_begin_attempt` starts a run for *any*
  dispatching command — `cmd_portfolio_review` (`:3710`),
  `cmd_section_analysis` (`:3725`), `cmd_proposals` (`:3796`) — none of which
  call `telemetry_end_run`; and (b) `fail`/`set -e` aborts inside `cmd_tick`
  and `cmd_run`, e.g. `assert_within_budget` at `:2818`. Confirm which is
  responsible before fixing.
- Note: `cmd_run_end` unconditionally overwrites `ended_at` and `status`, so
  any safety-net close must not clobber a terminal status already written by
  the owning command. Constrain the update to rows still open.
- Acceptance IDs: A3, A4
- Validation: `zsh tests/outcome_record_test.sh` exits 0; its new cases assert
  `SELECT COUNT(*) FROM runs WHERE ended_at IS NULL` is 0 for the rows created
  by the case, and that with the store made unwritable both `run` and `tick`
  still dispatch and exit 0.
- Depends on: T1 (shares the suite).

## Task T3 — Emit a `gen_ai.evaluation.result` span event per decision

- Status: pending
- Outcome: each recorded decision also writes a `span_events` row named by the
  semantic conventions and carrying the verdict, attached to the attempt span
  that produced the response; `trace_export.py --file` shows it as an OTLP
  event on that span.
- Paths: `src/pm_flow/semconv.py`,
  `template/.agentic/pm_flow/telemetry.py`,
  `template/.agentic/pm_flow/driver.zsh`, `tests/outcome_record_test.sh`,
  and `tests/otel_semconv_test.sh` only if the pin moves.
- Reuse: the stashed `TELEMETRY_LAST_ATTEMPT_SPAN` from T1;
  `telemetry.py event` (`:504`) and its `span_events` insert;
  `trace_export.py:141-147`, which already emits events generically and needs
  no change.
- Constraint: the event name and every attribute key must come from
  `src/pm_flow/semconv.py`. `tests/otel_semconv_test.sh:820-836` fails the
  build on a `gen_ai.` literal anywhere else in `template/` or `src/`, and
  `driver.zsh` cannot import Python, so the name must be resolved inside
  `telemetry.py`.
- Pin decision, to be made in this task and recorded in `state.md`: verify
  against the `semantic-conventions` repository whether the pinned `v1.37.0`
  defines the evaluation event. Move `REVISION` to `v1.38.0` only if it does
  not, and only with `_PROVIDER_ATTRIBUTES` extended and the sed pattern at
  `tests/otel_semconv_test.sh:805` tracked minimally — the revision-swap
  mechanism and every existing assertion stay load-bearing.
- Acceptance IDs: A2 (store and file-export half), A5
- Validation: `zsh tests/outcome_record_test.sh` and
  `zsh tests/otel_semconv_test.sh` both exit 0; the new case asserts the
  exported OTLP JSON has the event on the attempt span with the verdict.
- Depends on: T1.

## Integration and end-to-end validation

## Task T4 — Prove all four scenarios end to end against a real backend

- Status: pending
- Outcome: a real `pm-flow run` and a forced-failure `pm-flow tick` against a
  live local OTLP backend, with the four brief scenarios walked in order and
  their observed output recorded in `state.md`: the outcomes join, the
  evaluation event visible in the backend UI after the run, both runs closed,
  and a dispatch surviving an unwritable store at exit 0.
- Paths: `tests/outcome_record_test.sh`, `tests/fixtures/outcome_record/**`
- Reuse: the settled `pm-flow-jaeger` render (or Phoenix) named in the brief;
  `telemetry_autoexport` (`driver.zsh:774`) and `pm-flow trace export --otlp`;
  `tests/otel_semconv_test.sh`'s Jaeger assertions (`assert_jaeger_tree`) as
  the pattern for querying a live backend.
- Acceptance IDs: A1, A2, A3, A4, A5
- Validation: `pm-flow trace export --otlp http://localhost:4318/v1/traces`
  followed by a backend query showing the `gen_ai.evaluation.result` event
  with its verdict on the attempt span; `zsh tests/outcome_record_test.sh`,
  `zsh tests/otel_semconv_test.sh` and
  `zsh template/.agentic/pm_flow/tests/run.zsh` all exit 0.
- Depends on: T1, T2, T3.

## Risks and rollback

- Recording inside `record_cycle_decision` risks contaminating its stdout: the
  function's output is captured by command substitution at all three call
  sites and is the driver's control flow. Any new call must redirect both
  streams. Rollback is deleting the single call line.
- The signature change to `telemetry_record_outcome` has two existing callers
  (`driver.zsh:2124`, `:2172`) whose arguments are positionally identical
  today; missing one silently mislabels a `section_status` row. Both must move
  in the same edit.
- A safety-net run close could overwrite a real terminal status with a generic
  one, which would look like a fix while destroying the signal A3 exists to
  produce. Constrain it to rows still open.
- Moving `REVISION` touches otel-semconv's accepted evidence. If v1.37.0 turns
  out to define the event, do not move the pin at all — that is the cheapest
  and safest outcome.
- Rollback for the whole section is a revert of the driver and telemetry
  edits; nothing here is a schema migration, so no data is stranded.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T4 | sqlite3 SELECT joining `outcomes` to `attempts` and `runs`, one row per decision with the verdict in `value_text` |
| A2 | T3, T4 | exported OTLP JSON carries the event; live Jaeger/Phoenix UI shows it on the attempt span after the run |
| A3 | T2, T4 | SELECT over the two new `runs` rows showing terminal status and non-NULL `ended_at`, none left `running` |
| A4 | T2, T4 | `run` and `tick` with an unwritable store still dispatch and exit 0 |
| A5 | T3, T4 | `tests/outcome_record_test.sh`, `tests/otel_semconv_test.sh` and `template/.agentic/pm_flow/tests/run.zsh` each exit 0 |
