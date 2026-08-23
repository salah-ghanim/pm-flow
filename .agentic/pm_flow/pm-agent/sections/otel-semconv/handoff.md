# otel-semconv section handoff

## Outcome

Rebaselined into mapping, real emission, stock-backend proof, and revision-change
tasks. No standard-convention implementation exists yet.

## Decisions

- Pin one developmental GenAI revision in one mapping module.
- Unknown fields use a pm-flow namespace; no invented `gen_ai.*` names.
- Mapping fixtures alone cannot prove emitted/back-end-visible telemetry.

## Interfaces

- Planned: `semconv.py` maps attempt/span data and carries the revision on output.

## Risks

- Telemetry/driver paths remain owned by codex-usage. T2 cannot be assigned until
  those interfaces and paths are released.

## What is unproven

- All A1–A6 outcomes; current private telemetry is not acceptance evidence.

## Next action

After codex-usage completes, scope workplan T1.
