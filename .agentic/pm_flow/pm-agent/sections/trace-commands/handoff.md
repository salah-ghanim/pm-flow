# trace-commands section handoff

## Outcome

The expired packaging-layout blocker is removed. The section is rebaselined
against the packaged engine and now waits only for otel-semconv.

## Decisions

- `trace_export.py` owns selection, serialization, delivery, and checkpoints.
- File and HTTP exports share one payload; only acknowledged spans are marked.
- Export/telemetry failures never abort the underlying product run.

## Interfaces

- Planned: `pm_flow.sh trace export --file|--otlp` and
  `telemetry.enabled` config.

## Risks

- Starting before semantic-convention emission lands would validate the old
  private payload and bake drift into the public export contract.

## What is unproven

- All A1–A5 outcomes; nothing has been implemented.

## Next action

Keep planned/waiting on otel-semconv, then scope workplan T1.
