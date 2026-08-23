# a2a-binding section PM state

## Current task

- None while the hard dependency `agent-bindings` is incomplete.

## Completed tasks and evidence

- None. Workplan T1–T4 is defined; no product implementation exists.

## Active decisions

- A2A is remote HTTP agent-to-agent transport, not local ACP and not MCP.
- Inbound remote-seat dispatch and outbound pm-flow service are separate E2Es
  sharing one protocol/state mapping.
- At least one E2E side must be an independent implementation.

## Blockers

- `agent-bindings` must provide the binding/result/access interfaces and release
  the required integration paths before T1/T2 can be finalized.

## Next eligible task

- T1 after agent-bindings lands: pin the A2A revision and state/access mapping.
