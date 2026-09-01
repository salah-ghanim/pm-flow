## Outcome
All five re-verified by the PM on merged `main` (cycle-004 merge `8f51a55`; `git status` clean over `tests template src`).

- **A1** — the join returns six outcomes rows, one per parsed decision, each with non-NULL `attempt_id`: `scope_decision` ASSIGN/UNPARSED/COMPLETE, `review_verdict|GO_WITH_CHANGES`, `obstruction_class|NONE`, `portfolio_verdict|ON_TRACK`; orphan count 0.
- **A2** — six `gen_ai.evaluation.result` `span_events` on five attempt spans, the same six in exported OTLP JSON, and re-served by the live `pm-flow-jaeger` (`curl .../api/traces/b993f62e…` → span `fc6d31cc1977c3cd`, two `logs` entries). Asserted as `Counter` equality, not presence.
- **A3** — runs table: ten rows, all closed, `6|portfolio-review|ok`, `9|run|ok`, `10|tick|error`, `ended_at IS NULL` = 0.
- **A4** — `UNWRITABLE RUN EXIT: 0`, `UNWRITABLE TICK EXIT: 0`, dispatch output unchanged.
- **A5** — `tests/outcome_record_test.sh`, `tests/otel_semconv_test.sh` (A6 ran) and `template/.agentic/pm_flow/tests/run.zsh` (35+41+32+59+74, `fail=0`) each exit 0.

## Decisions
- `REVISION` is now `v1.38.0`: v1.37.0's registry defines no evaluation event (read first-hand). Reverting the pin removes the event.
- The event keys on `source = 'verdict'`, not a metric allowlist — a new verdict metric gets an event free; `section_status` stays `derived` and excluded structurally.
- Every event failure degrades silently after the outcomes row commits. The row is never lost to the event.
- Runs close in the owning process: explicit `telemetry_end_run ok` in the three on-demand handlers plus an `EXIT` trap closing `error`, made safe by `run-end --only-open`. Closes are first-close-wins; do not "simplify" the explicit calls away.
- `gen_ai.` literals live only in `src/pm_flow/semconv.py`; `driver.zsh` may never spell them.

## Interfaces
- `outcomes.metric` values, all `source='verdict'`, token verbatim in `value_text`: `review_verdict`, `scope_decision`, `portfolio_verdict`, `obstruction_class`. `pm-flow compare` can join these; its existing queries filter `section_status` and are unaffected.
- `runs.command` now records `portfolio-review`, `section-analysis`, `proposals` for the on-demand commands (`PM_FLOW_COMMAND` override intact) — `compare.py:492` groups on it.
- `semconv.evaluation_event()` returns the event name and attribute keys, or `None` on a revision that lacks them.
- No schema migration anywhere.

## Risks
- A later pin move past v1.38.0 silently drops the event unless `_PROVIDER_ATTRIBUTES` and the name map gain an entry; `otel_semconv_test.sh` catches the provider attribute, not the event.
- The two suites duplicate `jaeger_reachable`/`ensure_jaeger`; a third copy should go to `tests/lib/` first.
- Backend cases accumulate traces in the shared, unpruned `pm-flow-jaeger`.

## What is unproven
- Every decision recorded came from a `PM_FLOW_STUB` response. No unstubbed model dispatch has produced an outcomes row; a live tick with the join re-run would settle it.
- Backend evidence is Jaeger only, never Phoenix, and never across real elapsed time — process separation stands in for "hours later".
- `SEMCONV is None` degradation is reasoned from the code, not exercised; only the `v1.36.0` revision path was mutated.
- A3 holds on suite-created stores. The real project store's stuck `running` rows were never counted or fixed.

## Next action
Nothing here. A consumer wanting outcomes in `pm-flow compare` writes the join itself.
