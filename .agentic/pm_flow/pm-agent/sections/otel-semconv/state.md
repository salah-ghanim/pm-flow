# otel-semconv section PM state

## Current task

- None while the hard dependency `codex-usage` remains incomplete.

## Completed tasks and evidence

- None. Workplan T1–T4 is defined; current telemetry/store fields are inputs,
  not evidence that conventional spans are emitted.

## Active decisions

- Pin one developmental GenAI convention revision in `semconv.py`.
- Standard literals appear only in the mapping module; pm-flow extensions use a
  visibly non-standard namespace.
- Mapping tests, real emission, and stock-backend visibility are distinct gates.

## Blockers

- T2 needs telemetry/driver ownership after codex-usage's tracked replay and
  canary settle those interfaces. T1 can be scoped once the dependency releases.

## Next eligible task

- T1 after codex-usage: implement the revision/mapping table and stray-literal
  guard from upstream convention data.
