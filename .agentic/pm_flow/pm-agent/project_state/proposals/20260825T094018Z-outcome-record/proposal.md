## Assessment

The request asks for outcome data — cycle verdicts, obstruction classes, scope and completion decisions in the store and traces, and run rows that actually close. It serves the plan's objective sentence directly ("run the same work under two designs … and know whether it helped") and the metrics principle: cycles-to-done, rescue rate, abandonment rate and escalation depth are all computable only from recorded decisions and closed runs. The plan already anticipated this work: its documented-limits bullet defers fixing "`runs.ended_at` stays NULL" for capped arms "until capped-arm measurement matters" — this request is the dated decision that it now matters.

Probes run against `main` and the live store:

- `zsh probe_store.zsh` (sqlite3 over `.agentic/pm_flow/pm-agent/runs/pm_flow.db`): `outcomes` holds only `metric=section_status` (5 rows); `runs` shows 126 of 132 rows at status `running`, all 126 with NULL `ended_at`. The owner's 123/128 figure has drifted but the claim holds.
- `grep` on `telemetry.py`: the `outcome` subcommand exists (`telemetry.py:753`, registered at `:839`). One correction to the request: it **is** called — but only via `telemetry_record_outcome` (`driver.zsh:848`) for the derived `section_status` metric at complete/abandon (`driver.zsh:2124`, `:2172`). No verdict ever reaches it.
- `grep` on `driver.zsh`: `record_cycle_decision` (`:1221`) writes only `decision.txt`; call sites at `:1376` (ASSIGN/COMPLETE/BLOCKED_EXTERNAL), `:1505` (GO/GO_WITH_CHANGES/NO_GO), `:3433` (ON_TRACK/OFF_TRACK); obstruction parse at `:1513-1516` writes only `obstruction.txt`. `telemetry_end_run` (`:757`) is wired into tick and run exits (`:2779-2833`, `:2916-2923`), yet 126 rows never closed — dispatch-context runs opened lazily at `:797` are the likely leak; the section must find the real cause.
- `grep gen_ai.evaluation` across `src`, `template`, `tests`: absent. `src/pm_flow/semconv.py:16` pins `REVISION = "v1.37.0"`; `tests/otel_semconv_test.sh:805` sed-swaps exactly that string to v1.36.0, so moving the pin to v1.38.0 breaks that suite unless it is edited — its path must be owned here. `trace_export.py` ships span events generically from `span_events` (`:72-147`), so export needs no change.

Coverage: nothing covers it. The only live section, `real-install`, owns installer paths only — fully disjoint. `otel-semconv`, `store-ledger` and `topology-compare` are done and terminal; the store's contents prove none of them recorded verdicts. Neither cancelled section touches this.

## Section: outcome-record

### Objective
- Every cycle decision the driver parses and every run end lands in the store and the exported trace, so a finished run carries its outcomes and duration, not only its costs.

### Current baseline
- `telemetry.py outcome` subcommand (`template/.agentic/pm_flow/telemetry.py:753`) inserts into an `outcomes` table that today holds only 5 derived `section_status` rows, written from `driver.zsh:848-857`.
- `record_cycle_decision` (`template/.agentic/pm_flow/driver.zsh:1221`; call sites `:1376`, `:1505`, `:3433`) and the obstruction parse (`:1513-1516`) write verdicts to cycle files only; nothing reaches the store or traces.
- `telemetry_end_run` (`driver.zsh:757`) exists and is wired into tick/run exit paths, yet 126 of 132 `runs` rows sit at `running` with NULL `ended_at`.
- `src/pm_flow/semconv.py:16` pins `REVISION = "v1.37.0"`; no `gen_ai.evaluation.*` anywhere; `tests/otel_semconv_test.sh:805` sed-swaps that exact pin. `trace_export.py:72-147` already exports span events generically.

### Deliverables
- An `outcomes` row per parsed cycle decision — review verdicts (GO / GO_WITH_CHANGES / NO_GO / UNPARSED), scope decisions (ASSIGN / COMPLETE / BLOCKED_EXTERNAL), portfolio verdicts (ON_TRACK / OFF_TRACK) and obstruction classes (NONE / HARNESS / TASK) — tied to its attempt and run, written through the existing `outcome` subcommand.
- A `gen_ai.evaluation.result` span event per decision, per the OTel GenAI semantic conventions, present in exported traces.
- `runs` rows closed with a real terminal status and `ended_at` by both `run` and `tick`, including when a tick fails; the leak that leaves dispatch-opened runs unclosed is found and fixed.
- The swallow-and-exit-0 invariant preserved on every new call site.
- A new suite `tests/outcome_record_test.sh` wired into `tests/run.zsh`.

