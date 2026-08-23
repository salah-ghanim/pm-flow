# agent-bindings section handoff

## Outcome

Rebaselined into four workplan tasks. No implementation exists; T1 (ACP
transport contract) and T2 (MCP server) are independently assignable.

## Decisions

- ACP and MCP are adapters to the existing flow, not new state machines.
- Existing CLI bindings are the compatibility baseline.
- Dispatch integration is a later ownership transfer, explicitly T3.

## Interfaces

- Planned: `acp.py` session/result/access contract and `mcp_server.py` typed tools.

## Risks

- The current owned paths cannot satisfy the E2E/store criteria. Scoping T3
  before validated ownership transfer would create an impossible assignment.

## What is unproven

- All A1–A5 outcomes; nothing has been implemented.

## Next action

Scope workplan T1 only.
