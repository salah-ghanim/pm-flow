# agent-bindings section PM state

## Current task

- T1 accepted in cycle 001. T2 — the `acp` arm in `agent_exec.sh` — is the next
  eligible task and now carries two changes from T1's review (see workplan T2).

## Completed tasks and evidence

- **T1 — ACP client and test agent. Acceptance A3 (enforceability half), A6.**
  Cycle 001. Added `src/pm_flow/acp.py` and `tests/agent_bindings_test.sh`;
  nothing else changed (`git status --short` in the developer worktree lists
  exactly those two untracked paths).
  - Command: `zsh tests/agent_bindings_test.sh` → exit 0, eleven `PASS` lines
    including `sandbox capability yields enforceable=true for write`,
    `… for scoped`, `no sandbox capability yields enforceable=false for write`
    and `… for scoped`.
  - Enforceability is capability-derived, not asserted: mutating
    `_is_enforceable` to `return True` makes the suite fail at
    `FAIL: missing sandbox enforceability`.
  - The test agent parses frames rather than replying canned: changing the
    client's third request from `session/prompt` to `prompt` makes the agent
    abort on `assert request["method"] == "session/prompt"`.
  - The client really reaps a lingering child: with the cancel-mode agent
    changed to `sleep(30)` after `session/cancel`, the suite still passes; with
    that same agent and `_reap` stubbed to `return`, it fails at
    `FAIL: cancelled agent was not reaped`. (Against the shipped test agent,
    which exits on its own, a stubbed `_reap` passes — the assertion holds only
    because the implementation is correct, not because the test forces it.)
  - Failure names observed on the outcome line, one per fault:
    `acp_malformed_frame` (invalid JSON and non-JSON-RPC envelope, exit 1),
    `acp_child_exited` (exit status 17 mid-exchange, exit 1), `acp_cancelled`
    (SIGTERM, exit 1), `acp_capability_missing` (exit 0), `none` (exit 0).
    Also defined but not exercised: `acp_attempt_timeout`, `acp_silent_stall`,
    `acp_rpc_error`, `acp_invalid_params`.
  - Review harnesses kept at `cycles/001/review_mutations.zsh`,
    `review_reap.zsh`, `review_channel.zsh`; all operate on scratch copies.

## Verified baseline (cycle 001 probes)

- `src/pm_flow/` now holds `__init__.py`, `cli.py`, `paths.py`, `acp.py`, and
  `tests/agent_bindings_test.sh` exists (T1, accepted cycle 001). Still absent:
  `src/pm_flow/mcp_server.py` and the `acp` arm in `agent_exec.sh`.
- `build_command` (`agent_exec.sh:578`) has exactly the three arms `claude`
  (:581), `codex` (:629), `copilot` (:652). It is called twice — once at :852
  for the dry-run path, once per attempt inside the retry loop at :883.
- The binding resolver is an inline python block ending at `agent_exec.sh:365`.
  It prints **12 newline-separated fields**, read back by `sed -n 'Np'` at
  :368-380: cli, model, difficulty, access, max_attempts, retry_backoff,
  usage_pause, domain, stall_seconds, silent_stall_seconds,
  max_attempt_seconds, scoped-policy JSON. It does **not** emit `cli_params`;
  an `acp` binding needs a 13th single-line JSON field. The comment above the
  policy claims it is "always last" and must be corrected if a field follows.
- `tests/pm_flow_test.sh:616` `rebind_role` writes bindings as
  `{"cli", "model", "difficulty"}` only, so the resolver must tolerate an
  absent `cli_params`.
- `command -v "$AGENT_CLI"` (`agent_exec.sh:~869`) fails a dispatch whose cli
  is not on PATH. For `acp` the binary to probe is `cli_params.command[0]`.
- The access log is one JSON object per line at `$PM_FLOW_ACCESS_LOG`
  (`agent_exec.sh:130`, default `${OUTPUT_FILE%.json}.access.jsonl`), written
  by `access_hook.sh` as a claude PreToolUse hook and, for codex,
  reconstructed from the event stream after the fact (:1003).
- Nothing in `template/`, `src/` or `tests/` writes the strings `enforced` or
  `prompt-level` today — only prose in `agent_exec.sh:645`,
  `README.md:73`, `driver.zsh:473`. A3's enforcement record is new surface,
  not a field to populate.
- `classify_failure` (`agent_exec.sh:677`) is a regex matcher over the attempt
  log and raw output, emitting `usage_limit`, `network`, `permanent`,
  `unknown` in that precedence. It matches values, not JSON keys (`:693`).
  An ACP fault named only in prose lands in `unknown` unless the text happens
  to hit a pattern — `timed? ?out` is `network`, `usage: ` is `permanent` —
  so `acp.py` must hand its reason to the arm on a machine-readable channel
  rather than let the matcher guess.
- Reaching `acp.py` from the engine needs no `paths.py` change: installed,
  `engine_root()` is `<pm_flow>/engine`, so the module sits at
  `$SCRIPT_DIR/../acp.py`; in a checkout the engine is
  `template/.agentic/pm_flow`, so it sits at
  `$SCRIPT_DIR/../../../src/pm_flow/acp.py`. Both are resolvable inside
  `agent_exec.sh`, which the section owns. `paths.as_env()` exports no python
  interpreter and `paths.py` is outside the owned paths.

## Active decisions

- Transport identity is `bindings.cli` + `cli_params`; no schema change.
- The MCP server is a façade over the installed command.
- `cli_params` enters `agent_exec.sh` as a 13th resolver field, not as a second
  parse of `config.json`.
- T1's outcome channel is a single-line JSON object on `acp.py`'s stdout with
  `failure_reason`, `text`, `enforceable`, `usage` (and `error` on failure).
  T2 reads it directly; `classify_failure` is not consulted for ACP faults.
- All three tiers (`read`, `write`, `scoped`) use the same rule: enforceable
  only if the agent declared a sandbox / filesystem-boundary capability at
  `initialize`. `read` is not exempt — an unbounded agent reads outside the
  root as freely as it writes.
- `acp.py` takes `max_attempt_seconds` and `silent_stall_seconds` from
  `params` with no defaults; omitting either yields `acp_invalid_params`, so
  T2 must pass the resolved values through.

## Interfaces consumed (from store-ledger handoff)

- `pm-flow cost` reads `<project>/runs/pm_flow.db` and prints
  `ATTEMPT\t<started_at>\t<section>\t<role>\t<label>\t<cli>\t<cost>\t<in>\t<out>`.
  A5's `cli=acp` column comes from the attempt row, so an ACP dispatch must
  reach `telemetry.py attempt-start|attempt-end` the same way the other arms
  do. Fixtures seed spend through those two commands
  (`governance.zsh:198`), not through any ledger file.

## Blockers

- None.

## Next eligible task

- T2 — the `acp` arm in `agent_exec.sh`. Unblocked now that T1 has landed, and
  it carries T1's two review changes. T3 also has no dependency and could be
  taken instead; T4 needs both.
