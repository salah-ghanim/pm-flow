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
- `template/.agentic/pm_flow/agent_exec.sh`
- `template/.agentic/pm_flow/driver.zsh`
- `template/.agentic/pm_flow/telemetry.py`
- `tests/fixtures/codex_events_real.jsonl`
- `tests/codex_usage_test.sh`

### Dependencies
- green-suite

### Why this exists

`plan.md` leads with cost, tokens, cycles-to-done, rescue rate and escalation
depth, because those are the metrics where the effect size is large and the
measurement is not a matter of opinion. A run whose codex dispatches record no
tokens cannot be compared against anything. This section is not about a file
appearing; it is about the measurement layer having numbers in it.

### Acceptance

Stable IDs `A1`–`A6` refer to the bullets below in order.

Stated as outcomes in the running system, because the previous version of this
brief was not and the section passed while delivering nothing usable.

- After a **real** `codex` dispatch, that attempt's token counts are readable
  from the store: input, output, cached input and reasoning tokens, matching
  what codex reported. Not a file on disk - the recorded run.
- `pm_flow.sh cost` attributes non-zero spend or tokens to a codex dispatch, so
  a person can see what a codex-bound role cost without reading a JSONL file.
- Token recovery is proven against a stream captured from a real codex, held as
  a fixture, not against a double that emits whatever the parser expects. Real
  codex reports usage on `turn.completed`; it does not emit
  `total_token_usage`, and reading only the latter was how this came to record
  nothing.
- A codex dispatch whose only output is the event stream is not killed as
  stalled.
- `classify_failure` still reads stderr only; the event stream cannot cause a
  false `permanent` classification.
- The suite still passes.

### Integration requirement

Event parsing is insufficient unless `driver.zsh` brackets the real dispatch
with `telemetry_begin_attempt` and `telemetry_end_attempt`. The tracked replay
must prove both that a dispatch still occurs and that its completed attempt is
stored; a parser-only test cannot satisfy A1 or A2.

### Rejection conditions
- The event stream is written into the attempt log, where it can be misread as
  an error by failure classification.
- Liveness is left reading only stdout and stderr, so adding `--json` makes a
  working Codex dispatch look stalled.
- Any file outside the Owned paths list is modified.
