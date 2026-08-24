# trace-commands workplan

## Design summary

- `trace_export.py` keeps selection, serialisation, delivery and checkpoints,
  and reads the `telemetry` block for defaults; `pm_flow.sh` only routes
  `trace` to it.
  Acknowledgement marks a span exported; anything else leaves it retryable.
- `--protocol http` posts `to_otlp_json`'s payload with `urllib`, not the SDK.
  The SDK's `export()` returns SUCCESS/FAILURE and retries inside itself, so it
  cannot witness the 2xx the checkpoint is defined against; a stdlib POST also
  makes HTTP delivery dependency-free like `--file`, and lets the test run a
  `http.server` receiver that scripts its own status codes. The SDK path stays
  for `--protocol grpc` only.

## Interfaces and data changes

- `pm-flow trace export --otlp <url> [--header k=v]…`, `--file <path>`;
  `pm-flow trace status`.
- `config.json` `telemetry: {enabled, otlp_endpoint, headers}`.
- No schema change; `spans.exported_at` already exists.
- `export_to_otlp` gains an HTTP path built on `urllib.request`; its return
  becomes the acknowledged count rather than a boolean, so OTLP
  `partialSuccess.rejectedSpans` can be subtracted from what is marked.

## Task T1 — Checkpoint on acknowledgement

- Status: done (cycle 002). The suite now runs, so A1 and A3 close here.
  Historical note on why it was carried: cycle 001 delivered
  `trace_export.py` in full and the review verified A1 and A3 against a live
  loopback receiver, asserting on the receiver's recorded bodies. The delivered
  `tests/trace_commands_test.sh` dies at line 218 on zsh's read-only `status`,
  so A3 never runs and the failing run bypasses `trap cleanup EXIT`. The rename
  is one token; it is folded into T2 rather than spent as its own cycle.
- Outcome: `trace_export.py` marks spans exported only after a 2xx; 4xx, 5xx
  and timeouts leave them selected for the next run; the command prints the
  acknowledged count.
- Paths: `template/.agentic/pm_flow/trace_export.py`,
  `tests/trace_commands_test.sh`.
- Reuse: `fetch_spans`, `mark_exported`, `to_otlp_json`, `parse_headers`;
  `export_to_otlp`'s HTTP branch is replaced by the `urllib` POST, its gRPC
  branch and SDK import stay.
- Acceptance IDs: A1, A3.
- Validation: `zsh tests/trace_commands_test.sh` — a standard-library receiver
  scripted to answer 200, then 503, then timeout: first run exports N and
  prints N, second prints 0, after 503 and timeout the spans remain unexported
  and a later 200 run delivers them; a mutation marking before the response
  fails.
- Depends on: None.

## Task T2 — Command surface and config block

- Status: done (cycle 002, accepted). A1, A2, A3 and A4 met; `zsh
  tests/trace_commands_test.sh` exits 0 with the receiver-backed cases running.
- Outcome: `tests/trace_commands_test.sh` runs to completion, so T1's A1 and A3
  cases execute; `pm-flow trace export|status` route to `trace_export.py`,
  which reads `telemetry.otlp_endpoint` and `headers` as defaults; with
  `telemetry.enabled: false` a tick records no span and `status` reports it;
  `--file` works with no OpenTelemetry package importable.
- Paths: `template/.agentic/pm_flow/pm_flow.sh`, `template/.agentic/pm_flow/config.json`,
  `template/.agentic/pm_flow/trace_export.py`, `tests/trace_commands_test.sh`.
- Reuse: `driver.zsh telemetry_enabled` and `telemetry_autoexport`, which
  already reads `telemetry.otlp_endpoint` (both unchanged); the `case "$cmd"`
  block and `usage` heredoc in `pm_flow.sh`; the stub harness from
  `tests/pm_flow_test.sh`.
- Carried in from T1: rename the read-only `status` variable at
  `tests/trace_commands_test.sh` lines 218/220/221, 230/232/233, 250/252/253;
  and make `trace export` stdout report what was *marked*, not what the
  receiver acknowledged — on partial success cycle 001 printed
  `exported 2 span(s)` while marking none, which reads wrong to a scripted
  caller even though stderr corrects it.
- Acceptance IDs: A1, A2, A3, A4.
- Validation: `zsh tests/trace_commands_test.sh` — the suite exits 0 with A1 and
  A3 executing; a venv without the SDK writes a file that passes both schema
  checks; a disabled-telemetry tick records no span and `status` prints
  `recording: disabled`; a mutation that raises inside the exporter does not
  change the tick's exit status.
- Depends on: T1.

## Task T3 — End to end through the installed command

- Status: pending.
- Outcome: a packaged install records a stub run, exports to the receiver and
  to a file, reports counts, and re-exports nothing.
- Paths: `tests/trace_commands_test.sh`.
- Reuse: the harness in `tests/packaged_layout_test.sh`.
- Acceptance IDs: A1–A5.
- Validation: `zsh tests/trace_commands_test.sh`, `zsh tests/pm_flow_test.sh`,
  `zsh tests/packaged_layout_test.sh` exit 0.
- Depends on: T2.

## Integration and end-to-end validation

- T3 proves scenarios 1–3 through `.venv/bin/pm-flow`.

## Risks and rollback

- A checkpoint written on a failed send silently loses spans; T1's failure
  matrix is the guard. Rollback removes the `trace` routing; stored spans are
  untouched.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T3 | Receiver count equals marked count; rerun prints 0 |
| A2 | T2, T3 | SDK-less file passes both schema checks |
| A3 | T1, T2 | 5xx/timeout leave spans retryable |
| A4 | T2 | Disabled recording: no span, status says so |
| A5 | T3 | Three suites exit 0 |
