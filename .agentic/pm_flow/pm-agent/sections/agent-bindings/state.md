# agent-bindings section PM state

## Current task

- T1 and T2 are both accepted. T3 — the MCP server — is the next assignment; it
  has no dependency. T4 needs T3 and carries two changes from T2's review
  (access-log fault naming, ACP token accounting — see workplan T4).

## Completed tasks and evidence

- **T2 — the `acp` arm in `agent_exec.sh`. Acceptance A1, A2, A3, A5.**
  Cycle 002. Three files changed, all owned: `src/pm_flow/acp.py`,
  `template/.agentic/pm_flow/agent_exec.sh`, `tests/agent_bindings_test.sh`
  (+406/-11). `git status --porcelain` in the developer worktree lists exactly
  those three and nothing else.
  - **A1/A6.** `zsh tests/agent_bindings_test.sh` → exit 0, seventeen `PASS`
    lines: T1's eleven plus `ACP developer completes a public driver cycle to
    GO`, `enforced ACP access is recorded before work`, `cost distinguishes ACP
    and claude transports`, `prompt-level ACP access is recorded before work and
    still dispatches`, `ACP failures use the dedicated retry mapping`,
    `permission requests follow the access tier and option kind`. The cycle
    asserts `develop 001 -> result`, `review 001 -> GO`, `complete -> section
    done`, that `cycles/001/result.md` holds the agent's prose ("Built through
    ACP.") and that it does **not** contain `"failure_reason"`.
  - **A2.** `zsh tests/pm_flow_test.sh` → exit 0 (14 PASS, including `role
    personas, agent dispatch, and supervision`, which holds the `:638-656`
    dry-run assertions). `zsh template/.agentic/pm_flow/tests/run.zsh` → exit 0,
    `all suites passed`, totals 35/41/32/58/74, fail=0 throughout.
  - **A2, stronger than the suites ask.** `cycles/002/argv_probe.zsh` builds the
    dry-run argv from the pre-change engine (main checkout) and the changed
    engine against one identical config and diffs them. Byte-identical for
    developer/claude/medium (write), pm/codex/max (scoped), consultant/codex/high
    (read), consultant/copilot/xhigh (read), reviewer/claude/high — after
    normalising only the per-run `pm-flow-agent.XXXXXX` scratch dir, which varies
    by construction. Its `rebind` writes bindings with no `cli_params`, so this
    also proves the 13th resolver field tolerates absence.
  - **A3, ordering not presence.** The test agent snapshots
    `$PM_FLOW_ACCESS_LOG` at the moment it receives `session/prompt` and writes
    it to a marker; the assertion reads the marker, never the end-of-run log.
    `cycles/002/probe.zsh` shows the marker discriminates: with `--access-log`
    given the marker holds
    `{"access":"enforced",…,"source":"acp-capabilities",…}`; with it omitted the
    marker is empty. So moving the write after `session/prompt` fails the
    assertion. In source, `_record_access` sits between `client.response(1)` and
    the `session/new` request (`acp.py:337`).
  - **A3, prompt-level half.** A developer bound to an agent declaring no
    sandbox capability dispatches and returns `is_error=False` with the agent's
    text; its marker holds `"access":"prompt-level"`. Not a `permanent`
    classification.
  - **A5.** `pm-flow cost` on the test project has an `ATTEMPT` row with field 6
    `acp` for `developer` and another with `claude`, asserted by awk on the
    tab-separated columns.
  - **Exit status before `failure_reason`.** The developer kept
    `acp_capability_missing` on a successful exchange and gated the arm on
    `attempt_status == 0` first (`agent_exec.sh:910-930`); the reason is read
    only in the failure branch. The prompt-level test is the proof.
  - **Retry mapping is the arm's own.** `classify_failure` is not called for an
    `acp` attempt. Observed end to end: `invalid_json` → `permanent`,
    `early_exit` → `network`, and an unenumerated `rpc_error` →
    `unknown` with `attempts=2` and the agent itself counting exactly two
    exchanges — the one extra attempt the `unknown` arm grants.

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

## Verified baseline (cycle 002 probes)

- **A5 needs no telemetry call in the arm.** `telemetry.py attempt-end:623`
  resolves the attempt's cli as `args.cli or envelope.get("pm_backend") or
  row["cli"]`; `driver.zsh` already brackets every dispatch with
  `telemetry_start_attempt` (`:767`) and `telemetry_end_attempt` (`:785`,
  called at `:1032` and `:1050`); `write_response` (`agent_exec.sh:767`) writes
  `"pm_backend": cli` from `$AGENT_CLI`; `cost.py:233` selects `a.cli` from the
  attempts row. So `AGENT_CLI=acp` plus the standard envelope is the whole of
  A5. The earlier workplan note claiming the arm must call `telemetry.py`
  itself was wrong and is corrected.
- `run_attempt` (`:408`) runs `( cd "$PROJECT_ROOT" && exec python3 -c
  "$PGROUP_SHIM" "${AGENT_ARGV[@]}" ) > "$RAW_OUTPUT" 2> "$ATTEMPT_LOG"`. So an
  `acp` argv puts `acp.py`'s single-line JSON outcome into `$RAW_OUTPUT`, and
  the success test at `:888` (`status 0`, not stalled, `-s "$RAW_OUTPUT"`)
  passes on it. The arm must swap that line for the agent's `text` before
  `write_response`, or `result` carries the outcome JSON instead of the answer.
  `cd "$PROJECT_ROOT"` also means `acp.py`'s `session/new` `cwd` is already the
  working root; no extra parameter is needed.
- Enforceability is only known after `initialize`, which happens inside
  `acp.py`. The arm therefore cannot write A3's record before spawning; the
  record has to be written between `initialize` and `session/prompt`.
- The access log record shape (`access_hook.sh:106`) is `ts`, `role`, `label`,
  `tool`, `targets`, `outside`, `reaches_user_files`, optional `command`. The
  codex reconstruction (`agent_exec.sh:1071`) adds `"source": "codex-events"`
  to mark a weaker record. An ACP record should follow the same shape and mark
  its own source.
- `catalog.py:703` builds a seat's stored `cli_params` as every binding key
  except `cli`/`model`/`difficulty`, so the brief's nested
  `{"cli":"acp","cli_params":{...}}` lands in the store as
  `cli_params={"cli_params":{...}}`. `catalog.py` is outside this section's
  owned paths and `agent_exec.sh` reads `config.json`, not the store, so this
  changes nothing for T2 — recorded as a mismatch for whoever owns `catalog.py`.
- `tests/fixtures/stub_success.zsh` is a role-aware agent double: it switches on
  the task line in the prompt (`Task: scope the next assignment`, `Task:
  implement this assignment`, `Task: review a developer result`, `Task: review
  the portfolio`, `Task: write the section handoff`) and retires the workplan
  scaffold marker on the scope call. `pm_flow_test.sh:997-1036` installs it as
  `driver-bin/claude` and drives cycles with `run --max-ticks`. An ACP test
  agent that answers only the developer task, with pm and reviewer left on this
  stub, is the shortest route to A1.

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
- A5 is satisfied by the envelope, not by a telemetry call in the arm: the
  driver brackets the dispatch and `attempt-end` reads `pm_backend`.
- The arm maps `acp.py`'s reason to a retry class itself:
  `acp_child_exited` → `network`,
  `acp_attempt_timeout`/`acp_silent_stall`/`acp_cancelled` → `stall`,
  `acp_malformed_frame`/`acp_invalid_params` → `permanent`, anything else →
  `unknown`. An exit-0 line is never a failure whatever `failure_reason` says.

## Interfaces consumed (from store-ledger handoff)

- `pm-flow cost` reads `<project>/runs/pm_flow.db` and prints
  `ATTEMPT\t<started_at>\t<section>\t<role>\t<label>\t<cli>\t<cost>\t<in>\t<out>`.
  A5's `cli=acp` column comes from the attempt row, so an ACP dispatch must
  reach `telemetry.py attempt-start|attempt-end` the same way the other arms
  do. Fixtures seed spend through those two commands
  (`governance.zsh:198`), not through any ledger file.

## Verified baseline (cycle 002 review probes)

- The `acp` arm reads `cli_params` for everything agent-specific: the binary to
  probe (`command[0]`) and the argv to spawn. Nothing about any vendor is
  hard-coded, so a fourth ACP-speaking agent is a config change, not a fifth
  `case` arm.
- `role_binding` has exactly one reader (`agent_exec.sh:369-381`), so adding the
  13th field broke no other consumer. Confirmed by grep across `template/`,
  `src/` and `tests/`.
- On an ACP *failure*, `failure_output` is `$RAW_OUTPUT`, so the envelope's
  `result` carries `acp.py`'s outcome JSON. That matches how the other arms
  surface a failed attempt and is not the rejection condition, which is about
  the accepted result body.
- `acp.py` fails closed if it cannot write the access record, but names the
  fault `acp_invalid_params` — see workplan T4 item 1. Reproduce with
  `cycles/002/log_fault_probe.zsh`.
- Review harnesses kept at `cycles/002/probe.zsh` + `probe_agent.py` (A3
  ordering), `cycles/002/argv_probe.zsh` (A2 argv equality),
  `cycles/002/log_fault_probe.zsh` (access-log fault). All read the developer
  worktree and write only to their own `mktemp -d` scratch.

## Blockers

- None.

## Next eligible task

- T3 — the MCP server. T1 and T2 are accepted; T3 has no dependency. T4 needs
  T3 and picks up T2's two carried changes.
