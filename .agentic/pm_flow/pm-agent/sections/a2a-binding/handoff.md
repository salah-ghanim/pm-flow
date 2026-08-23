# a2a-binding section handoff

## Outcome

Rebaselined into protocol mapping, inbound binding, outbound service, and
authenticated regression tasks. No implementation exists.

## Decisions

- A2A is remote HTTP transport; Agent Client Protocol remains local subprocess
  transport and MCP remains a tool/control surface.
- Inbound and outbound E2Es are separate and require an independent peer.

## Interfaces

- Planned: one A2A revision/state/access mapping in `a2a.py` built on the
  agent-bindings adapter contract.

## Risks

- Integration ownership must be transferred after agent-bindings; editing its
  paths concurrently would invalidate section isolation.

## What is unproven

- All A1–A7 outcomes; nothing has been implemented.

## Next action

Wait for agent-bindings, then scope workplan T1.
