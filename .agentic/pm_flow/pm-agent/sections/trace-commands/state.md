# trace-commands section PM state

## Current task

- T3, cycle 003 — the packaged end-to-end run and A5.

## Completed tasks and evidence

- T1 — A1, A3. `zsh tests/trace_commands_test.sh` (cycle 002 review, full
  receiver-backed mode) exits 0. A1: first export prints `exported 3 span(s)`,
  `SELECT COUNT(*) … exported_at IS NOT NULL` is 3, the receiver recorded one
  request whose `resourceSpans[0].scopeSpans[0].spans` carries three entries
  including the seeded `fixture-event`; the second run prints `exported 0
  span(s)` and the receiver's request count stays at 1. A3: 503 and a 0.05 s
  timeout against a 0.4 s responder each print `exported 0 span(s)`, exit
  non-zero, leave `exported_at` null on every row, and the retry at 200
  delivers the same three span ids. The suite's own mutant — checkpointing
  before delivery — is caught by the timeout case.
- T2 — A1, A2, A3, A4. Same command, exit 0. `pm-flow trace export|status`
  route through `pm_flow.sh`; `config.json` ships `telemetry: {enabled: 1,
  otlp_endpoint: "", headers: {}}` and the command takes its endpoint and
  headers from it (the configured-header case only answers 200 when
  `X-Trace-Config: configured` arrives), while `--otlp` still wins over a
  configured endpoint pointed at a dead port. A2: in a venv with a poison
  `opentelemetry/__init__.py` that raises `ImportError`, `trace export --file`
  prints `exported 3 span(s)` and the written line passes both
  `validate_otlp_json` and the test's independent JSON-Schema subset checker.
  A4: a stub tick with `telemetry.enabled: false` exits 0 and leaves the span
  count unchanged, and `pm-flow trace status` prints `recording: disabled`;
  an exception raised from inside the exporter during a real tick still leaves
  the tick's exit status 0.
- Regressions: `zsh tests/pm_flow_test.sh` and `zsh
  tests/packaged_layout_test.sh` both exit 0.

## Evidence in hand, not yet closing an ID

- A5 stays open until T3 proves the three suites through `.venv/bin/pm-flow`.

## Active decisions

- Acknowledgement, not attempt, marks a span exported.
- `pm_flow.sh` is owned for the `trace` routing and its `usage` line only.
- HTTP delivery is a stdlib `urllib` POST of OTLP/JSON, not the SDK exporter.
  Probed 2026-08-24: `ls .venv/lib/python3*/site-packages | grep -i
  opentelemetry` returns nothing, so the SDK is absent here, and the SDK's
  `export()` reports only SUCCESS/FAILURE — it cannot witness the 2xx that A1
  and A3 are written against. `--protocol grpc` still uses the SDK.
- `driver.zsh telemetry_autoexport` already reads `telemetry.otlp_endpoint`
  from `config.json` and posts on the way out. T2 adds the block that setting
  reads from; it does not invent the key or change the driver.
- On partial success, stdout must report spans *marked*, not spans
  acknowledged. Cycle 001 printed `exported 2 span(s)` while marking none;
  stderr corrected it, but stdout is what a scripted caller reads.
- A one-token fix is not a cycle. T1's `status` rename is folded into T2 rather
  than assigned on its own.
- The suite keeps a `--offline` argument that runs A2 and A4 only. It is
  opt-in, the default invocation runs everything, and offline mode says on
  stdout that A1/A3 did not run. Nothing may invoke the suite with it — a CI
  entry point that does would make the receiver-backed cases silently absent.

## Blockers

- None. The developer sandbox refuses a loopback `bind()`
  (`PermissionError: [Errno 1] Operation not permitted` from
  `HTTPServer(("127.0.0.1", 0), …)`), reported in cycles 001 and 002. This is a
  developer-role harness restriction only: the review role runs the same suite
  unchanged and every receiver-backed case passes, so the sandbox shapes what
  the developer can self-verify, not whether the work is correct. Assign
  receiver-backed acceptance expecting the developer to report the bind error
  and the review to execute those cases. Note the earlier state claim that the
  PM sandbox also refuses the bind was wrong: only a bare `python3 -c` needed
  approval; `zsh tests/trace_commands_test.sh` binds and passes.

## Known gaps, not blocking T2

- `trace status` counts every span with `exported_at IS NULL`, including spans
  with no `ended_at`, while `trace export` only ships finished ones. During a
  live run `status` can therefore report more unexported spans than the next
  export will send. Fold a `ended_at IS NOT NULL` filter, or a separate
  in-flight line, into T3.

## Next eligible task

- T3 — the packaged end-to-end run through `.venv/bin/pm-flow`, for A5.