### User-visible scenarios
1. Run a tick that carries a review to a verdict; one `sqlite3` SELECT on the store shows an outcomes row with that verdict, joined to the attempt and run that produced it.
2. Run `pm-flow trace export --otlp http://localhost:4318/v1/traces` against a local Jaeger or Phoenix; the review attempt's span shows a `gen_ai.evaluation.result` event carrying the verdict, hours after the run.
3. Run `pm-flow run` to completion and force one `pm-flow tick` to fail; both new `runs` rows show a terminal status and non-NULL `ended_at`, and no new row is left at `running`.
4. Make the store unwritable and dispatch; the dispatch still happens and exits 0.

### Interfaces produced
- The outcome metric names and source values written to the `outcomes` table, documented so `pm-flow compare` can later join a real outcome column.
- The `gen_ai.evaluation.result` event shape on exported spans.

### Interfaces consumed
- The store schema from store-ledger (`outcomes`, `runs`, `span_events` tables) as-is.
- The revision map and pin discipline in `src/pm_flow/semconv.py` from otel-semconv.

### Scope
- In: outcome wiring at the driver's decision call sites, run closure on all exit paths, the evaluation span event, a pin move to v1.38.0 if the manager judges it necessary, the new suite.
- Out: extending `pm-flow compare`; backfilling or sweeping the 126 historical stuck `runs` rows; any store schema migration beyond what outcome rows already have columns for.

### Non-goals
- Subjective quality scoring or judge-model metrics; the plan admits objective metrics only.
- An outcome column in `pm-flow compare` — the owner explicitly excluded it.
- Repricing or repairing the under-counted 2026-08-24 store window.

### Priority
- must-have: without recorded outcomes and closed runs, "two topologies compared in one command" compares arms with no outcome and no wall clock, and the objective's "know whether it helped" cannot be answered.

### Owned paths
- template/.agentic/pm_flow/telemetry.py
- template/.agentic/pm_flow/driver.zsh
- src/pm_flow/semconv.py
- tests/otel_semconv_test.sh
- tests/outcome_record_test.sh
- tests/fixtures/outcome_record/**

### Dependencies
- None.

### Constraints and fixed decisions
- Recording failure never fails a dispatch: the swallow-and-exit-0 contract `telemetry.py` already holds applies to every new call site.
- The driver's file-derived state machine stays: `decision.txt` and `obstruction.txt` remain authoritative for control flow; store rows are additive records, never inputs to scheduling.
- If `REVISION` moves to v1.38.0, `tests/otel_semconv_test.sh` may be edited only minimally to track the pin; its revision-swap mechanism must remain load-bearing and the suite green on `main`. Weakening otel-semconv's accepted evidence is not open.
- End-to-end verification is against a real local OTLP backend (the settled `pm-flow-jaeger` render, or Phoenix), not only a loopback receiver.
- These paths are the engine: work happens in a git worktree, merged back after review.

### Acceptance
- A1: after a tick that parses a review verdict, one sqlite3 SELECT shows an outcomes row for that verdict tied to its attempt and run (scenario 1).
- A2: after `pm-flow trace export`, a local Jaeger or Phoenix shows a `gen_ai.evaluation.result` event with the verdict on the corresponding attempt span, checkable in the backend UI hours later (scenario 2).
- A3: after one completed `run` and one failed `tick`, both new `runs` rows have a terminal status and non-NULL `ended_at`, verified by SELECT (scenario 3).
- A4: with the store unwritable, `run` and `tick` still dispatch and exit 0 (scenario 4).
- A5: `tests/outcome_record_test.sh` exits 0 on `main`, `tests/otel_semconv_test.sh` stays green, and `tests/run.zsh` runs to completion.

### Rejection conditions
- Outcome rows produced by re-scraping cycle files at export time instead of being recorded at the decision call sites — that is a derived report, not a record.
- Any path where a telemetry failure changes dispatch behaviour, output, or exit status.
- Runs closed by a sweeper that marks stale rows terminal rather than by the `run` or `tick` that owns them.
- Backend evidence supplied only by a loopback test receiver.
- A pin move that passes by weakening `otel_semconv_test.sh`'s assertions.

### Open questions
- None.

## Decision
CUT — the plan's objective and its deferred `runs.ended_at` limit both need this; store probes show only derived `section_status` rows and 126 of 132 runs never closed, and no live or done section records decisions.
