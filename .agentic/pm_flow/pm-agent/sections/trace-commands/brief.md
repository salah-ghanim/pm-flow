## Objective

- A recorded run ships to any OTLP backend with one command, or to a file
  with no dependency installed, and nothing already shipped ships twice.

## Current baseline

- `trace_export.py` selects stored spans, serialises OTLP/JSON, posts over
  OTLP/HTTP, and marks exported spans; it is reachable only by invoking the
  module directly.
- `driver.zsh telemetry_enabled` already honours `telemetry.enabled`, but
  `config.json` ships no `telemetry` block and nothing reports the setting.
- `pm_flow.sh` has no `trace` command.

## Deliverables

- `pm-flow trace export --otlp <url> [--header k=v]`, `pm-flow trace export
  --file <path>`, `pm-flow trace status`.
- A `telemetry` block in `config.json`: `enabled`, `otlp_endpoint`, `headers`,
  read by the `trace` command for its defaults.
- `tests/trace_commands_test.sh`.

## User-visible scenarios

1. After a run, `pm-flow trace export --otlp http://localhost:4318` prints the
   number of spans the collector acknowledged; running it again prints 0.
2. On a machine with no OpenTelemetry SDK installed, `pm-flow trace export
   --file run.json` writes OTLP/JSON that a stock collector accepts.
3. With `telemetry.enabled: false`, a run completes and records no spans, and
   `pm-flow trace status` says so.

## Interfaces produced

- The `trace` command surface and the `telemetry` config block.
- `trace_export.py` checkpointing: a span is marked exported only after a 2xx
  acknowledgement.

## Interfaces consumed

- `spans` and `span_events` in the store; attribute names as recorded
  (`otel-semconv` owns them).

## Scope

- In: command routing, config block, checkpointing, file and HTTP delivery,
  the test.
- Out: what is recorded and how it is named; backend-specific attributes.

## Non-goals

- A vendor default endpoint.
- Deleting or rewriting stored spans on any failure.

## Priority

- must-have: the recording layer exists and is invisible; this is what makes
  it usable.

## Owned paths

- `template/.agentic/pm_flow/pm_flow.sh`
- `template/.agentic/pm_flow/config.json`
- `template/.agentic/pm_flow/trace_export.py`
- `tests/trace_commands_test.sh`

## Dependencies

- None.

## Constraints and fixed decisions

- `pm_flow.sh` edits are limited to adding the `trace` command routing;
  anything wider is a boundary conflict to report.
- A failed or refused export leaves every span retryable; telemetry failure
  never aborts a run.
- Phoenix (`:6006/v1/traces`), Jaeger (`:4318/v1/traces`) and Langfuse
  (`/api/public/otel`, Basic auth) are documented endpoints, none a default.

## Acceptance

- A1: `pm-flow trace export --otlp <url>` against a local OTLP/HTTP receiver in
  the test delivers every unexported span and prints the acknowledged count; a
  second run prints 0 and sends nothing.
- A2: `pm-flow trace export --file <path>` with no OpenTelemetry package
  importable writes OTLP/JSON that `to_otlp_json`'s schema check and an
  independent JSON-schema check both accept.
- A3: After a receiver answers 5xx or times out, the same spans are delivered
  by the next run; none is marked exported.
- A4: With `telemetry.enabled: false`, one stub tick completes, the store
  gains no span, and `pm-flow trace status` reports recording disabled.
- A5: `zsh tests/trace_commands_test.sh`, `zsh tests/pm_flow_test.sh` and
  `zsh tests/packaged_layout_test.sh` exit 0.

## Rejection conditions

- A telemetry failure can abort a run.
- An endpoint is defaulted to one vendor.
- A span is marked exported before acknowledgement.
- A file outside Owned paths is modified, or `pm_flow.sh` is changed beyond
  the routing and config read.

## Open questions

- None.
