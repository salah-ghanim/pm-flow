# trace-commands workplan

## Design summary

- Expose the existing durable telemetry through bounded export commands. Use
  `trace_export.py` for selection/serialization/delivery and keep `pm_flow.sh`
  as command routing. Export checkpoints make successful delivery idempotent;
  telemetry failure remains non-fatal to product runs.

## Interfaces and data changes

- `pm_flow.sh trace export --file <path>` writes OTLP JSON.
- `pm_flow.sh trace export --otlp <url>` posts to a caller-selected endpoint.
- Config controls recording; the store records export checkpoints only after
  successful delivery.

## Task T1 — Rebaseline ownership and export selection

- Status: pending.
- Outcome: packaged-layout paths are authoritative and the exporter selects
  recorded, not-yet-exported spans without changing run records.
- Paths: `template/.agentic/pm_flow/trace_export.py`,
  `tests/trace_commands_test.sh`.
- Reuse: existing telemetry/store schema and trace IDs.
- Acceptance IDs: A3.
- Validation: seed two traces, export one batch, rerun selection, and mutation-
  remove checkpointing to prove the duplicate assertion fails.
- Depends on: packaging (complete), otel-semconv.

## Task T2 — Add file export and recording toggle

- Status: pending.
- Outcome: file export writes valid OTLP JSON without network dependencies;
  `telemetry.enabled: false` suppresses recording without affecting the run.
- Paths: `pm_flow.sh`, `config.json`, `trace_export.py`,
  `tests/trace_commands_test.sh`.
- Reuse: existing config loader and non-fatal telemetry wrappers.
- Acceptance IDs: A2, A4.
- Validation: JSON/schema assertions, disabled/enabled paired runs, and a broken
  exporter mutation that must not abort the underlying project run.
- Depends on: T1.

## Task T3 — Add vendor-neutral OTLP delivery

- Status: pending.
- Outcome: caller-selected OTLP HTTP endpoint receives a valid batch and the
  command reports exactly how many spans were acknowledged.
- Paths: `pm_flow.sh`, `trace_export.py`, `tests/trace_commands_test.sh`.
- Reuse: T1 selection/checkpointing and T2 serialization.
- Acceptance IDs: A1, A3.
- Validation: local HTTP collector captures request path/headers/body; 2xx marks
  exported, 4xx/5xx/timeout leaves spans retryable, no vendor URL is defaulted.
- Depends on: T2.

## Task T4 — Installed-artifact E2E and regression closeout

- Status: pending.
- Outcome: an installed `pm-flow` records, exports to file and HTTP, reports
  counts, retries failures, skips acknowledged spans, and still passes the suite.
- Paths: all owned trace paths and `tests/trace_commands_test.sh`.
- Reuse: packaged-layout harness and OTel backend fixture.
- Acceptance IDs: A1–A5.
- Validation: `zsh tests/trace_commands_test.sh`, packaged artifact scenario,
  duplicate/checkpoint mutation, telemetry-failure scenario, and full suite.
- Depends on: T3.

## Integration and end-to-end validation

- Export success is based on collector acknowledgement, not attempted writes.
  The file and HTTP paths must serialize the same semantic payload.

## Risks and rollback

- Endpoint failure must affect only the export command. Disable export/recording
  via config; never delete stored spans during rollback.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T3, T4 | Local OTLP endpoint receives batch and count |
| A2 | T2, T4 | Dependency-free OTLP JSON file |
| A3 | T1, T3, T4 | Acknowledged spans are not re-exported |
| A4 | T2, T4 | Disabled recording leaves run successful |
| A5 | T4 | Full suite completes |
