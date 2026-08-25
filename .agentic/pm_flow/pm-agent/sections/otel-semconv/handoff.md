## Outcome
- A1 — an independent OTLP receiver decodes one `invoke_agent` per dispatch with exactly one `chat` child (`TREE primary: 5f25ebfe5c8e5e03 -> f30666db7b2e1142`), green twice in a row.
- A2 — the child's `gen_ai.usage.*` equals the `attempts` row (31/13) via `spans.parent_span_id = attempts.span_id`; an off-by-one mutation fails the suite.
- A3 — `pm_flow.semconv.revision` on every span, stamped once in `insert_span`; an absent tag fails, root span included.
- A4 — the grep matches only `src/pm_flow/semconv.py`, plus one exempted comment at `template/.agentic/pm_flow/catalog.py:254`.
- A5 — a tree pinned `v1.36.0` emits `gen_ai.system`, the primary `gen_ai.provider.name`; `REVISION` is the only edit.
- A6 — Jaeger re-serves this run's own trace at `/api/traces/<traceID>` with that tree, usage and revision; live, not skipped.
- A7 — `otel_semconv_test.sh`, `pm_flow_test.sh` (10 PASS) and `store_ledger_test.sh` all exit 0.

All at commit `2afd3d1` on `main`, re-verified there at cycle 008 rather than inherited.

## Decisions
- `telemetry.py` loads `semconv.py` by path from `__file__`, never `import pm_flow.semconv`: the engine runs under plain `python3`, and an installed import would defeat A5.
- `telemetry.py` writes the `chat` child itself, since `driver.zsh` is not owned here. The printed `span_id`, the traceparent and the `attempt-end` lookup are unchanged, and `attempts.span_id` still points at the parent.
- Aggregatable and bulky keys (`llm.token_count.*`, `pm_flow.cost_usd|cache_*|reasoning_tokens`, `input.value`, `output.value`) stay on the parent only, so a backend summing a trace cannot double-count.
- Where no `semconv.py` resolves (engine copied alone), no GenAI names and no `chat` child are written.

## Interfaces
- `src/pm_flow/semconv.py`: `REVISION`, `SPAN_OPERATIONS`, `attributes_for(attempt)`. Bumping the pin is a one-file edit.
- `pm_flow.semconv.revision` on every span; `gen_ai.operation.name` is `invoke_agent` or `chat`.
- `zsh tests/otel_semconv_test.sh` — needs `curl`; reuses a Jaeger already on 16686 and removes only one it started.

## Risks
- `attributes_for` still emits `gen_ai.usage.*` for any `span_kind`; the chat gate lives in its caller. A second caller would put usage back on the parent — the receiver's parent assertion reveals it.
- The GenAI conventions are Development. A bump renames keys and breaks dashboards keyed on the old ones; the pin confines the edit, not the consequence.
- Every A6 run adds one trace to whatever Jaeger answers on 16686.

## What is unproven
- `pm_flow.cache_read_tokens`, `pm_flow.cache_write_tokens` and `pm_flow.reasoning_tokens` on the parent: the stub emits no such usage, so only a cycle-004 probe showed them. A dispatch with a real cache/reasoning usage block settles it.
- `trace_export.py --protocol grpc` is never exercised — the SDK is absent here. Installing it and exporting over grpc settles it.
- The suite drives one stub dispatch; multi-dispatch behaviour is only ambient (100 `invoke_agent`→`chat` pairs from real runs in the user's Jaeger), not asserted.
- Jaeger is the only backend that has read these spans.

## Next action
`persona-cards` rewords the `gen_ai.*` comment at `template/.agentic/pm_flow/catalog.py:254`; then delete the one-file A4 exemption in `tests/otel_semconv_test.sh`.
