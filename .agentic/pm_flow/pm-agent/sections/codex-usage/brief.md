### Objective
Capture Codex token usage and hand every child agent a traceparent, so a Codex
dispatch is described as fully as a Claude one.

### Scope
Codex emits OTLP under a private `codex.*` schema with no `gen_ai.*` attributes,
much of it log-only, so a span-oriented backend shows nothing useful. Its
response file holds only the last message, so token counts are unreachable there
too. `codex exec --json` does emit a `token_count` event carrying
`total_token_usage`, and `telemetry.py usage_from_codex_events` already parses it.

Wire it up: run Codex with `--json`, send its event stream to its own file next
to the response envelope as `<name>.events.jsonl`, and keep stderr going to the
attempt log so failure classification is unchanged. Export `TRACEPARENT` into the
dispatched process.

### Priority
- must-have. Without this, half the roles in a default install report no tokens
  at all and cross-model comparison is impossible.

### Owned paths
- template/.agentic/pm_flow/agent_exec.sh

### Dependencies
- green-suite

### Acceptance
- A Codex dispatch writes a non-empty `.events.jsonl` beside its response.
- The events file is included in the liveness computation, so a Codex dispatch
  whose only output is the event stream is not killed as stalled.
- `classify_failure` still reads stderr only; a JSONL event stream cannot cause
  a false `permanent` classification.
- The suite still passes.

### Rejection conditions
- The event stream is written into the attempt log, where it can be misread as
  an error by failure classification.
- Liveness is left reading only stdout and stderr, so adding `--json` makes a
  working Codex dispatch look stalled.
- Any file outside agent_exec.sh is modified.
