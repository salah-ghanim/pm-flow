# agent-bindings workplan

## Design summary

- One ACP client module; one new `case` arm in `agent_exec.sh` that calls it
  and writes the same response envelope the other arms write; an MCP server
  that is a thin tool façade over the installed command. Existing arms are
  untouched.

## Interfaces and data changes

- `acp.run(...)`, binding `cli: acp` with `cli_params.command`; MCP tools
  `status`, `next`, `tick`, `list_sections`, `cost`. No schema change.

## Task T1 — ACP client and test agent

- Status: done (cycle 001, accepted with changes carried into T2).
- Outcome: `acp.py` completes initialize → session → prompt → result against
  a protocol-faithful test agent shipped in the test, distinguishes malformed
  frames, missing capability, cancellation and child exit, and reports
  whether the tier is enforceable from the agent's declared capabilities.
- Paths: `src/pm_flow/acp.py`, `tests/agent_bindings_test.sh`.
- Reuse: the envelope fields and timeout semantics in `agent_exec.sh`.
- Interface to T2: a machine-readable outcome channel, not prose.
  `classify_failure` (`:677`) is a regex matcher over the attempt log, so any
  reason it is left to infer falls through to `unknown`; T1 must hand T2 the
  reason directly.
- Acceptance IDs: A3, A6.
- Validation: `zsh tests/agent_bindings_test.sh` — one successful exchange
  returns the agent's text; each failure mode yields a distinct
  `failure_reason`; an agent declaring no sandbox capability yields
  `enforceable=false`.
- Depends on: None.

## Task T2 — The `acp` arm in agent_exec.sh

- Status: pending.
- Outcome: a binding with `cli: acp` dispatches through `acp.py`, writes the
  standard response envelope, records `access: enforced|prompt-level` before
  the agent runs, and a full section cycle completes with an ACP developer.
- Paths: `template/.agentic/pm_flow/agent_exec.sh`, `tests/agent_bindings_test.sh`.
- Reuse: `write_access_settings`, `write_response`, `classify_failure`
  (`:677`), T1's test agent. Three edits the cycle-001 probes make
  unavoidable, all inside this task: the resolver block ending at `:365`
  prints 12 fields and no `cli_params`, so add a 13th single-line JSON field
  (tolerating its absence, per `pm_flow_test.sh:616`) and correct the "always
  last" comment at `:358`; the `command -v "$AGENT_CLI"` guard at `~:869`
  must probe `cli_params.command[0]` for an `acp` binding; the arm must reach
  `telemetry.py attempt-start|attempt-end` as the others do, or `cost` never
  shows `cli=acp` (store-ledger handoff). `enforced`/`prompt-level` appear
  nowhere in `template/`, `src/` or `tests/` today — this is new surface.
- Carried change from T1's cycle-001 review: `acp.py` prints
  `failure_reason="acp_capability_missing"` on a **successful** exchange
  (exit 0, real `text`, `usage` populated) whenever `enforceable` is false.
  The arm must gate on the client's exit status first and read
  `failure_reason` only for a non-zero exit; an exit-0 line is never a
  failure. `enforceable=false` means record `access: prompt-level` and
  dispatch, per the brief's constraint — not a `permanent` classification.
  Either enforce that ordering in the arm or change the success line to
  `failure_reason="none"` and let the arm read `enforceable`.
- Also from that review: `acp.py` answers every
  `session/request_permission` with `outcome: cancelled`. That is a policy
  the tier should drive; decide it here and cover it in the test, or the
  `write` tier silently denies an agent that asks.
- Acceptance IDs: A1, A2, A3, A5.
- Validation: `zsh tests/agent_bindings_test.sh` — cycle reaches `GO`; access
  log shows the record before the attempt start; `pm-flow cost` lists
  `cli=acp`; `zsh tests/pm_flow_test.sh` and the stub suites exit 0.
- Depends on: T1.

## Task T3 — MCP server

- Status: pending.
- Outcome: `python -m pm_flow.mcp_server` serves the five tools over stdio;
  each invokes the installed `pm-flow` command and returns its output or a
  tool error.
- Paths: `src/pm_flow/mcp_server.py`, `tests/agent_bindings_test.sh`.
- Reuse: `pm_flow.cli`; no state machine code.
- Acceptance IDs: A4, A6.
- Validation: `zsh tests/agent_bindings_test.sh` — a JSON-RPC client script
  lists exactly five tools, drives a stub project to `done` via `tick`, and a
  `tick` while the driver lock is held returns a tool error naming the lock.
- Depends on: None.

## Task T4 — End to end through the installed command

- Status: pending.
- Outcome: a packaged install binds an ACP developer, is driven by the MCP
  client to a terminal section, and `cost` distinguishes the two transports.
- Paths: `tests/agent_bindings_test.sh`.
- Reuse: the harness in `tests/packaged_layout_test.sh`.
- Acceptance IDs: A1–A6.
- Validation: `zsh tests/agent_bindings_test.sh`, `zsh tests/pm_flow_test.sh`,
  `zsh tests/packaged_layout_test.sh` exit 0.
- Depends on: T2, T3.

## Integration and end-to-end validation

- T4 proves scenarios 1–3 through `.venv/bin/pm-flow`.

## Risks and rollback

- ACP is young; the client is isolated in one module and the arm can be
  removed without touching the other three.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T4 | ACP developer cycle reaches `GO` |
| A2 | T2, T4 | Existing suites exit 0, arms unchanged |
| A3 | T1, T2 | Access record precedes the attempt |
| A4 | T3, T4 | MCP client drives a project to `done` |
| A5 | T2, T4 | `cost` shows `cli=acp` and `cli=claude` |
| A6 | T1, T3, T4 | Section suite exits 0 |
