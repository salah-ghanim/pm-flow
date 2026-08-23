# otel-semconv workplan

## Design summary

- One module pins the revision and owns every standard name; `telemetry.py`
  calls it. The proof is an independent OTLP/HTTP receiver in the test fed by
  the real record-then-export path, with a Jaeger query as the viewer check
  when Docker is present.

## Interfaces and data changes

- `semconv.REVISION`, `semconv.SPAN_OPERATIONS`, `semconv.attributes_for`.
- New span attribute `pm_flow.semconv.revision`; no schema change.

## Task T1 — Pin the revision and centralise the names

- Status: pending.
- Outcome: `src/pm_flow/semconv.py` declares the pinned GenAI conventions
  revision and exports `attributes_for(attempt)`; `telemetry.py` builds its
  `gen_ai.*` attributes through it and stamps `pm_flow.semconv.revision`; no
  other file contains `gen_ai.`.
- Paths: `src/pm_flow/semconv.py`, `template/.agentic/pm_flow/telemetry.py`,
  `tests/otel_semconv_test.sh`.
- Reuse: the existing attribute block in `telemetry.py` (move, do not
  duplicate); `store.py` span writer.
- Acceptance IDs: A3, A4, A5.
- Validation: `zsh tests/otel_semconv_test.sh` — records one attempt through
  `telemetry.py` and asserts the revision attribute and the names for the
  pinned revision; the A4 grep matches only `semconv.py`; a copy with the
  revision switched emits the alternate names.
- Depends on: None.

## Task T2 — Prove the span tree through an independent receiver

- Status: pending.
- Outcome: the test starts a minimal OTLP/HTTP receiver (standard library),
  drives one stub dispatch through the public driver, runs
  `trace_export.py --otlp` against the receiver, and asserts the
  `invoke_agent` → `chat` tree, the usage attributes equal to the `attempts`
  row joined on `span_id`, and the revision on every span.
- Paths: `tests/otel_semconv_test.sh`.
- Reuse: the disposable-project setup from `tests/pm_flow_test.sh`;
  `trace_export.py` unchanged.
- Acceptance IDs: A1, A2, A7.
- Validation: `zsh tests/otel_semconv_test.sh` exits 0; a mutation that
  drops the `chat` child's usage attributes fails it; `zsh tests/pm_flow_test.sh`
  exits 0.
- Depends on: T1.

## Task T3 — Viewer check against Jaeger

- Status: pending.
- Outcome: with Docker present, the A6 command is run, one run is exported to
  `http://localhost:4318`, and the Jaeger API returns the trace with the A1
  tree; the query and its response are pasted into the result.
- Paths: none (evidence only).
- Reuse: T2's export.
- Acceptance IDs: A6.
- Validation: `curl -s 'http://localhost:16686/api/traces?service=pm-flow'`
  shows operation names `invoke_agent` and `chat` for the exported trace; if
  Docker is absent, the result says so and the handoff records A6 unproven.
- Depends on: T2.

## Integration and end-to-end validation

- T2 is the end-to-end gate; T3 is the viewer confirmation the plan names.

## Risks and rollback

- The conventions move between revisions; the pin confines the churn to one
  edit. Rollback: revert `telemetry.py` to its literal block; stored spans
  are unaffected.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T2 | Receiver shows the tree; usage equals the store |
| A3 | T1, T2 | Revision attribute on every span |
| A4 | T1 | Grep matches only `semconv.py` |
| A5 | T1 | Revision switch changes names in a copy |
| A6 | T3 | Jaeger API returns the tree, or recorded unproven |
| A7 | T2 | Both suites exit 0 |
