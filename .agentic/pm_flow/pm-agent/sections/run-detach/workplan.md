# run-detach workplan

## Design summary

- One new engine script, `template/.agentic/pm_flow/run_detach.zsh`, supervises
  the existing driver instead of changing it. It composes `pm-flow run
  --max-ticks 1` one tick at a time, so the boundary between two dispatches -
  the only place a graceful stop can land - is a place the supervisor already
  controls, and no edit to `driver.zsh`'s loop is needed.
- Launcher independence comes from a new session, not from ignoring a signal.
  `start` re-execs the supervisor loop through `python3 -c 'import os; os.setsid()'`
  (or `nohup` plus zsh's `&!`, provided the result is a session leader), so a
  SIGHUP directed at the launching terminal's process group never reaches the
  supervisor *or* the dispatched agent child. Ignoring SIGHUP in the supervisor
  alone is not enough: `agent_exec.sh` execs a vendor CLI that may reset the
  disposition, and the rejection conditions in `brief.md` fail a run whose
  child dies.
- The supervisor re-enters the engine directly - `zsh "$SCRIPT_DIR/pm_flow.sh"
  … run --max-ticks 1` - rather than through the `pm-flow` console script. The
  layout `src/pm_flow/cli.py:77-87` exported into the environment is inherited
  by the detached process, so the project resolves identically without assuming
  the venv's `bin` is on the detached `PATH`.
- That inheritance is exactly what a *direct* invocation lacks, and until T3
  lands direct invocation is the documented path. With no `PM_FLOW_REPO_ROOT`
  or `PM_FLOW_FLOW_DIR` in the environment, `pm_flow.sh:17-18` falls back to
  `$SELF_DIR/../..`, which for a packaged engine is inside the venv rather than
  the operator's repository. So the engine command is resolved once, by `start`,
  in this order: `$PM_FLOW_RUN_DETACH_CMD` (escape hatch and test seam); the
  sibling `pm_flow.sh` when the layout is already in the environment; otherwise
  `pm-flow` from `PATH`, which resolves the layout itself. The resolved command
  is recorded in `run-detach.state` and reused by every tick, so a run cannot
  change engines halfway.
- Runtime state is three files under `$RUNS_DIR` (`pm_flow.sh:560`,
  `PM_FLOW_RUNS_DIR` from `paths.py:252`), which `*/runs/*` at
  `template/.agentic/pm_flow/.gitignore:15` already excludes from git:
  `run-detach.pid`, `run-detach.state`, `run-detach-<UTC>.log`. Stop is a
  fourth, `run-detach.stop`, created by `stop` and deleted by the supervisor as
  it exits.
- Liveness is `kill -0 <pid>`, not a lock: the driver's own locks
  (`driver.zsh:2253-2274`) still refuse a concurrent dispatch, so `start` only
  has to refuse a second *supervisor*.

## Interfaces and data changes

- New command surface `run-detach start [--max-ticks N] [--section <key>] |
  stop | status`, reachable directly as `zsh <engine>/run_detach.zsh …` and,
  from T3, as `pm-flow run-detach …`.
- `start` prints exactly two machine-readable lines, `pid=<n>` and
  `log=<project>/runs/run-detach-<UTC>.log`, then returns.
- `$RUNS_DIR` is resolved by the script itself, in this order: `$PM_FLOW_RUNS_DIR`;
  `$PM_FLOW_PROJECT_DIR/runs`; `${PM_FLOW_FLOW_DIR:-$SCRIPT_DIR}/<key>/runs`,
  where `<key>` is `--project`, `$PM_FLOW_PROJECT`, or the first line of
  `<flow dir>/.project-key` - the same order `resolve_project_key`
  (`pm_flow.sh:170-190`) uses.
- `$RUNS_DIR/run-detach.pid` - supervisor pid, one line.
- `$RUNS_DIR/run-detach.state` - `key=value` lines: `pid`, `started_at` (UTC
  ISO), `log`, `section`, `max_ticks`, `engine`, `ticks` (rewritten atomically -
  temp file then `mv` - by the loop after each tick, so a `status` racing a tick
  never reads a half-written file).
- `$RUNS_DIR/run-detach.stop` - presence is the stop request; its content is
  the UTC stamp of the request.
- `$RUNS_DIR/run-detach-<UTC>.log` - the supervisor's own lines plus every
  tick's stdout and stderr.
- No change to any driver, agent, CLI or store interface.

## Task T1 — a detached run that outlives its launcher, and a status that reads it

- Status: done — A1, A2, A4 and A6 (`start`) met, and A8's new-suite leg met.
  A8's `packaged_layout_test.sh` leg is carried to T1a: registering a new engine
  file with `install.sh` was never in T1's writable paths.
- Outcome: `zsh <engine>/run_detach.zsh start` returns within seconds having
  printed `pid=` and `log=`; the supervisor and the agent child it dispatched
  both survive a SIGHUP to the launching shell's process group and the dispatch
  is recorded with the stub's normal status; `status` reads `running` with pid,
  start time, tick count and log path while live and `idle` once the process is
  gone, including when a stale pid file is left behind; a second `start` while
  one is live exits non-zero, prints the live pid and log path, and dispatches
  nothing.
- Paths: `template/.agentic/pm_flow/run_detach.zsh` (new),
  `tests/run_detach_test.sh` (new), `tests/fixtures/stub_detach.zsh` (new).
- Reuse: the tick loop and its refusals in `driver.zsh:2833-2911` through
  `run --max-ticks 1`; `$RUNS_DIR` from `pm_flow.sh:560`; the exported layout
  from `src/pm_flow/paths.py:252`; the `PM_FLOW_*` unset guard and the
  `fail`/`assert_contains`/`assert_file_contains` helpers at
  `tests/pm_flow_test.sh:12-19,36-61`; the fixture-repo pattern - `install.sh`
  into a `mktemp -d`, `init-section`, a stub `claude` on `PATH` via a
  `driver-bin` directory - at `tests/pm_flow_test.sh:998-1056`; the stub's
  prompt dispatch and `retire_workplan_scaffold` shape in
  `tests/fixtures/stub_success.zsh`.
- Behaviour: `start` refuses when `run-detach.pid` names a live process
  (`kill -0`) and clears the pid file when it does not; otherwise it writes the
  log path, spawns the loop in a new session, writes `run-detach.pid` and
  `run-detach.state`, prints the two lines and returns without waiting for the
  first tick. The loop appends a start line, then per iteration runs one tick,
  appends its output, increments `ticks` in the state file, and stops when the
  driver reports no actionable work or `--max-ticks` is reached; on exit it
  appends a final line and removes the pid file. `status` prints `running`,
  `stopping` or `idle` plus `pid=`, `started_at=`, `ticks=`, `log=`, and exits
  0 in every case, treating a pid file whose process is gone as `idle`.
  (`stopping` is only reachable once T2 lands; the branch exists here so the
  states are one function.)
- The hangup has to be delivered the way a closing terminal delivers it, or the
  test proves nothing: SIGHUP goes to the *launcher's process group*, not to the
  launcher pid alone. A non-interactive zsh does not put a background job in its
  own group, so a supervisor that had merely been backgrounded shares that group
  and dies, while a session leader does not - that difference is what A1 is
  measuring. The launcher is therefore given a group of its own (start it
  through the same `os.setsid()` shim), and the test signals `-<launcher pid>`.
  Signalling only the launcher pid would leave a plain `&` implementation
  passing.
- Acceptance IDs: A1, A2, A4; A6 for `start`; A8 for the new suite.
- Validation: `zsh tests/run_detach_test.sh` exits 0, with the SIGHUP case
  asserting the marker file exists before the signal, the launcher pid is gone
  after it, and the cycle record for the dispatch does not read
  `failed (unknown)`; `zsh tests/pm_flow_test.sh` and
  `zsh tests/packaged_layout_test.sh` still exit 0.
- Depends on: None.

## Task T1a — the new engine file survives a migration

- Status: pending, waiting on an owned-path authorization, and now the only
  unfinished task in this workplan. While T2 and T3 were open it was held
  rather than blocking — it touches `install.sh` and nothing else, so the
  section worked around it instead of idling behind a permission it cannot
  grant itself. That room is gone: T1, T2 and T3 are accepted, so from cycle
  004 the section has no executable task and reports `BLOCKED_EXTERNAL` until
  the extension is granted or refused. Re-probed at the cycle-004 scope rather
  than carried: `install.sh:47-67` still names none of the three stranded
  entries, and `brief.md` still carries only the `pm_flow.sh` extension of
  2026-08-24.
- Scope corrected 2026-08-25, from a run of the suite on main rather than from
  cycle 002's carried claim: `run_detach.zsh` is no longer the only unregistered
  engine file. Observed
  `FAIL: the migrated flow directory holds project data only: expected
  '.gitignore .project-key config.json local_env.sh.example projects.md
  salvage-legacy ', got '.gitignore .project-key artifact_quality.md cards
  config.json local_env.sh.example projects.md run_detach.zsh salvage-legacy '`.
  `artifact_quality.md` is the artifact-quality section's and `cards` is the
  persona-cards section's — and `cards` is a directory, so it belongs in
  `COPIED_ENGINE_DIRS`, not `COPIED_ENGINE_FILES`. Neither is this section's to
  register. So T1a's one line no longer makes the suite exit 0, and no task in
  this workplan can: the suite's exit 0 is now a portfolio-level outcome. T1a's
  outcome is narrowed to removing this section's own entry from that list.
- Why it exists: `install.sh` removes a copied engine file from a migrated flow
  directory only if the file is named in `COPIED_ENGINE_FILES`
  (`install.sh:47-67`, `remove_copied_engine` at `install.sh:350-355`).
  `packaged_layout_test.sh:905` builds its legacy fixture by copying the whole
  of `template/.agentic/pm_flow/` in, so every new engine file must be
  registered or migration strands it. `run_detach.zsh` is the first new engine
  file this section adds, so shipping T1 turns
  `packaged_layout_test.sh:1017-1020` red until this lands.
- Outcome: a migrated flow directory has no `run_detach.zsh` left behind — the
  migration group's `got` list no longer names it. The group still fails while
  `artifact_quality.md` and `cards` are unregistered; that is the other
  sections' work, escalated in `handoff.md`, not a defect of this task.
- Paths: `install.sh` — one line, `run_detach.zsh` added to
  `COPIED_ENGINE_FILES`, and nothing else.
- Authorization required: `install.sh` is not in `brief.md`'s Owned paths, and
  "any file outside Owned paths is modified" is one of its rejection
  conditions. The next portfolio review has to extend the boundary the way it
  extended it for `pm_flow.sh` on 2026-08-24 before this is assignable.
- Behaviour: insert `run_detach.zsh` into the `COPIED_ENGINE_FILES` array. No
  other install, migration or packaging change; `pyproject.toml:47-51` already
  force-includes the file into the wheel.
- Acceptance IDs: this section's share of A8's `packaged_layout_test.sh` leg.
- Validation: `zsh tests/packaged_layout_test.sh`; the migration group's `got`
  list no longer contains `run_detach.zsh`. Exit 0 is no longer the expected
  observation and was not when cycle 002's review recorded it — the scratch-copy
  run that produced 13 passing groups predates `artifact_quality.md` and
  `cards`. That claim is superseded, not carried.
- Depends on: T1.

## Task T2 — graceful stop, and a resume that repeats nothing

- Status: done — A3, A5 and A6 (`stop` and the second `start`) met, accepted
  cycle 002. A8's `packaged_layout_test.sh` leg still sits with T1a.
- Outcome: `stop` issued while a dispatch is in flight prints that the run will
  stop after the current dispatch and exits 0; the in-flight dispatch is never
  signalled, finishes, and is recorded; no further tick starts; the log's last
  line names the tick it stopped after; `status` reads `stopping` while the
  dispatch finishes and `idle` afterwards. A `start` after that stop continues
  with the action `pm-flow next` listed before the stop, and the log shows no
  repeated tick.
- Paths: `template/.agentic/pm_flow/run_detach.zsh`,
  `tests/run_detach_test.sh`, `tests/fixtures/stub_detach*.zsh`.
- Reuse: T1's state file and liveness predicate; the level-triggered resume the
  driver already guarantees (`driver.zsh:3`) - the supervisor must add no
  cursor of its own; `pm-flow next` (`pm_flow.sh:1935`) as the before/after
  probe in the test.
- Behaviour: `stop` writes `run-detach.stop` and returns immediately when a
  supervisor is live; with none live it says so and exits 0 without creating
  the file. The loop tests for `run-detach.stop` only between ticks, never
  during one, and never signals the tick child or its agent. On a stop it
  appends `stopped by request after tick <n>`, removes the stop file and the
  pid file, and exits. The stop-outlasting stub is a second fixture whose
  developer dispatch sleeps past the `stop` call.
- Two details the shipped T1 code makes load-bearing. `cmd_status`
  (`run_detach.zsh:233-236`) reads `stopping` as "pid file live *and* stop file
  present", so the loop must drop the pid file *before* the stop file on its way
  out; the reverse order shows `running` again after the stop was honoured.
  And a supervisor killed hard leaves `run-detach.stop` behind, which would make
  the next run stop after one tick for no reason, so `start` clears a stale stop
  file in the same branch where it already clears a stale pid file
  (`run_detach.zsh:197-204`) — one line, inside this task because this task is
  what creates the file.
- Acceptance IDs: A3, A5; A6 for `stop` and the second `start`.
- Validation: `zsh tests/run_detach_test.sh` exits 0, asserting the stub's
  post-stop marker (proving the dispatch was not signalled), the recorded
  cycle result, the final log line, `status` reading `stopping` then `idle`,
  the tick numbering across the two runs, and `git status --porcelain` empty in
  the fixture repository after start, stop and start.
- Depends on: T1.

## Integration and end-to-end validation

- T3 is that task: it puts the command where the operator types it and drives
  all four user-visible scenarios of `brief.md` end to end through
  `pm-flow run-detach`.

## Task T3 — the command reaches the operator, and the doc says how

- Status: done — A7 (its reachable clauses), A6 and A8 (the two suites this
  section can turn green) met, accepted cycle 003. A7's and A8's
  `packaged_layout_test.sh` legs remain portfolio-level; T1a still holds this
  section's share.
- Outcome: `pm-flow run-detach start|stop|status` reaches the supervisor
  through the routing arm; `pm-flow help` lists the command; `docs/run-detach.md`
  tells an operator how to start a run, find its log, stop it and resume, and
  names the runtime files; the test drives all four user-visible scenarios of
  `brief.md` through `pm-flow run-detach` rather than through the script path.
- Paths: `template/.agentic/pm_flow/pm_flow.sh` (one `case` arm and one `help`
  line only, per the authorized boundary extension in `brief.md`),
  `docs/run-detach.md` (new), `tests/run_detach_test.sh`.
- Reuse: the routing shape of the `run)` arm at `pm_flow.sh:1927-1930` and the
  usage block at `pm_flow.sh:35-81`; `SCRIPT_DIR` and the `SECTION_OVERRIDE`
  set by the global flag parse at `pm_flow.sh:1892-1896`; the packaged-engine
  force-include at `pyproject.toml:51`, which ships the new script with no
  packaging edit.
- Behaviour: the arm forwards the remaining arguments to `run_detach.zsh` and
  passes the global `--section` through, so `pm-flow --section <key> run-detach
  start` supervises one section. Nothing else in `pm_flow.sh` changes. The doc
  states that the runtime files live under `<project>/runs/`, that stop is
  graceful only, and that `kill <pid>` remains the hard exit.
- Argument shape, which the arm has to get right because the two parsers differ.
  `main()` (`pm_flow.sh:1885-1903`) has already stripped `--project` and
  `--section` into `PROJECT_OVERRIDE` and `SECTION_OVERRIDE` before the `case`
  is reached, while `run_detach.zsh` takes `--project` *before* the subcommand
  (`:281-291`) and `--section` only *inside* `start` (`:203-207`); `stop` and
  `status` `fail` on any argument at all (`:296-297`). So the arm rebuilds:
  `--project` first when `PROJECT_OVERRIDE` is set, then the subcommand and its
  arguments, then `--section` appended only when the subcommand is `start`.
- Project resolution has to agree across the two entry paths or the routed
  `status` reads a different runs directory than the script path does.
  `initialize_project_paths` exports `PM_FLOW_PROJECT` (`pm_flow.sh:555`), and
  `cli.py:77-79` exports `PM_FLOW_FLOW_DIR` always but `PM_FLOW_RUNS_DIR` and
  `PM_FLOW_PROJECT_DIR` only when `--project` was given
  (`paths.py:242-256`). `resolve_project` (`run_detach.zsh:67-93`) falls through
  to `$PM_FLOW_FLOW_DIR/$PROJECT_KEY/runs`, which is `$PROJECT_DIR/runs`
  (`pm_flow.sh:560`), so the two agree in both cases — the test pins it rather
  than the workplan asserting it.
- Acceptance IDs: A7 except its `packaged_layout_test.sh` clause; A6 and A8
  across the two suites this section can turn green.
- Validation: `zsh tests/run_detach_test.sh` and `zsh tests/pm_flow_test.sh`
  exit 0; `zsh tests/packaged_layout_test.sh` fails on the migration group and
  only that group, with a `got` list unchanged by this task; the engine `help`
  output contains `run-detach`; the fixture repository's
  `git status --porcelain` is empty after the full scenario.
- What this task cannot deliver, and why it is not a defect of it: A7's
  "`packaged_layout_test.sh` still exits 0" and A8's third suite are not
  reachable from this section's owned paths. `artifact_quality.md` and `cards`
  strand migration too, and both belong to other sections. Escalated in
  `handoff.md`; the review should accept T3 on the two suites plus an unchanged
  migration `got` list, and must not accept a T3 that fixes the other sections'
  entries.
- Carried from T2's review: `start`'s stale-stop clearing
  (`run_detach.zsh:221`) is shipped but unproven — a gracefully stopped loop
  always removes its own stop file, so no test manufactures a stale one.
  Deleting `"$STOP_FILE"` from that `rm` leaves the suite green. T3's group
  writes a stray `run-detach.stop`, runs `start --max-ticks 2`, and asserts the
  run reaches tick 2.
- Depends on: T2.

## Risks and rollback

- The SIGHUP test can pass for the wrong reason if the signal lands before the
  stub has been dispatched or after it has finished. The stub writes a marker
  before sleeping and a second marker after waking; the test waits for the
  first and asserts the second, so a mistimed signal fails rather than passes.
- `python3 -c` inside `start` costs an interpreter start per run, not per tick;
  if that proves unacceptable, `nohup … &!` is the fallback, but only with the
  child-survival assertion of A1 still green.
- Rollback for T1 and T2 is deleting `run_detach.zsh`, its test and its
  fixtures - no other file has changed. Rollback for T3 is additionally
  reverting one `case` arm and one `help` line in `pm_flow.sh`.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1 | `tests/run_detach_test.sh`: marker written, launcher SIGHUPed and gone, dispatch completes, recorded status is the stub's normal one, not `failed (unknown)` |
| A2 | T1 | `status` output while live shows `running` with pid, start time and log; after exit, and with a stale pid file, shows `idle` and exit 0 |
| A4 | T1 | second `start` exits non-zero, prints the live pid and log path, tick count in `run-detach.state` unchanged |
| A3 | T2 | in-flight dispatch recorded, no further tick, final log line names the tick, `status` reads `stopping` then `idle` |
| A5 | T2 | `pm-flow next` before the stop matches the action taken after the restart; tick numbering shows no repeat |
| A6 | T1, T2, T3 | `git status --porcelain` empty in the fixture repo after start, stop, start; every runtime file under `<project>/runs/` |
| A7 | T3 | `run-detach status` reaches the script through the routing arm, `help` lists the command. Its `packaged_layout_test.sh` clause is **not reachable from this section**: `artifact_quality.md` and `cards` strand migration alongside `run_detach.zsh` and belong to other sections. T3 proves the arm adds no new failure; T1a removes this section's entry |
| A8 | T1, T1a, T2, T3 | `run_detach_test.sh` and `pm_flow_test.sh` exit 0 and the new suite opens with the `PM_FLOW_*` unset guard — T1, T2, T3. The `packaged_layout_test.sh` leg is portfolio-level: T1a takes `run_detach.zsh` off the stranded list, the other two entries are other sections' |
