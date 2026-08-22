# codex-usage section PM state

## Objective

- Make Codex dispatches retain their JSONL event stream for token accounting,
  treat that stream as liveness without exposing it to failure classification,
  and pass the dispatch trace context to the child process.

## Owned paths

- `template/.agentic/pm_flow/agent_exec.sh`

## Plan

- Cycle 001: validate the Codex dispatch path with a fake `codex` executable and
  correct only `agent_exec.sh` if the direct probe exposes a gap.
- Review with the same direct probe, the full suite, and mutations that remove
  JSON mode, event-stream liveness, stderr isolation, and trace propagation.

## Decisions and evidence

- No previous cycle has been accepted; there is no section work to commit before
  cycle 001. Current section diffs are dispatch bookkeeping only.
- Commit `d5b48ee` already added `codex exec --json`, a response-adjacent
  `EVENTS_FILE`, stdout/stderr separation, and event-file mtime participation in
  `run_attempt` for a separate observability objective. These are candidates to
  validate and reuse, not evidence that this section is complete.
- `telemetry.py usage_from_codex_events` and the driver's
  `telemetry_end_attempt` event-file lookup already consume
  `<response-without-.json>.events.jsonl`; they are outside this section and must
  not be rebuilt or changed.
- The green-suite handoff states that `zsh tests/pm_flow_test.sh` completes with
  six stable PASS labels and identifies no remaining dependency work.

## Current assignment

- Exercise the current Codex path through `agent_exec.sh` using a temporary fake
  CLI that records argv and `TRACEPARENT`, emits JSONL while stderr and the final
  response remain quiet, and emits failure-looking narration in JSONL. Preserve
  the current implementation if it passes; otherwise make the smallest fix in
  the owned file.

## Dependencies

- `green-suite`: satisfied by its handoff; the full suite is runnable and stable.
