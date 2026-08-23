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

- Status: pending.
- Outcome: `acp.py` completes initialize → session → prompt → result against
  a protocol-faithful test agent shipped in the test, distinguishes malformed
  frames, missing capability, cancellation and child exit, and reports
  whether the tier is enforceable from the agent's declared capabilities.
- Paths: `src/pm_flow/acp.py`, `tests/agent_bindings_test.sh`.
- Reuse: the envelope fields and timeout semantics in `agent_exec.sh`.
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
- Reuse: `write_access_settings`, the envelope writer, T1's test agent.
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
