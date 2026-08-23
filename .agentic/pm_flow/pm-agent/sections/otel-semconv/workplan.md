# otel-semconv workplan

## Design summary

- Pin one OpenTelemetry GenAI semantic-conventions revision and centralize all
  standard-name mapping in `semconv.py`. Instrument the existing attempt span
  lifecycle through that mapping; non-standard fields use an explicit pm-flow
  namespace instead of masquerading as standard attributes.

## Interfaces and data changes

- `semconv.py` exports the revision, span operation names, token attribute names,
  and a mapping function from pm-flow attempt data to OTel attributes.
- Emitted spans carry the pinned revision and correlate to stored attempts.

## Task T1 — Implement the pinned mapping contract

- Status: pending.
- Outcome: a pure standard-library module maps invoke/chat/tool operations,
  model/provider identifiers, usage, and pm-flow extensions for one revision.
- Paths: `src/pm_flow/semconv.py`, `tests/otel_semconv_test.sh`.
- Reuse: existing attempt and token field names; do not create a second usage
  parser.
- Acceptance IDs: A3, A4, A5.
- Validation: table tests derived from the pinned upstream registry, one-source
  revision assertion, unknown-field namespace test, and repository search that
  rejects `gen_ai.*` literals outside the mapping.
- Depends on: None.

## Task T2 — Emit mapped spans from real dispatches

- Status: blocked until codex-usage releases telemetry/driver ownership.
- Outcome: one role dispatch emits `invoke_agent`; its model call emits nested
  `chat`; token attributes equal the corresponding stored attempt.
- Paths: `src/pm_flow/semconv.py`, `tests/otel_semconv_test.sh`; telemetry and
  driver paths must be transferred before assignment.
- Reuse: current trace/span IDs, attempt begin/end lifecycle, and exporter.
- Acceptance IDs: A1, A2, A3, A4.
- Validation: in-memory/recording exporter assertions join emitted span and
  stored attempt by trace/span IDs; mutation of token mapping must fail.
- Depends on: T1 and codex-usage T3/T4.

## Task T3 — Prove a stock-backend round trip

- Status: pending.
- Outcome: a finished local run opens in a stock OTel backend as the expected
  span tree with matching token counts and visible convention revision.
- Paths: `tests/otel_semconv_test.sh` and approved integration paths.
- Reuse: T2 emission and `trace_export.py`; no backend-specific attributes.
- Acceptance IDs: A1, A2, A3, A6.
- Validation: start an ephemeral collector/backend, run one dispatch, query its
  API or captured OTLP, assert hierarchy/names/counts, and run the full suite.
- Depends on: T2.

## Task T4 — Revision-change mutation and closeout

- Status: pending.
- Outcome: changing the single revision/mapping changes emitted names in one
  place; invented standard-looking fields and self-produced-only proof fail.
- Paths: `src/pm_flow/semconv.py`, `tests/otel_semconv_test.sh`.
- Reuse: T1 registry table and T3 backend harness.
- Acceptance IDs: A3–A6.
- Validation: revision mutation, stray-literal search, non-standard-prefix test,
  backend E2E, and full suite.
- Depends on: T3.

## Integration and end-to-end validation

- Unit mapping, real emission, and backend visibility are three distinct gates.
  A JSON fixture containing expected strings cannot satisfy T2 or T3.

## Risks and rollback

- GenAI conventions are developmental. The revision pin contains churn; rollback
  disables the mapped exporter while retaining stored attempts.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T2, T3 | Stock backend span tree and store-equal tokens |
| A3, A4 | T1, T2, T4 | One revision/mapping source used by emission |
| A5 | T1, T4 | Unknown field uses explicit pm-flow namespace |
| A6 | T3, T4 | Backend scenario and full suite pass |
