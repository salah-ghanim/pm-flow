# trace-commands section PM state

## Current task

- None. T1, T2 and T3 are done and A1–A5 are all closed. The workplan holds no
  unfinished task; the section needs a new one or none.

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
- T3 — A1, A2, A4, A5. `zsh tests/trace_commands_test.sh` in the cycle-003
  worktree exits 0 with the receiver running. Traced with `zsh -fx`, the
  packaged block observed: a wheel built offline from
  `tests/packaging-build-wheelhouse`, installed `--no-index --no-deps` into its
  own venv, `"$VENV/bin/python" -c 'import opentelemetry'` non-zero. A real
  `$VENV/bin/pm-flow tick` in an `install.sh`-created repo took the store from
  0 to 2 spans, 1 finished (`99b2d34aaedd17bc`) and 1 still open. A1: `pm-flow
  trace export --otlp` printed `exported 1 span(s)`, `SELECT COUNT(*) …
  exported_at IS NOT NULL` was 1, the receiver logged 1 request whose
  `resourceSpans[0].scopeSpans[0].spans` carried exactly `99b2d34aaedd17bc`;
  the second invocation printed `exported 0 span(s)` and the request count
  stayed 1. A2: after `reset_exports`, `--file` printed `exported 1 span(s)`
  from that SDK-less venv and the line passed `validate_otlp_json` and the
  suite's independent JSON-Schema subset checker. A4: with a synthetic open
  span added beside the run's own, `trace status` printed `unexported spans: 1`
  — equal to what the next export shipped — and `in-flight spans: 2`, with
  `recording:`, `endpoint:` and `exported spans:` unchanged; a second packaged
  repo at `telemetry.enabled: false` ticked to exit 0, kept span count at 0,
  and printed `recording: disabled`.
- Regressions and A5: `zsh tests/trace_commands_test.sh`, `zsh
  tests/pm_flow_test.sh` and `zsh tests/packaged_layout_test.sh` each exit 0
  in the cycle-003 worktree.
- Mutation: dropping `AND ended_at IS NOT NULL` from `print_status` and
  rerunning the suite fails at `FAIL: packaged status did not match the next
  export count` (exit 1), then the file restores to sha256
  `942ddd4c…b413f02`. The status fix is asserted, and the packaged block is
  proven to execute rather than to be skipped.

## Active decisions

- Acknowledgement, not attempt, marks a span exported.
- `trace status` reports five lines, not four. `unexported spans:` means
  finished-and-unexported — what the next export would ship — and
  `in-flight spans:` carries the open ones so the operator loses no count.
  The four original lines keep their wording; anything keying on them still
  works.
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
- The packaged venv is the SDK-less machine A2 names. `pyproject.toml:47`
  force-includes `template/.agentic/pm_flow` as `pm_flow/engine`, so
  `trace_export.py` travels in the wheel; the wheel declares no runtime
  dependencies and `packaged_layout_test.sh` installs it `--no-deps`, so no
  OpenTelemetry package can be present. That is a stronger A2 witness than
  cycle 002's poison-package venv, and it costs nothing extra once the install
  exists.

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

## Known gaps, outside this section

- A completed packaged tick leaves exactly one span with `ended_at IS NULL`
  (observed 2026-08-24: store held 2 spans, 1 finished, 1 open, after the tick
  returned 0). A span that never ends never exports, so the brief's objective —
  a recorded run ships — is not fully true of that span. `trace status` now
  surfaces it rather than hiding it, which is all this section can do:
  what is recorded and when a span closes belongs to the recording layer
  (`telemetry.py finish_span`, called from `cmd_run_end`/`cmd_span_end`), which
  `otel-semconv` owns. Raised in the handoff; not a trace-commands task.
- The packaged path exercises a single-span payload, because that is what one
  stub tick records. Multi-span batching and payload ordering are covered only
  by the checkout block's three seeded spans.
- `fetch_spans` orders by `started_at ASC` while the test's expected-id query
  orders by `started_at ASC, span_id ASC`. Identical today at one span; if a
  future tick records two finished spans with the same `started_at`, the id
  assertion could flap. Add the `span_id` tiebreak to `fetch_spans` if that
  is ever seen.

## Next eligible task

- None. The workplan is complete and A1–A5 are closed. Any further cycle needs
  a new task, not a continuation.
