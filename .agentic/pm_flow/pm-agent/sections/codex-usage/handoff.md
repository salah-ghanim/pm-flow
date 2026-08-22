## Outcome

Codex dispatches now retain their JSONL event stream for token accounting, count event-file activity as liveness, propagate `TRACEPARENT`, and keep event content out of failure classification. The change is committed in `07848d3`, integrated into `main`, and the full nine-group suite passed.

## Decisions

- Run Codex as `exec --json` and store stdout separately from diagnostics.
- Declare `events_seen` once at function scope; redeclaring it in the zsh poll loop leaked values onto supervisor stdout.
- Disable zsh `BG_NICE` at startup, preventing the background `nice(2)` call and its sandbox warning rather than filtering stderr.
- Reuse `telemetry.py usage_from_codex_events`; no second token parser was introduced.

## Interfaces

- A Codex response at `<name>.json` has an event stream at `<name>.events.jsonl`; telemetry consumers depend on that adjacency and JSONL format.
- Codex stdout goes only to the events file. Codex stderr remains the attempt log and sole input to `classify_failure`.
- The final response remains the file supplied through Codex `-o`.
- The dispatched process inherits the caller's exact `TRACEPARENT`.
- Supervisor stdout remains exactly `role`, `cli`, `response`, and `attempts` records; callers may parse that contract.

## Risks

- Codex CLI event schemas or `--json`/`-o` behavior may change; a real dispatch producing missing token totals, malformed/empty JSONL, or no final response would reveal it.
- Event liveness was tested with a short synthetic cadence; a real long-running dispatch could still stall if Codex stops emitting events beyond the configured threshold.
- The focused probes are temporary, not tracked regression tests. Future stdout leakage, re-enabled `BG_NICE`, or classifier contamination would be revealed by rerunning equivalent probes or adding permanent coverage.

## What is unproven

- No real Codex CLI or service was contacted. `exec --json`, `-o`, event capture, token recovery, and trace propagation were demonstrated with a fake executable. One real authenticated dispatch, verifying argv-compatible execution, a non-empty adjacent event file, parsed totals, final response, and observed trace context would settle this.
- Liveness was demonstrated once with four seconds of synthetic once-per-second JSONL against a two-second threshold, not with a production-length Codex run. A real run exceeding its stall threshold while only the event stream changes would settle this.

## Next action

The product officer can treat `codex-usage` as complete and allow downstream telemetry and dispatch work to depend on the interfaces above. Add a real-Codex smoke check when credentials and an execution environment are available; reopen this section only if that check contradicts the validated contract.
