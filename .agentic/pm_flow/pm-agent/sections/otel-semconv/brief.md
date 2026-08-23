## Objective

- Emit pm-flow's telemetry under the OpenTelemetry GenAI semantic conventions,
  pinned to one stated revision, so a finished run opens in a stock backend with
  names that backend already understands.

## Scope

`plan.md` says to adopt a standard where one exists and is better than what we
would write, and names OpenTelemetry and OpenInference first. Three sections are
about to invent attribute names independently: `codex-usage` carries tokens into
the store, `trace-commands` exposes traces, `store-ledger` reports them. Left
alone they will each name the same quantity differently and none of them will
match what Phoenix, Langfuse or Jaeger expect.

The conventions now model an agent run as a span tree: `invoke_agent` for a role
dispatch, `chat` for each model call beneath it, `execute_tool` for each tool
invocation, with `gen_ai.operation.name` covering the lifecycle. That is the
shape pm-flow already produces; what is missing is that it says so in the
standard's vocabulary.

Two facts decide the design, and both cut against treating this as a one-off
rename:

- **The conventions are not stable.** Every `gen_ai.*` attribute, span, metric
  and event in the registry still carries the `Development` badge. None is
  marked stable, and names change between versions.
- **They now move on their own cadence.** At v1.42.0 the `gen_ai.*` work was
  moved out of the main semantic-conventions repository into a dedicated GenAI
  conventions repository, deliberately so it can release faster than the
  stability-bound core.

So: adopt the names, pin the revision, and put the mapping in one module, so a
convention bump is a single edit rather than a search across the engine. Waiting
for a 1.0 that has no date is the more expensive option, because every week of
waiting is another locally invented attribute name to migrate later.

In scope: the mapping module, the pinned revision, and the proof that a real
run's spans carry conventional names. Out of scope: changing what is measured,
adding a backend, and OpenInference, which is a second vocabulary and deserves
its own decision rather than being smuggled in here.

## Priority

- must-have. Without it the measurement layer speaks a private dialect, and the
  record that is supposed to outlive the run needs pm-flow present to read it.

## Owned paths

- `src/pm_flow/semconv.py`
- `tests/otel_semconv_test.sh`

The mapping is independently testable in these new paths. Real emission is a
later workplan task and requires a validated transfer of the telemetry/driver
paths after `codex-usage`; it must not be faked by testing only this module.

## Dependencies

- codex-usage

`codex-usage` owns the attempt lifecycle and telemetry integration paths. It
must settle and release those interfaces before this section changes emission.
`store-ledger` is a downstream reader, not a prerequisite; making it one created
a dependency cycle through trace export.

## Acceptance

Stable IDs `A1`–`A6` refer to the bullets below in order.

Stated as outcomes in the running system; a fixture containing the right strings
cannot substitute for emitted telemetry.

- A run finished on this machine and opened afterwards in a stock OpenTelemetry
  backend shows a role dispatch as an `invoke_agent` span, with its model calls
  as `chat` spans nested beneath it, identified by `gen_ai.operation.name`. Not
  a JSON file that contains those strings — the trace, in the viewer.
- The token counts on that span are readable under the conventions' own token
  attributes, and the numbers equal what the store holds for the same attempt.
  A disagreement between the two is a failure, not a rounding note.
- The pinned convention revision is stated in exactly one place and travels with
  the emitted telemetry, so somebody reading the run months later can tell which
  revision the names came from without asking.
- Changing that pinned revision changes the emitted names, and the change is one
  edit in one module. No role prompt, driver path or store query names a
  `gen_ai.*` attribute directly.
- An attribute the pinned revision does not define is still emitted, under a
  clearly non-standard prefix, rather than being dropped or renamed into the
  nearest standard-looking thing.
- The suite still passes.

## Rejection conditions

- A `gen_ai.*` literal appears anywhere outside the mapping module.
- The conventions are described as stable, or a revision is adopted without
  recording which one was adopted.
- A name is invented where the pinned revision already defines one.
- The mapping is proven only against a fixture that the mapping itself produced.
- Emitted telemetry changes shape but nothing verifies it against a real backend.
- The suite is weakened, or made to exit zero without running to completion.
