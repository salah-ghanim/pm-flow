# agent-bindings workplan

## Design summary

- One ACP client module; one new `case` arm in `agent_exec.sh` that calls it
  and writes the same response envelope the other arms write; an MCP server
  that is a thin tool façade over the installed command. Existing arms are
  untouched.

## Interfaces and data changes

- `acp.run(...)`, binding `cli: acp` with `cli_params.command`; MCP tools
  `status`, `next`, `tick`, `list_sections`, `cost`. No schema change.

## Task T1 — ACP client and test agent

- Status: done (cycle 001, accepted with changes carried into T2).
- Outcome: `acp.py` completes initialize → session → prompt → result against
  a protocol-faithful test agent shipped in the test, distinguishes malformed
  frames, missing capability, cancellation and child exit, and reports
  whether the tier is enforceable from the agent's declared capabilities.
- Paths: `src/pm_flow/acp.py`, `tests/agent_bindings_test.sh`.
- Reuse: the envelope fields and timeout semantics in `agent_exec.sh`.
- Interface to T2: a machine-readable outcome channel, not prose.
  `classify_failure` (`:677`) is a regex matcher over the attempt log, so any
  reason it is left to infer falls through to `unknown`; T1 must hand T2 the
  reason directly.
- Acceptance IDs: A3, A6.
- Validation: `zsh tests/agent_bindings_test.sh` — one successful exchange
  returns the agent's text; each failure mode yields a distinct
  `failure_reason`; an agent declaring no sandbox capability yields
  `enforceable=false`.
- Depends on: None.

## Task T2 — The `acp` arm in agent_exec.sh

- Status: done (cycle 002, accepted with one change carried into T4).
- Outcome: a binding with `cli: acp` dispatches through `acp.py`, writes the
  standard response envelope, records `access: enforced|prompt-level` before
  the agent runs, and a full section cycle completes with an ACP developer.
- Paths: `template/.agentic/pm_flow/agent_exec.sh`, `tests/agent_bindings_test.sh`.
- Reuse: `write_response` (`:737`), `run_attempt` (`:408`), the
  `tests/fixtures/stub_success.zsh` role script, T1's test agent. Three edits
  the cycle-001 probes make unavoidable, all inside this task: the resolver
  block ending at `:365` prints 12 fields and no `cli_params`, so add a 13th
  single-line JSON field (tolerating its absence, per `pm_flow_test.sh:616`)
  and correct the "always last" comment at `:358`; the `command -v
  "$AGENT_CLI"` guard at `:867` must probe `cli_params.command[0]` for an
  `acp` binding; `run_attempt` sends the child's stdout to `$RAW_OUTPUT`, so
  the arm must replace that JSON line with the agent's `text` before
  `write_response` runs, or the envelope's `result` is the outcome line rather
  than the role's answer. `enforced`/`prompt-level` appear nowhere in
  `template/`, `src/` or `tests/` today — this is new surface.
- A5 needs no telemetry call in the arm, contrary to the earlier note here.
  `telemetry.py attempt-end` (`:623`) resolves the attempt's `cli` as
  `args.cli or envelope["pm_backend"] or row["cli"]`, the driver already
  brackets every dispatch with `telemetry_start_attempt`/`telemetry_end_attempt`
  (`driver.zsh:767`, `:785`), and `write_response` writes `pm_backend` from
  `$AGENT_CLI`. Setting `AGENT_CLI=acp` and writing the standard envelope is
  what makes `cost` print `cli=acp`; `cost.py:233` selects `a.cli` straight
  from the row.
- `classify_failure` is not consulted for an `acp` attempt. The arm maps
  `acp.py`'s reason itself: `acp_child_exited` → `network`,
  `acp_attempt_timeout`/`acp_silent_stall`/`acp_cancelled` → `stall`,
  `acp_malformed_frame`/`acp_invalid_params` → `permanent`, `acp_rpc_error`
  and anything unenumerated → `unknown`, so a reason nobody has named yet
  still buys the one retry the `unknown` arm grants.
- Carried change from T1's cycle-001 review: `acp.py` prints
  `failure_reason="acp_capability_missing"` on a **successful** exchange
  (exit 0, real `text`, `usage` populated) whenever `enforceable` is false.
  The arm must gate on the client's exit status first and read
  `failure_reason` only for a non-zero exit; an exit-0 line is never a
  failure. `enforceable=false` means record `access: prompt-level` and
  dispatch, per the brief's constraint — not a `permanent` classification.
  Either enforce that ordering in the arm or change the success line to
  `failure_reason="none"` and let the arm read `enforceable`.
