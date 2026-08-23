# trace-commands section PM state

## Current task

- None while the hard dependency `otel-semconv` is incomplete.

## Completed tasks and evidence

- Nothing attempted. Packaging is complete, so the old layout blocker is gone.

## Active decisions

- `trace_export.py` owns selection, OTLP serialization, delivery, and checkpoints;
  `pm_flow.sh` only routes commands.
- Successful acknowledgement, not an attempted request, marks spans exported.
- File and HTTP paths serialize the same vendor-neutral payload.

## Blockers

- OTel semantic mapping/emission must land before export E2E can assert the
  payload. This replaces the expired packaging-layout blocker.

## Next eligible task

- T1 after otel-semconv: select unexported spans and prove checkpoint idempotence.
