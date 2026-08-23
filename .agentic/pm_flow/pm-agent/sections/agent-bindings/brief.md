## Objective

- A seat binds any agent that speaks the Agent Client Protocol, and pm-flow's
  own commands are reachable as MCP tools, so neither adding an agent nor
  driving a project needs a shell or a new `case` arm.

## Current baseline

- `agent_exec.sh build_command` has three arms — `claude`, `codex`, `copilot`
  — each hand-writing that vendor's flags for effort, model, working root and
  permissions. The access tiers `write`, `scoped`, `read` are enforced on
  `claude`, prompt-level only on `codex` and `copilot`.
- `bindings.cli` references `clis(key)` and `cli_params` holds free-form JSON;
  `attempts` reference a binding.
- No MCP surface exists; another agent drives pm-flow by shelling out.

## Deliverables

- `src/pm_flow/acp.py`: an ACP client that spawns an agent, completes
  initialize/session/prompt/result over JSON-RPC on stdio, declares whether
  the requested access tier is enforceable, and supports cancellation.
- `agent_exec.sh` dispatching a seat whose binding `cli` is `acp` through it.
- `src/pm_flow/mcp_server.py`: `status`, `next`, `tick`, `list-sections`,
  `cost` as MCP tools, run as `python -m pm_flow.mcp_server`.
- `tests/agent_bindings_test.sh`.

## User-visible scenarios

1. `config.json` binds `developer` to `{"cli": "acp", "cli_params":
   {"command": ["my-agent", "--acp"]}}`; a section cycle completes through
   scope, develop and review with that seat.
2. A stock MCP client connects to `python -m pm_flow.mcp_server`, lists the
   tools, calls `status` then `tick`, and sees the section advance.
3. `pm-flow cost` shows the ACP attempt with `cli=acp`, distinguishable from a
   `claude` attempt on the same role.

## Interfaces produced

- Binding `cli: acp` with `cli_params.command`; stored as `bindings.cli='acp'`.
- `acp.run(prompt, params, access_tier) -> Result(text, enforceable, usage)`.
- MCP tool names `status`, `next`, `tick`, `list_sections`, `cost`.

## Interfaces consumed

- The response-envelope shape `agent_exec.sh` writes (`is_error`, `result`,
  `failure_reason`); `attempts`/`bindings` via `catalog.py` as they are.

## Scope

- In: the ACP client, its `agent_exec.sh` arm, the MCP server, the tests.
- Out: remote agents over HTTP (`a2a-binding`); store schema changes; the
  driver's state machine.

## Non-goals

- Re-implementing project or section transitions inside the MCP server.
- Removing the three vendor arms; they remain adapters to the same envelope.

## Priority

- must-have: the plan requires pm-flow to bind any ACP-compatible agent and to
  be drivable over MCP.

## Owned paths

- `src/pm_flow/acp.py`
- `src/pm_flow/mcp_server.py`
- `template/.agentic/pm_flow/agent_exec.sh`
- `tests/agent_bindings_test.sh`

## Dependencies

- None.

## Constraints and fixed decisions

- Transport identity is `bindings.cli` plus `cli_params`; no schema change.
- An ACP binding that cannot enforce the tier is dispatched only after
  `agent_exec.sh` has recorded `access: prompt-level` for it, as codex is
  today.
- The MCP server calls the installed `pm-flow` command; it holds no state and
  respects the driver lock and budget because the command does.

## Acceptance

- A1: In `tests/agent_bindings_test.sh`, a protocol-faithful ACP test agent
  bound to `developer` completes one cycle to `GO` through the public driver.
- A2: `zsh tests/pm_flow_test.sh` and `zsh template/.agentic/pm_flow/tests/run.zsh`
  exit 0 with the `claude`, `codex` and `copilot` arms unchanged in the
  arguments they build (asserted by the existing tests).
- A3: Dispatching a seat on an ACP binding records `access` as `enforced` or
  `prompt-level` in the run's access log before the agent runs; the test
  covers one agent of each kind.
- A4: A stock MCP client in the test (the reference Python SDK client or an
  equivalent JSON-RPC script) lists the five tools and drives a disposable
  project through `tick` to a terminal section state with no shell call of
  its own.
- A5: `pm-flow cost` on that project shows the ACP attempt with `cli=acp` and
  the `claude` attempt with `cli=claude`.
- A6: `zsh tests/agent_bindings_test.sh` exits 0.

## Rejection conditions

- A fourth vendor still means a fourth `case` arm.
- An ACP binding gets more access than its tier allows without the
  prompt-level record.
- The MCP server bypasses the budget ceiling or the driver lock.
- A persona names a transport.

## Open questions

- None.
