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

- Cycle 001 is `NO_GO`; no section implementation has been accepted or
  committed. The direct fake-Codex probe independently proved JSON mode, exact
  trace propagation, response-adjacent events, event-only liveness, token
  parsing, and stderr-only network classification, but exited 1 because the
  review sandbox wrote `nice(5) failed: operation not permitted` to the
  supervisor stderr and the probe required that stream to be empty.
- Cycle 001's disposable mutation restored the loop-local `events_seen`
  declaration and the stdout-contract assertion caught four leaked
  `events_seen=<mtime>` lines. The declaration move therefore fixes a real
  defect, but cannot be accepted while the assigned direct probe fails.
- The independent full suite exited 0 with all nine current PASS groups.
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

- Cycle 001 is rejected. Scope cycle 002 around the observed zsh background-job
  niceness warning and an acceptance probe that directly distinguishes child
  attempt-log stderr from supervisor stderr. Preserve the proven declaration
  fix and all existing Codex event/trace behavior; do not expand outside
  `agent_exec.sh`.

## Dependencies

- `green-suite`: satisfied by its handoff; the full suite is runnable and stable.

## Review history

- Cycle 001: `NO_GO`. Full suite passed and mutation was caught; direct probe
  returned 13 passed, 1 failed because sandbox-denied `nice(5)` polluted the
  stderr stream its harness required to be empty. No commit was made.
