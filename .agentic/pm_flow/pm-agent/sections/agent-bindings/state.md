# agent-bindings section PM state

## Current task

- None. T1, T2, T3 and T4 are all accepted; T4 landed in cycle 005 and nothing
  follows it. Every brief acceptance ID A1–A6 has evidence below. The section's
  remaining work is its handoff.

## Completed tasks and evidence

- **T4 — end to end through the installed command. Acceptance A1–A6.**
  Cycle 005, accepted. It carries cycle 004's delivery forward plus the
  section-selection control; `git status --porcelain` in the developer worktree
  lists exactly the three owned paths `src/pm_flow/acp.py`,
  `template/.agentic/pm_flow/agent_exec.sh`, `tests/agent_bindings_test.sh`, and
  the status is unchanged after four suite runs — no venv, wheel or temp
  repository left behind, and no `pm-flow-agent-bindings.*` directory survives
  in `$TMPDIR`.
  - **A4, the half cycle 004 could not prove.** Command:
    `zsh tests/agent_bindings_test.sh` → exit 0 with
    `PASS: MCP targets one named section and leaves the other unchanged`.
    The fixture now seeds the target `selected-widget` with a real dispatch and
    then creates `undispatched-widget` through `"$PM_FLOW" init-section`,
    leaving it `planned` and never dispatched, so it heads the queue on
    `last_dispatch=0` rather than on its name — which sorts *after* the target.
    The client asserts the ordering through the `next` tool
    (`section_queue[0] == unchanged_key`) **before every** targeted tick, and
    compares whole `list_sections` rows for both sections **after every** tick,
    inside the same loop (`tests/agent_bindings_test.sh:860-885`). The control
    is never made unactionable; if it left the queue the `next` assertion would
    fail first.
  - **A4, the discriminating negative check.** On a copy of the worktree at
    `$TMPDIR/pm-flow-review-005-mutant` with `_command_for` mutated to
    `if section is not None and False:` — a server that accepts `section` and
    never passes it on — `zsh <mutant>/tests/agent_bindings_test.sh` exits **1**
    at `assert selected_after != selected_before`:
    `target row did not change after targeted tick`, with
    `selected-widget … | active | Cycle 0; last action scope. | … | 2026-08-24T11:15:21Z |`
    identical before and after, while the control moved
    `undispatched-widget … | planned | Section created; …` →
    `| active | Cycle 0; last action scope. |` with a later `updated` stamp.
    So the untargeted tick really did take the control: the assertion now
    discriminates, and the fixture ordering is observed rather than assumed.
    The mutant copy was removed after the run; the worktree was never written
    to. Harnesses kept at `cycles/005/review_mutation.zsh` and
    `cycles/005/review_cleanup.zsh`.
  - **No hand-repair of engine state survives.** The synthetic failing `claude`
    dispatch is routed at its own `usage-widget` section, which may stay
    quarantined; `grep` for `rm ` in the suite returns only `$TEST_ROOT` marker
    files and the trap's `rm -rf -- "$TEST_ROOT"`. The former
    `rm -f -- "$SELECTED_SECTION/quarantine.txt"` is gone.
  - **A1.** Same command: `PASS: ACP developer completes a public driver cycle
    to GO`, on the wheel-installed `$VENV/bin/pm-flow` — the run asserts
    `develop 001 -> result`, `review 001 -> GO`, `complete -> section done`,
    that `cycles/001/result.md` holds `Built through ACP.` and does **not**
    contain `"failure_reason"`. `PM_FLOW_ENGINE_ROOT` appears nowhere in the
    suite; the only two `PM_FLOW_REPO_ROOT` uses (`:597`, `:639`) point at the
    disposable fixture, and `PYTHONPATH` is unset (`:306`) before the wheel is
    built and never re-exported for a packaged scenario.
  - **A3.** `PASS: enforced ACP access is recorded before work`,
    `PASS: prompt-level ACP access is recorded before work and still
    dispatches`, `PASS: an ACP access-log fault is permanent and is not
    retried` — `--access-log` at a directory yields
    `acp_access_log_unwritable`, `attempts=1`, the agent runs once and
    `arm-log-fault.prompt` never exists, so `session/prompt` was never reached.
  - **A5.** `PASS: cost distinguishes ACP and claude transports` and
    `PASS: cost preserves ACP and nested claude token counts` — the `awk`
    assertions match an `ATTEMPT` row with field 6 `acp` and fields 8/9 `17`/`5`
    beside one with field 6 `claude` and fields 8/9 `11`/`3`. Both still hold
    with the synthetic claude failure re-routed to `usage-widget`.
  - **A2.** `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS`.
    `zsh template/.agentic/pm_flow/tests/run.zsh` → exit 0, `all suites
    passed`, totals 35/41/32/58/74, fail=0.
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS`.
  - **A6.** `zsh tests/agent_bindings_test.sh` → exit 0, 33 `PASS` lines:
    every cycle-004 line still present, plus `MCP targets one named section and
    leaves the other unchanged`.

- **T3 — the MCP server. Acceptance A4, A6.**
  Cycle 003. Two paths changed, both writable: `src/pm_flow/mcp_server.py`
  (new, 189 lines) and `tests/agent_bindings_test.sh` (+330/-1).
  `git status --porcelain` in the developer worktree lists exactly those two.
  `pyproject.toml` is untouched and the module imports only `json`, `shutil`,
  `subprocess`, `sys`, `typing` — standard library throughout.
  - **A6.** `zsh tests/agent_bindings_test.sh` → exit 0. The seventeen T1/T2
    `PASS` lines are all still present, plus five new ones: `MCP client has no
    shell or state-reading escape hatch`, `MCP tick reports the driver lock as
    a tool error without advancing`, `MCP lists exactly five tools and drives a
    section to done`, `MCP tick reports budget exhaustion as a tool error
    without dispatching`, `agent bindings MCP suite`.
  - **A2, unaffected as predicted.** `zsh tests/pm_flow_test.sh` → exit 0, 10
    `PASS`. `zsh template/.agentic/pm_flow/tests/run.zsh` → exit 0, `all suites
    passed`, totals 35/41/32/58/74, fail=0. T3 added a module and touched no
    engine file.
  - **A4, the tool set is asserted as a set, not by presence.** The client
    asserts `names == {"status","next","tick","list_sections","cost"}`.
    Verified by mutation on a *copy* of the module under
    `cycles/003/` (the worktree was never modified): adding a sixth
    `"run": "run"` entry to `TOOL_COMMANDS` and running the developer's own
    client against it fails at `assert names == expected` with
    `{'list_sections','next','status','tick','run','cost'}`; against the
    unmutated module the same client gets past that assertion. It also asserts
    each tool's `additionalProperties is False` and exact property set —
    `{project}`, and `{project, section}` for `tick` alone.
  - **A4, no shell call of the client's own.** The test walks the client's AST
    and asserts its `subprocess.*`/`os.*` call list is exactly
    `[("subprocess","Popen")]`. Verified the guard bites: inserting a single
    `subprocess.run(["pm-flow","status"])` into a copy of the client makes it
    fail with `[('subprocess','Popen'), ('subprocess','run')]`. The client also
    contains no `open(` and no `Path(` — its only `os` use is `os.environ` —
    so it reads no section directory and no file the driver wrote.
  - **A4, terminal state read back through a tool.** The client loops `tick`
    (bounded at 32, raising if it does not converge) and re-reads
    `list_sections` each time, matching the section's row on `done`. It does
    not assume the first tick is section work: the test sets
    `governance.portfolio_review_dispatches = 1` (`driver.zsh:819`, default 12),
    so a portfolio review arms after every dispatch and preempts section work
    during the drive. The shell then asserts the reported terminal table
    contains `| mcp-widget | must-have | done |`.
  - **Stdout purity, proven directly rather than inferred.**
    `cycles/003/review_probe3.py` pipes six frames into
    `python3 -m pm_flow.mcp_server` at once against this repo and reads back
    exactly five lines — the `notifications/initialized` notification draws no
    reply — every one a clean JSON frame, with the engine's `list-sections`
    table carried *inside* `result.content[0].text` rather than beside it.
    Server exit 0, its own stderr empty. The child is spawned with
    `stdout=PIPE`/`stderr=PIPE`, never `cli.main` in-process.
  - **The two error channels are distinct.** Same probe: `resources/list` →
    JSON-RPC `error` -32601 `Method not found`; `tools/call tick` with an
    undeclared `bogus` argument → JSON-RPC `error` -32602 `unexpected tool
    argument: bogus`, *before* any process is spawned. Against the engine's own
    guards the suite shows the other channel: a `tick` under a held
    `.driver.lock` returns a `tools/call` **result** with `isError` true whose
    text names `another pm_flow driver is already running`, and the client
    proves nothing advanced by diffing `list_sections` across it; over budget,
    `tick` returns `isError` true carrying `project budget exhausted`, with
    `cost` output identical before and after, so no attempt was recorded.
    Neither is translated into a JSON-RPC error, retried, or swallowed.
  - **Argv, observed not read.** `cycles/003/review_probe4.zsh` prints what
    each tool builds: `--project` first in every case, `list_sections` mapping
    to the hyphenated command `list-sections`, `--section` emitted for `tick`
    only, and nothing else passed through. With `pm-flow` off `PATH` the
    fallback `[sys.executable, "-m", "pm_flow.cli"]` is what runs — which is
    the form the suite exercises.
  - **The server holds no state.** It touches the filesystem only through
    `shutil.which`; it never reads `sections/`, parses `status.txt`, decides
    what is actionable, or caches anything between calls.
  - Review harnesses kept at `cycles/003/review_run.zsh` (suite + exit status),
    `review_probe.zsh` (extract client/guard, build the mutant copy),
    `review_probe2.zsh` (the two negative checks), `review_probe3.zsh`/`.py`
    (stdout purity and both error channels), `review_probe4.zsh` (argv),
    `review_cleanup.zsh`. All operate on copies; none writes into the worktree.

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
- The MCP server's error rule is one line and settled: a protocol fault
  (unknown method, unknown tool, an argument outside the declared schema) is a
  JSON-RPC `error`; a child that ran and exited non-zero is a `tools/call`
  result with `isError` true carrying its stderr and stdout. The lock and the
  budget are always the second kind.
- The MCP server is standard library only and stays that way while
  `pyproject.toml` declares `dependencies = []` and sits outside this section.
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

## Verified baseline (cycle 003 probes)

- `src/pm_flow/` holds `__init__.py`, `cli.py`, `paths.py`, `acp.py`,
  `semconv.py`. `mcp_server.py` is still absent.
- **No MCP SDK, and none may be added.** `pyproject.toml` declares
  `dependencies = []` with a comment saying the emptiness is the point ("a
  dependency here would have to resolve on every machine the flow is installed
  into"). `.venv/…/site-packages/` holds only `pm_flow` and its dist-info — no
  `mcp`. `pyproject.toml` is outside the owned paths, so T3 is standard library
  only and A4's client is the brief's permitted equivalent JSON-RPC script.
- **The engine's stdout is the transport.** `cli.main` ends in
  `subprocess.call(command, cwd=…, env=…)` (`cli.py:87`) with no pipes, so the
  engine writes to the inherited fd 1. An MCP server that calls `cli.main`
  in-process puts engine output on the JSON-RPC channel. The child must be
  spawned with `stdout`/`stderr` piped.
- **The command surface.** `pm_flow.sh:1910-1993` dispatches `tick`, `status`,
  `next`, `cost`, `list-sections` among others. `main`'s option loop
  (`:1881-1898`) strips `--project` and `--section` from any position;
  `cli.py:73` recognises `--project` only as argv[0]. `cmd_cost`
  (`driver.zsh:466`), `cmd_next` (`:2857`), `cmd_status` (`:2875`) and
  `cmd_list_sections` (`pm_flow.sh:1744`) take no arguments. `cmd_tick`
  (`:2710`) reads `SECTION_OVERRIDE` and, with no section, may return
  `section=(project) action=portfolio-review` before any section work.
- **Lock and budget are the same failure shape.** `acquire_driver_lock`
  (`pm_flow.sh:884`) calls `fail "another pm_flow driver is already running for
  project '<key>'"`; `assert_within_budget` (`driver.zsh:611`) calls `fail
  "project budget exhausted: …"`. `fail` writes stderr and exits non-zero, so
  one rule — non-zero exit becomes a tool error carrying the child's output —
  covers both of the brief's server-side rejection conditions.
- **The disposable-project harness already exists** at
  `tests/agent_bindings_test.sh:256-343`: `install.sh` into a temp repo,
  `CYCLE_PM=(env PM_FLOW_REPO_ROOT=… PYTHONPATH=… python3 -m pm_flow.cli)`,
  `init-section` from a heredoc brief, `tests/fixtures/stub_success.zsh`
  installed as `driver-bin/claude`, `drain_project_work`, `run_driver`. A
  second disposable project driven over MCP reuses it as-is.

## Verified baseline (cycle 003 review probes)

- **The engine never reads the server's stdin.** Every `read` in `pm_flow.sh`
  and `driver.zsh` is fed by a here-string or a pipe (`pm_flow.sh:1552`,
  `driver.zsh:128`, `:144`, `:2686`, `:2942`, `:3392`, `:3396`). So the child
  inheriting fd 0 from the MCP server cannot consume a pipelined client frame.
  Confirmed empirically: six frames written in one go were answered in order.
  Worth re-checking if any future command becomes interactive — the server
  passes stdin through rather than closing it.
- The AST guard in the test matches `subprocess.*` and `os.*` attribute calls
  by name. It would not catch `from subprocess import run` or `__import__`, so
  it is a guard against drift rather than against a determined bypass. Adequate
  for its purpose; noted so a later cycle does not over-trust it.
- `tick`'s `section` argument reaches the engine correctly but no test
  demonstrates it selecting a section — see the carried change in workplan T4.

## Verified baseline (cycle 004 probes)

- **A packaged install exercises code paths no suite has run.** `pyproject.toml`
  packages `src/pm_flow` and force-includes `template/.agentic/pm_flow` as
  `pm_flow/engine`. So installed, `agent_exec.sh` is at
  `<site-packages>/pm_flow/engine/agent_exec.sh` and `acp.py` one level up at
  `<site-packages>/pm_flow/acp.py` — the arm's **first** branch (`:670`).
  Every existing test runs from the checkout and takes the **second** branch
  (`:672`). Likewise `shutil.which("pm-flow")` finds the venv console script,
  where the suite has only ever seen the `-m pm_flow.cli` fallback. Neither
  shipped path has been run once.
- **Token accounting needs no file outside the owned paths.**
  `driver.zsh:791-793` always passes `--response` to `telemetry.py
  attempt-end`; `usage_from_response` (`telemetry.py:139`) depth-first searches
  the envelope for `usage` and reads `input_tokens`/`output_tokens`;
  `write_response` (`agent_exec.sh:751`) is owned. Carrying `acp.py`'s counts
  into the envelope is the whole change.
- **But an unconditional `usage` key is an A2 regression.** `_find_key`
  (`telemetry.py:103`) returns the first `usage` it meets and
  `usage_from_response` `setdefault`s off it. A claude envelope's real counts
  are in the *second* candidate — the JSON nested in `result` — so a top-level
  `"usage": {}` written for every arm sets both keys to `None` first and
  `setdefault` never overwrites them. Claude's token accounting would go to
  NULL with every suite still green. The key must be omitted when empty.
- **`_record_access` still cannot name its own fault.** `acp.py:232-253` writes
  with no `try`; `main:424` catches bare `OSError` beside `ValueError` and
  labels both `acp_invalid_params`.
- **The ACP `usage` the test agent reports is not tokens.**
  `agent_bindings_test.sh:149` sends `{"used": 7, "size": 100}` — context
  occupancy. `acp.py:360-372` copies it through verbatim, so there is nothing
  token-shaped to carry yet.
- **Where the assertion lands.** `cost.py:227-236` selects
  `a.input_tokens, a.output_tokens` as the last two columns of the `ATTEMPT`
  row, i.e. fields 8 and 9 of the row A5 already matches by `awk`.

## Verified baseline (cycle 004 review probes)

- **The packaged harness is real.** Reviewed against the developer worktree:
  the suite unsets `VIRTUAL_ENV`/`PYTHONPATH`/`PYTHONHOME` and every `PIP_*`/
  `UV_*` parameter, sets `ZDOTDIR` to an empty dir, builds the wheel offline
  from `tests/packaging-build-wheelhouse` in a separate build venv, and runs
  every packaged scenario through `$VENV/bin/pm-flow` or
  `$INSTALLED_ENGINE/agent_exec.sh`. `PM_FLOW_ENGINE_ROOT` appears nowhere;
  the only `PM_FLOW_REPO_ROOT` uses (`:571`, `:613`) point at the disposable
  fixture, never at the checkout. `install.sh` writes no engine file and calls
  `remove_copied_engine`, so the fixture holds project data only.
- **The claude-usage guard bites.** Mutating `write_response` to write the
  `usage` key on every arm (`if usage_path:` → `if True:`, and dropping the
  non-empty test) makes the suite fail at `FAIL: cost lost nested claude token
  counts` while the ACP row's fields 8/9 still read `17`/`5`. So the
  rejection condition the workplan named is genuinely covered, not asserted
  only on the ACP side.
- **The retry-mapping guard bites.** Removing `acp_access_log_unwritable` from
  the arm's `case` fails at `FAIL: access-log failure did not map to
  permanent`.
- **The section-selection assertion does not discriminate.** Mutating
  `_command_for` to drop `--section` (`if section is not None and False:`) —
  a server that accepts the argument and never passes it on — leaves the whole
  suite green, `PASS: MCP targets one named section and leaves the other
  unchanged` included. Cause: the MCP drive runs *after* the ACP cycle has
  taken `widget` to `done`, so `selected-widget` is the only actionable
  section and the control cannot move under any tick. Printing the client's
  own `list_sections` read-back confirms it: both rows are `done`, and
  `widget`'s was already `done` before the first targeted tick. The control
  section has to be actionable at tick time — and ranked ahead of the target
  by the scheduler — or the "other section standing still" half proves
  nothing. All mutations were applied to `/tmp` copies of the worktree; the
  worktree was never written to. Harness: `cycles/004/review_mutate.zsh`.

## Verified baseline (cycle 005 scope probes)

- **The scheduler's key is not "dependents then lexical".** `actionable_sections`
  (`driver.zsh:2666`) sorts on `(priority_rank, -dependents, last_dispatch,
  name)`. So `last_dispatch` decides before the name does, and a section that
  has never been dispatched reads `0` (`:2648`) and heads the queue. This
  matters for the open defect: on `name` alone `selected-widget` sorts *before*
  `widget`, so simply leaving the cycle-004 control actionable would still let
  an untargeted tick take the target, and the dropped-`--section` mutant would
  still pass. A never-dispatched control is what discriminates.
- **A targeted tick cannot be preempted.** `cmd_tick` (`:2711-2722`) reads
  `SECTION_OVERRIDE` first and skips the `decompose`/`portfolio-review` branch
  entirely when it is set; only an untargeted tick goes through
  `project_next_action`. So a portfolio review can never take a tick the client
  aimed at a section, and an armed review makes a `--section`-dropping server
  fail sooner, not later.
- **The queue is observable through a tool.** `cmd_next` (`:2857`) prints the
  same order `cmd_tick` would take, project work included, and dispatches
  nothing. `next` is already one of the five MCP tools, so "the control is what
  an untargeted tick would take" can be asserted from inside the client.
- **A quarantined section leaves the queue.** `actionable_sections` skips
  `quarantined` (`:2616`) and `cmd_next` iterates the same list, so a section
  parked by the synthetic claude failure perturbs neither the ordering nor the
  drive — and needs no hand-deletion of `quarantine.txt`.
- **`list_sections` rows carry `updated_at`.** `refresh_sections_index`
  (`pm_flow.sh:653-655`) emits `name | priority | status | summary | handoff |
  run_path | updated`, so whole-row equality is a real "did not move" test.
- Cycle 004's delivery is intact and uncommitted in the section worktree at
  `.pm-flow-worktrees/pm-flow/pm-agent/agent-bindings` (branch tip `67367b6`,
  three modified files). `main` and the branch tip carry only through cycle 003.

## Blockers

- None. The cycle-004 defect — the vacuous MCP named-section assertion — is
  closed in cycle 005 and re-verified by mutation (see T4's evidence above).

## Next eligible task

- None. Every workplan task is done and every brief acceptance ID A1–A6 has
  evidence. The section's next action is its handoff.

## Residual notes for whoever reads this next

- `governance.portfolio_review_dispatches = 1`, set during T3, was not restored
  in cycle 005. It is not needed for the property under test: `cmd_tick`
  (`driver.zsh:2711-2722`) reads `SECTION_OVERRIDE` before consulting
  `project_next_action`, so a portfolio review can never preempt a *targeted*
  tick. The suite still drains project work through `drain_project_work` at the
  default threshold. Optional hardening, not a gap.
- The AST guard on the MCP client matches `subprocess.*`/`os.*` attribute calls
  by name only; `from subprocess import run` or `__import__` would evade it. It
  guards against drift, not a determined bypass — unchanged from cycle 003 and
  still adequate for its purpose.
