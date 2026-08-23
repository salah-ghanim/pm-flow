# agent-bindings section PM state

## Current task

- T1 — define and test the ACP transport contract in `acp.py`.

## Completed tasks and evidence

- None. The section has been decomposed; no product implementation exists.

## Active decisions

- ACP transport and MCP control are separate adapters to the existing state
  machine. Neither may duplicate project/section transitions.
- Existing CLI bindings remain the compatibility baseline.
- T3 requires a validated dispatch-path ownership transfer after codex-usage.

## Blockers

- None for T1 or T2. T3 is intentionally not assignable under current ownership.

## Next eligible task

- T1. Validate a protocol-faithful initialize/prompt/result exchange, access
  capability preflight, cancellation, malformed frames, and child failure.
