# agent-bindings workplan

## Design summary

- Introduce one binding/transport interface between a seat and an executable
  agent. Implement local ACP as one binding and expose existing pm-flow commands
  through an MCP server. Existing CLI bindings remain adapters to the same
  interface, not special cases copied into new modules.

## Interfaces and data changes

- `acp.py`: subprocess JSON-RPC session, capability/access declaration, prompt
  dispatch, streaming progress, cancellation, and final result.
- `mcp_server.py`: typed tools over existing pm-flow command semantics.
- Attempts must persist binding identity and transport separately.

## Task T1 — Define and test the ACP transport contract

- Status: pending.
- Outcome: an ACP subprocess completes initialize/session/prompt/result and
  reports whether the requested access tier is enforceable.
- Paths: `src/pm_flow/acp.py`, `tests/agent_bindings_test.sh`.
- Reuse: current response-envelope fields, timeout/cancellation semantics, and
  access-tier vocabulary.
- Acceptance IDs: A1, A3.
- Validation: a protocol-faithful test server completes one exchange; malformed
  frames, missing capability, cancellation, and child failure are distinct.
- Depends on: None.

## Task T2 — Expose pm-flow operations through MCP

- Status: pending.
- Outcome: a stock MCP client can list and invoke bounded project/section
  operations without using a shell.
- Paths: `src/pm_flow/mcp_server.py`, `tests/agent_bindings_test.sh`.
- Reuse: the installed `pm-flow` command contract and structured status output;
  do not duplicate the state machine.
- Acceptance IDs: A4.
- Validation: initialize, list tools, drive a disposable project to a terminal
  section state, and verify command errors are returned as tool errors.
- Depends on: None.

## Task T3 — Integrate ACP as a seat binding

- Status: blocked on an ownership amendment after codex-usage releases dispatch
  paths.
- Outcome: config selects ACP for a seat, a full cycle follows the ordinary
  scope/develop/review path, and stored attempts identify binding and transport.
- Paths: not assignable until `agent_exec.sh`, relevant driver/telemetry paths,
  and any CLI registration path are transferred into this section.
- Reuse: T1 adapter, current CLI binding adapters, response envelopes, catalog
  binding records, and attempt lifecycle.
- Acceptance IDs: A1, A2, A3, A5.
- Validation: run one ACP-bound and one existing CLI-bound cycle; compare outputs
  and store rows, then mutation-disable ACP selection and transport recording.
- Depends on: T1 and codex-usage dispatch ownership release.

## Task T4 — Cross-interface regression closeout

- Status: pending.
- Outcome: ACP, Claude/Codex CLI bindings, and MCP control all drive the same
  state machine with unchanged local behavior.
- Paths: `tests/agent_bindings_test.sh` plus paths transferred for T3.
- Reuse: installed-artifact harness and existing role fixtures.
- Acceptance IDs: A1–A5.
- Validation: `zsh tests/agent_bindings_test.sh` and the full suite pass; removing
  transport persistence or routing ACP through a CLI arm fails focused checks.
- Depends on: T2, T3.

## Integration and end-to-end validation

- T1 and T2 are independently assignable. T3 must not be scoped until the brief
  and `owned_paths.txt` are amended through the ownership validator.

## Risks and rollback

- ACP protocol revisions and MCP SDK dependencies may move. Keep protocol code
  isolated and preserve the existing CLI adapter as the rollback path.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T3, T4 | ACP-bound cycle reaches acceptance |
| A2 | T3, T4 | Existing CLI behavior remains unchanged |
| A3 | T1, T3 | Access enforcement/caveat reported before dispatch |
| A4 | T2, T4 | Stock MCP client drives a project without a shell |
| A5 | T3, T4 | Store distinguishes binding and transport |
