## Outcome
- **A1** — receiver decoded one `invoke_agent` with exactly one `chat` child: `TREE primary: 61e56eb0442d29d7 invoke_agent -> b37abcf1cb062168 chat`, `zsh tests/otel_semconv_test.sh` exit 0 on `main`. Commit `06f9dbc`.
- **A2** — child `gen_ai.usage.input_tokens=31`/`output_tokens=13` equal the joined `attempts` row; parent carries neither. `06f9dbc`.
- **A3** — every received span, parent and child, carries `pm_flow.semconv.revision`. `a393c6b`.
- **A4** — grep matches only `src/pm_flow/semconv.py`, plus one exempted prose comment at `template/.agentic/pm_flow/catalog.py:250` (owned by `persona-cards`). `e08be2a`.
- **A5** — a copy with only `REVISION` set to `v1.36.0` emits `gen_ai.system` in place of `gen_ai.provider.name`, asserted on the receiver. `a393c6b`.
- **A6** — unproven; see below.
- **A7** — `pm_flow_test.sh` (10 PASS) and `store_ledger_test.sh` exit 0 on `main`. `06f9dbc`.

## Decisions
- The revision is stamped per span in `insert_span` at record time; `trace_export.py` is untouched and stays with `trace-commands`.
- `semconv.py` is loaded **by path** from `telemetry.py.__file__`, never `import pm_flow.semconv`: telemetry runs under plain `python3` in three layouts, and an installed import would make A5 prove nothing.
- `telemetry.py` writes the `invoke_agent`→`chat` pair itself; `driver.zsh` is unchanged and `attempts.span_id` still points at the parent, so A2 joins `spans.parent_span_id = attempts.span_id`.
- No `chat` child when `SEMCONV` is `None` (engine copied alone emits `pm_flow.*` only, no GenAI names).
- `llm.token_count.*`, `pm_flow.cost_usd|cache_*|reasoning_tokens` and the `input.value`/`output.value` bodies live on the parent only.
- Nothing is emitted under `gen_ai.` that the pin does not define; `gen_ai.usage.cost` is retired.

## Interfaces
- `src/pm_flow/semconv.py`: `REVISION`, `SPAN_OPERATIONS`, `attributes_for(attempt) -> dict`. The only file holding a `gen_ai.` literal; bump `REVISION` alone to change names.
- `pm_flow.semconv.revision` on every emitted span.
- `semconv_attributes(..., include_non_convention_attributes=True)` (telemetry.py:247); child call sites pass `False`.
- `zsh tests/otel_semconv_test.sh` — the end-to-end gate.

## Risks
- `attributes_for` still emits `gen_ai.usage.*` for any span kind — the chat gate lives in telemetry's caller. A second caller would land usage on a non-chat span.
- `include_non_convention_attributes` defaults `True`, so a new child call site re-duplicates silently; the split assertion covers only the two existing sites.
- The conventions are Development and rename between releases; the secondary-pin run is what reveals a breaking bump.

## What is unproven
- **A6**: no stock viewer has ever received these spans. Docker absent on every seat (`docker ps` → exit 1, socket missing). `docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one` then `curl -s 'http://localhost:16686/api/traces?service=pm-flow'` settles it.
- The wire route never ran: the OTel SDK is not installed, so all proof used `trace_export.py --file --replay` POSTed by the test. Install the exporter and re-run to exercise `telemetry_autoexport`'s protobuf path.
- `pm_flow.cache_read_tokens`, `cache_write_tokens` and `reasoning_tokens` on the parent are proven only by cycle 004's probe — the stub emits no such counters. A stub emitting them settles it.
- One dispatch, one stub model, one host.

## Next action
- `persona-cards` rewords `catalog.py:250`; then delete the test's one-file A4 exemption.
- Any Docker-capable host runs the A6 command.
- `trace-commands` must route `pm-flow trace export` through the same serialiser.
