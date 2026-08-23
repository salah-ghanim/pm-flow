## Objective

- Make pm-flow drivable over MCP, and let a seat bind any ACP-compatible agent
  rather than one of three hardcoded CLIs.

## Scope

`plan.md` says pm-flow must be "drivable over MCP and able to bind any
ACP-compatible agent", and its principles say to adopt a standard wherever one
exists rather than write our own. Neither half exists today: `build_command` in
`agent_exec.sh` has a `case` with exactly three arms — `claude`, `codex`,
`copilot` — and each arm hand-writes that vendor's flags for effort, model,
working root and permissions. A fourth agent means a fourth arm, and an agent
nobody here has heard of means a patch.

Two halves, and they are independent enough to sequence:

- **ACP inbound.** A seat binds an agent over the Agent Client Protocol, so the
  three `case` arms become one of several transports rather than the whole
  world. The three tiers of access (`write`, `scoped`, `read`) must survive the
  translation or be reported as unenforceable on that binding, the way codex's
  scoped tier already is.
- **MCP outbound.** pm-flow's own commands — status, next, tick, the section
  registry, the store — exposed as MCP tools, so another agent can drive a
  project without shelling out to `pm_flow.sh`.

## Priority

- must-have for the plan as written; the last section to schedule of those that
  are. Nothing else depends on it, and it is the largest unknown.

## Owned paths

- `src/pm_flow/acp.py`
- `src/pm_flow/mcp_server.py`
- `tests/agent_bindings_test.sh`

New paths only. `agent_exec.sh` is where the three-armed `case` lives and is
the file this section most obviously wants, but it belongs to `codex-usage`,
which is reopened and moving. Build the binding and the server here, prove them
here, and hand `codex-usage` a bounded change to make the `case` call into it
rather than editing that file from two sections at once.

## Dependencies

- None.

It reads no packaged layout and changes none. Waiting on `packaging` would be
sequencing by habit rather than by need.

## Acceptance

Stable IDs `A1`–`A5` refer to the bullets below in order.

- A seat binds an ACP agent and completes a cycle end to end.
- The three existing CLI bindings still work, unchanged in behaviour.
- The access tier is either enforced on an ACP binding or reported as
  prompt-level only, per binding, the way codex is today.
- pm-flow's commands are reachable over MCP and a second agent drives a project
  through them without a shell.
- The store records which binding and which transport produced each attempt, so
  a comparison can tell two transports apart.

## Rejection conditions

- Adding a fourth vendor still means adding a `case` arm.
- An ACP binding silently gets more access than its tier allows.
- MCP exposure bypasses the budget ceiling or the driver lock.
- A persona names a transport. A persona names no model and no vendor; that is
  what makes it portable.