- Also from that review: `acp.py` (`:130`) answers every
  `session/request_permission` with `outcome: cancelled`. That is a policy
  the tier should drive; decide it here and cover it in the test, or the
  `write` tier silently denies an agent that asks.
- Enforceability is only known after `initialize`, which happens inside
  `acp.py`, so the arm cannot write A3's record before spawning. The record
  must instead land in `$PM_FLOW_ACCESS_LOG` after `initialize` and before
  `session/prompt` — before the agent is handed any work — and the test must
  prove that ordering rather than the record's mere presence.
- Acceptance IDs: A1, A2, A3, A5.
- Validation: `zsh tests/agent_bindings_test.sh` — cycle reaches `GO`; the
  agent reads its own `access` record out of the log at `session/prompt`
  time; `pm-flow cost` lists `cli=acp`; `zsh tests/pm_flow_test.sh` and
  `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0.
- Depends on: T1.

## Task T3 — MCP server

- Status: done (cycle 003, accepted with one change carried into T4).
- Outcome: `python -m pm_flow.mcp_server` serves the five tools over stdio;
  each invokes the installed `pm-flow` command and returns its output or a
  tool error.
- Paths: `src/pm_flow/mcp_server.py`, `tests/agent_bindings_test.sh`.
- Reuse: `pm_flow.cli`; no state machine code.
- Standard library only. `pyproject.toml` declares `dependencies = []` with a
  comment stating the absence is deliberate, `pyproject.toml` is outside this
  section's owned paths, and the editable venv carries no `mcp` package. So the
  server hand-writes JSON-RPC 2.0 over stdio, and A4's "stock MCP client" is
  the brief's permitted equivalent JSON-RPC script.
- The transport hazard: `cli.main` runs the engine with `subprocess.call(...)`
  inheriting fd 1 (`cli.py:87`). Calling it in-process would put the engine's
  stdout on the JSON-RPC channel and corrupt every frame. The server must spawn
  the command as a child with `stdout` and `stderr` piped, and write nothing to
  its own stdout but protocol frames.
- Error mapping is one rule, and it covers both of the brief's server-side
  rejection conditions. `acquire_driver_lock` (`pm_flow.sh:884`) and
  `assert_within_budget` (`driver.zsh:611`) both go through `fail`: message on
  stderr, non-zero exit. A non-zero exit is therefore a *tool* error — a
  `tools/call` result carrying the child's output with `isError` true — not a
  JSON-RPC error. JSON-RPC errors are reserved for protocol faults: unknown
  method, unknown tool name, arguments that do not match the declared schema.
- Argument surface, confirmed against the engine: `main` (`pm_flow.sh:1881-1898`)
  strips `--project` and `--section` from anywhere in argv; `cli.py:73` honours
  `--project` only as argv[0], so the server puts it first. `cmd_cost`
  (`driver.zsh:466`), `cmd_next` (`:2857`), `cmd_status` (`:2875`) and
  `cmd_list_sections` (`pm_flow.sh:1744`) take no arguments; `cmd_tick`
  (`:2710`) honours `SECTION_OVERRIDE`. So `tick` takes an optional `section`,
  every tool takes an optional `project`, and nothing else is passed through.
- Acceptance IDs: A4, A6.
- Validation: `zsh tests/agent_bindings_test.sh` — a JSON-RPC client script
  lists exactly five tools, drives a stub project to `done` via `tick`, and a
  `tick` while the driver lock is held returns a tool error naming the lock.
- Depends on: None.

## Task T4 — End to end through the installed command

- Status: done (cycle 005, accepted; the cycle-004 delivery plus the
  section-selection control).
- Outcome: a packaged install binds an ACP developer, is driven by the MCP
  client to a terminal section, and `cost` distinguishes the two transports.
- Paths: `tests/agent_bindings_test.sh`, `src/pm_flow/acp.py`,
  `template/.agentic/pm_flow/agent_exec.sh`.
- Reuse: the harness in `tests/packaged_layout_test.sh` — the offline wheel
  build (`:104-200`), the two venvs, `PM_FLOW="$VENV/bin/pm-flow"` (`:226`),
  the documented `install.sh` invocation (`:852`), `flow-bin/claude` from
  `tests/fixtures/stub_success.zsh` (`:749`) — and this suite's own
  disposable-project harness at `:256-343` for the config and brief shapes.
- Why a packaged run is not ceremony (cycle-004 probes). `[tool.hatch.build.
  targets.wheel]` packages `src/pm_flow`, and `force-include` maps
  `template/.agentic/pm_flow` → `pm_flow/engine`. So in a real install
  `agent_exec.sh` sits at `<site-packages>/pm_flow/engine/agent_exec.sh` and
  `acp.py` at `<site-packages>/pm_flow/acp.py` — which is the arm's **first**
  branch, `"$SCRIPT_DIR/../acp.py"` (`agent_exec.sh:670`). Every test to date
  runs from the checkout and therefore takes the **second** branch,
  `"$SCRIPT_DIR/../../../src/pm_flow/acp.py"` (`:672`). Symmetrically,
  `mcp_server.py` ships as `pm_flow.mcp_server` and `pm-flow` is a console
  script on the venv's `bin`, so `shutil.which("pm-flow")` succeeds and the
  server spawns the console script — where the suite so far has only exercised
  the `[sys.executable, "-m", "pm_flow.cli"]` fallback. T4 is the first run of
  either shipped path.
- Carried from T3's cycle-003 review, in `tests/agent_bindings_test.sh`:
  `tick`'s `section` argument is built correctly — `_command_for("tick",
  {"project":"p","section":"s"})` yields `--project p tick --section s`, and
  `main`'s option loop (`pm_flow.sh:1881-1898`) strips `--section` from any
  position — but no test shows it selecting a section. The drive loop calls
  `tick` with `project` only; the budget case passes `section` but
  `assert_within_budget` refuses before section resolution, so it proves only
  that the engine tolerates the flag. T4's packaged run should tick a named
  section over MCP and assert that section advanced and the other did not, or
  the brief's "a tool silently accepts an argument it does not pass on" stays
  untested for the one argument that is not `project`.
  Still open after cycle 004, and the reason is fixture ordering, not the
  assertion's shape. Cycle 004 wrote both halves but ran the MCP drive after
  the ACP cycle had already taken the control section (`widget`) to `done`,
  leaving `selected-widget` the only actionable section; mutating
  `_command_for` to drop `--section` entirely left the suite green. Two things
  have to be true at the moment each targeted tick is issued: the control is
  **actionable**, and the control is what an **untargeted** tick would take.
  Making the control merely actionable is not enough — the scheduler's key is
  `(priority_rank, -dependents, last_dispatch, name)` (`driver.zsh:2666`), and
  on `name` alone `selected-widget` sorts *before* `widget`, so an untargeted
  tick would still take the target and the mutant would still pass.
  `last_dispatch` outranks `name`: a section never dispatched reads `0`
  (`:2648`) and heads the queue. `cmd_next` (`:2857`) prints exactly that queue
  without dispatching, and `next` is already one of the five tools — so the
  client can assert the ordering through the MCP surface rather than infer it.
  Note also that `SECTION_OVERRIDE` makes `cmd_tick` skip the project branch
  entirely (`:2711-2722`), so no portfolio review can preempt a *targeted*
  tick; an untargeted one is preempted by it, which only strengthens the
  mutant's failure. Prove the fix the way the defect was found: with
  `--section` dropped from `_command_for`, `zsh tests/agent_bindings_test.sh`
  must fail, and the failing assertion must be reported.
- Also from cycle 004's review, and entangled with the above: the fixture
  injects a synthetic failing `claude` dispatch at `selected-widget` to get a
  nested-`usage` row for the A5 claude-side assertion, then deletes
  `quarantine.txt` out of the section to make it drivable again. A test that
  repairs engine state by hand is asserting against a state the engine never
  produces. Route the synthetic failure somewhere that needs no repair — a
  section that may stay quarantined, since `actionable_sections` (`:2616`) and
  `cmd_next` both drop a quarantined section from the queue.
- Carried from T2's cycle-002 review, both in `src/pm_flow/acp.py`:
  1. `_record_access` (`:232`) does not guard its write. An `OSError` on the
     access log escapes into `main`'s `except` (`:424`), which names every
     non-`ACPFailure` fault `acp_invalid_params` — so a log-write problem is
     reported as bad parameters and the arm's mapping condemns it `permanent`
     with no retry. Failing closed is right (no record, no dispatch), but the
     reason has to name the cause; add an `acp_access_log_unwritable` reason,
     or the nearest existing one, rather than borrowing the params name.
     Observed: `--access-log <a directory>` against a healthy agent gives
     `{"failure_reason":"acp_invalid_params","error":"[Errno 21] Is a
     directory: …"}`, exit 1, and the agent never reaches `session/prompt`.
     `access_hook.sh:132` swallows the same class of fault (`except OSError:
     pass`), so the two writers disagree about how loud a log fault is.
     Confirmed in cycle 004: `_record_access` (`acp.py:232-253`) writes with no
     `try`, and `main`'s handler (`:424`) catches bare `OSError` alongside
     `ValueError`, so the fault cannot be told from a bad `--params-json`.
     Decision for T4: `acp.py` raises `ACPFailure("acp_access_log_unwritable",
     …)` and the arm maps it to `permanent`. A log path that is a directory, or
     a root the process cannot write, does not become writable inside one
     retry backoff, and the `unknown` arm's free retry would spend a dispatch
     to re-learn it. Fail closed, loud, and once.
  2. The arm discards `usage`: the outcome line is replaced wholesale by
     `text` before `write_response` (`agent_exec.sh:914-931`), so an ACP
     attempt reaches the store with `input_tokens`/`output_tokens` NULL. A5
     only ever needed `cli=acp` and is met, but T4's packaged run is where
     token accounting for the transport should land.
     The route needs nothing outside the owned paths, confirmed in cycle 004:
     `driver.zsh:791-793` always passes `--response "$response_json"` to
     `telemetry.py attempt-end`, and `usage_from_response` (`telemetry.py:139`)
     depth-first searches the envelope for a `usage` key and reads
     `input_tokens`/`output_tokens` off it. `write_response`
     (`agent_exec.sh:751`) is owned, so carrying `acp.py`'s counts into the
     envelope as a `usage` object is the whole of it — no `telemetry.py` edit.
     Two constraints on doing it:
     - **The envelope must not carry an empty `usage`.** `_find_key`
       (`telemetry.py:103`) returns the first `usage` it meets, and
       `usage_from_response` then `setdefault`s `input_tokens`/`output_tokens`
       to `None` from it. For a claude dispatch the real counts live in the
       second candidate — the JSON nested in `result` — and `setdefault` will
       not overwrite a key already set to `None`. So a top-level `"usage": {}`
       written unconditionally silently zeroes claude's token accounting while
       every suite stays green. Write the key only when there is something in
       it.
     - **The keys must be the envelope's, not ACP's.** The test agent today
       reports `{"used": 7, "size": 100}` (`agent_bindings_test.sh:149`) —
       context occupancy, not tokens. `acp.py` should normalise whatever the
       agent reports into `input_tokens`/`output_tokens` and leave `Result.
       usage` empty when the agent reported neither, so the arm's "only when
       non-empty" rule has something to test.
     - Where it lands: `cost.py:227-236` selects `a.input_tokens,
       a.output_tokens` as the last two columns of the `ATTEMPT` row, so the
       assertion is on fields 8 and 9 of the same row A5 already matches on.
- Acceptance IDs: A1–A6.
- Validation: `zsh tests/agent_bindings_test.sh` — a wheel-installed
  `$VENV/bin/pm-flow` runs a cycle with an ACP developer to `GO`, an MCP
  client on the console script ticks a *named* section and only that section
  advances, and the packaged `cost` row for the ACP attempt carries `cli=acp`
  with non-empty token columns beside a `cli=claude` row. Plus
  `zsh tests/pm_flow_test.sh`, `zsh template/.agentic/pm_flow/tests/run.zsh`
  and `zsh tests/packaged_layout_test.sh` exit 0.
- Depends on: T2, T3.

## Integration and end-to-end validation

- T4 proves scenarios 1–3 through `.venv/bin/pm-flow`.

## Risks and rollback

- ACP is young; the client is isolated in one module and the arm can be
  removed without touching the other three.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T4 | ACP developer cycle reaches `GO` |
| A2 | T2, T4 | Existing suites exit 0, arms unchanged |
| A3 | T1, T2 | Access record precedes the attempt |
| A4 | T3, T4 | MCP client drives a project to `done` |
| A5 | T2, T4 | `cost` shows `cli=acp` and `cli=claude` |
| A6 | T1, T3, T4 | Section suite exits 0 |
