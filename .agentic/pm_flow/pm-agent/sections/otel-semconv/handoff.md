## Outcome
- A1 — the receiver in `tests/otel_semconv_test.sh` decoded `TREE primary: 61e56eb0 invoke_agent -> b37abcf1 chat`, exactly one child. `06f9dbc`.
- A2 — the child's `gen_ai.usage.*` (31/13) equal the `attempts` row joined on `spans.parent_span_id = attempts.span_id`; the parent carries neither. `06f9dbc`.
- A3 — every received span carries `pm_flow.semconv.revision`, stamped once in `insert_span`. `e08be2a`.
- A4 — the grep matches only `src/pm_flow/semconv.py`, plus one exempted prose comment at `template/.agentic/pm_flow/catalog.py:250` (owned by `persona-cards`). `e08be2a`.
- A5 — a copy with only `REVISION` switched to `v1.36.0` emits `gen_ai.system` where the primary emits `gen_ai.provider.name`. `a393c6b`.
- A6 — not met; Docker absent (`docker ps` exit 1, socket missing).
- A7 — `otel_semconv_test.sh`, `pm_flow_test.sh` and `store_ledger_test.sh` each exit 0 on merged `main`, the first also in a dirty tree.

## Decisions
- The revision is stamped per span at record time; `trace_export.py` is untouched and stays with `trace-commands`.
- `semconv.py` is loaded by path from `telemetry.py`'s `__file__`, not imported: the engine runs under plain `python3` and one of its three layouts ships no package. Unresolved, spans degrade to `pm_flow.*` with no `chat` child.
- `telemetry.py`, not `driver.zsh`, writes the pair. `attempts.span_id` still points at the `invoke_agent` parent, and `cmd_attempt_start`'s printed lines are unchanged.
- The aggregatable keys (`llm.token_count.*`, `pm_flow.cost_usd|cache_*|reasoning_tokens`, `input.value`, `output.value`) sit on the parent only, so summing a trace cannot double. Nothing goes under `gen_ai.` that the pin does not define; `gen_ai.usage.cost` is retired for `pm_flow.cost_usd`.

## Interfaces
- `src/pm_flow/semconv.py`: `REVISION` (`v1.37.0`), `SPAN_OPERATIONS`, `attributes_for(attempt) -> dict`. Bumping `REVISION` is the whole edit.
- `pm_flow.semconv.revision` on every emitted span.
- `semconv_attributes(..., include_non_convention_attributes=True)` in `telemetry.py`; the two child call sites pass `False`.
- Every dispatch writes two `spans` rows; the child is reached by `spans.parent_span_id`.

## Risks
- Both gates live in `telemetry.py`, not the module: `attributes_for` emits `gen_ai.usage.*` for any span kind and `include_non_convention_attributes` defaults to `True`, so a second caller that forgets either re-duplicates silently.
- Only the two pinned revisions were checked against the upstream registry; a third bump can rename a name unnoticed.

## What is unproven
- A6: no Jaeger, no viewer, on any seat tried. Settled by `docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one` then `curl -s 'http://localhost:16686/api/traces?service=pm-flow'`.
- The protobuf wire route was never exercised: no OTel SDK is installed, so the receiver was fed `trace_export.py --file --replay` output over the test's own HTTP hop. Settled by re-running the suite where the SDK is installed.
- `pm_flow.cache_read_tokens`, `cache_write_tokens` and `reasoning_tokens` are on the parent per a review probe only; the stub emits no such counters. Settled by a stub that does.
- Every span proven came from one stub dispatch; no real model call has been exported.

## Next action
- `persona-cards` rewords the `gen_ai.` mention at `template/.agentic/pm_flow/catalog.py:250`; the exemption in `tests/otel_semconv_test.sh` is then deleted and A4's grep is clean unaided.
