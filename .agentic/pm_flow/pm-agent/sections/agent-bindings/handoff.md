## Outcome

All evidence sits on branch `pm-flow/pm-agent/agent-bindings`, tip `9a683f4`; not yet in `main`.

- **A1** — `zsh tests/agent_bindings_test.sh` → exit 0, `PASS: ACP developer completes a public driver cycle to GO`, driven through a wheel-installed `pm-flow`.
- **A2** — `pm_flow_test.sh` 10 PASS; `template/.agentic/pm_flow/tests/run.zsh` `all suites passed`, 35/41/32/58/74, fail=0; `packaged_layout_test.sh` 13 PASS. `cycles/002/argv_probe.zsh` shows claude/codex/copilot argv byte-identical to the pre-change engine.
- **A3** — `PASS: enforced ACP access is recorded before work` and its prompt-level twin; the marker is snapshotted at `session/prompt`, so ordering is asserted, not presence.
- **A4** — `PASS: MCP lists exactly five tools and drives a section to done` and `PASS: MCP targets one named section and leaves the other unchanged`; a `_command_for` that drops `--section` fails the suite.
- **A5** — `PASS: cost distinguishes ACP and claude transports`: `ATTEMPT` field 6 `acp`, fields 8/9 `17`/`5`, beside `claude` `11`/`3`.
- **A6** — exit 0, 33 PASS.

## Decisions

- Transport identity is `bindings.cli` plus `cli_params`; no store schema change. `cli_params` enters `agent_exec.sh` as a 13th resolver field.
- Every tier, `read` included, is enforceable only if the agent declared a sandbox capability at `initialize`.
- `acp.py` returns one JSON line on stdout; the arm maps `failure_reason` to a retry class itself and never consults `classify_failure`.
- The MCP server is a stdlib-only façade over the installed command. Protocol faults are JSON-RPC errors; a child that ran and exited non-zero is a `tools/call` result with `isError`. Lock and budget are always the second kind.

## Interfaces

- `python -m pm_flow.mcp_server`: tools `status`, `next`, `tick` (`project`, `section`), `list_sections`, `cost`, each `additionalProperties: false`.
- Binding `{"cli": "acp", "cli_params": {"command": [...]}}` in `config.json`. A fourth ACP-speaking agent is config, not a new `case` arm.
- `acp.py` needs `max_attempt_seconds` and `silent_stall_seconds` in `params`, else `acp_invalid_params`.
- For `catalog.py`'s owner: `catalog.py:703` stores that binding as `cli_params={"cli_params":{...}}`. Nothing here depends on it — the arm reads `config.json`.

## Risks

- Unmerged. `git diff --stat main pm-flow/pm-agent/agent-bindings` still lists `mcp_server.py` +188, absent from `main`; until the driver merges, `main` exercises neither surface.
- The server passes stdin through. A future interactive engine command would eat pipelined client frames — re-check the `read` sites in `pm_flow.sh`/`driver.zsh`.
- The suite's AST guard matches `subprocess.*`/`os.*` by name; `from subprocess import run` evades it.

## What is unproven

- No real ACP agent has connected — every exchange was with the suite's Python test agent. Bind a shipped ACP agent to `developer` and run one cycle.
- No stock MCP SDK client has connected; A4 used the brief's permitted equivalent JSON-RPC script.
- ACP token accounting is untested: the test agent's `usage` is context occupancy, so A5's `17`/`5` are not real tokens.
- `acp_attempt_timeout`, `acp_silent_stall`, `acp_rpc_error` are defined but never exercised.

## Next action

Driver merges `9a683f4` into `main`. Then bind one shipped ACP agent and one stock MCP client to settle the two claims above. `a2a-binding` can consume the `acp` arm unchanged.
