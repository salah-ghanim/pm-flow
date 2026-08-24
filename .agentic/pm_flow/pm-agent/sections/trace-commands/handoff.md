## Outcome
- **A1** — Packaged `pm-flow trace export --otlp` printed `exported 1 span(s)`, the receiver body carried the tick's exact span id `99b2d34aaedd17bc`, `exported_at IS NOT NULL` equalled 1, and the rerun printed 0 with the request count unmoved (c79f7c2, merged e93b937).
- **A2** — In a `--no-deps` wheel venv where `import opentelemetry` exits non-zero, `--file` wrote a line accepted by both `validate_otlp_json` and the suite's independent JSON-Schema checker (c79f7c2).
- **A3** — 503, a 0.05 s timeout and partial success each leave every `exported_at` null and a later 200 delivers the same span ids; unchanged by cycle 003 (cycle 002 work, still passing at e8d846b).
- **A4** — A packaged `telemetry.enabled: false` tick exits 0 with the span count unchanged and `status` prints `recording: disabled`; with recording on, `unexported spans:` equals what the next export ships and open spans appear on a new `in-flight spans:` line (c79f7c2).
- **A5** — `trace_commands_test.sh` (full mode), `pm_flow_test.sh` and `packaged_layout_test.sh` each exit 0 on `main` at e8d846b.

## Decisions
- A 2xx acknowledgement, not an attempt, marks a span exported; stdout reports spans *marked*, not acknowledged.
- HTTP delivery is a stdlib `urllib` POST of OTLP/JSON. The SDK's `export()` reports only SUCCESS/FAILURE and cannot witness the 2xx A1/A3 are written against; `--protocol grpc` still uses the SDK.
- `pm_flow.sh` is owned for the `trace` routing and its usage lines only.
- No vendor endpoint is defaulted; `telemetry.otlp_endpoint` is empty in shipped config.
- The suite's `--offline` flag is opt-in and says on stdout which cases were skipped. Nothing may invoke the suite with it — receiver-backed cases would go silently absent.

## Interfaces
- `pm-flow trace export --otlp <url> [--header k=v] | --file <path>`, `pm-flow trace status` (5 lines now: `recording:`, `endpoint:`, `unexported spans:`, `in-flight spans:`, `exported spans:`).
- `config.json` `telemetry: {enabled, otlp_endpoint, headers}` at lines 59-63.
- `trace_export.py` consumes `spans`/`span_events` and `spans.exported_at`; `otel-semconv` owns the attribute names.

## Risks
- **`otel-semconv` action:** a completed tick leaves one span with `ended_at IS NULL`. A span that never closes never exports, so the objective is not true of it. `telemetry.py finish_span` owns when a span closes. `trace status`'s in-flight count reveals it.
- `fetch_spans` orders by `started_at ASC` while the test expects `started_at, span_id`. Two finished spans sharing a `started_at` would flap the id assertion.

## What is unproven
- Multi-span batching through the installed command: the packaged round trip ships a single-span payload because that is all one stub tick records. Batching is proven only against three SQL-seeded spans in the checkout block. A tick recording two or more finished spans would settle it.
- `--protocol grpc` is untested against any receiver; no case imports the SDK.
- Phoenix, Jaeger and Langfuse are documented but never contacted; only the loopback `http.server` receiver has answered.

## Next action
- None here. Route the never-closed span to `otel-semconv`.
