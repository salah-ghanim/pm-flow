## Objective

- pm-flow's spans carry the OpenTelemetry GenAI semantic-convention names of
  one pinned revision, defined in one module, so a finished run opens in a
  stock backend with names it already understands.

## Current baseline

- `telemetry.py` writes `gen_ai.*`, `llm.*`, `openinference.span.kind`,
  `session.id` and `pm_flow.*` attributes as string literals when a span is
  recorded; `trace_export.py` serialises stored spans to OTLP under scope
  `pm-flow` with no version.
- No file states which convention revision those names come from, and the
  GenAI conventions are still marked Development and change between releases.

## Deliverables

- `src/pm_flow/semconv.py`: the pinned revision, every standard span and
  attribute name pm-flow emits, and the function that maps an attempt to
  attributes; the only file containing a `gen_ai.` literal.
- `telemetry.py` recording through that mapping, with the revision stamped on
  every span it emits.
- `tests/otel_semconv_test.sh`.

## User-visible scenarios

1. A run is exported with `pm-flow trace export --otlp <url>` to a stock
   backend; the viewer shows each role dispatch as an `invoke_agent` span
   with its model call as a `chat` child, token counts under the convention's
   usage attributes, and the convention revision readable on the span.
2. A maintainer bumps the pinned revision in `semconv.py`; emitted names change
   with no other file edited.

## Interfaces produced

- `semconv.REVISION` and `semconv.attributes_for(attempt) -> dict`.
- Span attribute `pm_flow.semconv.revision` on every emitted span.

## Interfaces consumed

- `attempts` token and identity columns; `store.py` span writer.

## Scope

- In: the mapping module, the pinned revision, recording through it, the
  stray-literal guard, the backend proof.
- Out: the export commands and checkpointing (`trace-commands`), what is
  measured, OpenInference names (left as they are).

## Non-goals

- Waiting for a stable 1.0 of the GenAI conventions.
- Backend-specific attributes.

## Priority

- must-have: without it the record that is supposed to outlive the run speaks
  a private dialect and needs pm-flow present to read it.

## Owned paths

- `src/pm_flow/semconv.py`
- `template/.agentic/pm_flow/telemetry.py`
- `tests/otel_semconv_test.sh`

## Dependencies

- None.

## Constraints and fixed decisions

- The revision travels as a span attribute set at record time, not as an
  exporter resource attribute; `trace_export.py` is not edited from here.
- A pm-flow-specific attribute keeps the `pm_flow.` prefix and is never renamed
  to a standard-looking name the revision does not define.

## Acceptance

- A1: On a run recorded after this change, an OTLP receiver independent of
  pm-flow (`tests/otel_semconv_test.sh` starts one) receives, for each role
  dispatch, a span with `gen_ai.operation.name=invoke_agent` whose child has
  `gen_ai.operation.name=chat`.
- A2: The `chat` span's `gen_ai.usage.input_tokens` and
  `gen_ai.usage.output_tokens` equal the `attempts` row for the same
  `span_id`; a disagreement fails the test.
- A3: Every emitted span carries `pm_flow.semconv.revision` equal to
  `semconv.REVISION`.
- A4: `grep -rn 'gen_ai\.' template/ src/ --include='*.py' --include='*.zsh'
  --include='*.sh'` matches only `src/pm_flow/semconv.py`.
- A5: Changing `semconv.REVISION` to a second pinned revision changes the
  emitted names in the test's receiver with no other file edited (the test
  performs the edit in a copy).
- A6: A Jaeger instance (`docker run -d -p 4318:4318 -p 16686:16686
  jaegertracing/all-in-one`) queried at `/api/traces?service=pm-flow` returns
  the exported trace with the A1 span tree. If Docker is not available on the
  host, the handoff records this unproven with that command as what settles
  it.
- A7: `zsh tests/otel_semconv_test.sh` and `zsh tests/pm_flow_test.sh` exit 0.

## Rejection conditions

- A `gen_ai.` literal outside `semconv.py`.
- A revision adopted without being recorded, or described as stable.
- A name invented where the pinned revision defines one.
- The receiver in the test is fed by the mapping module rather than by the
  real record-and-export path.
- A file outside Owned paths is modified.

## Open questions

- None.
