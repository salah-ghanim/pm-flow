# run-detach section PM state

## Current task

- None assigned. T3 was accepted in cycle 003; T1 and T2 were accepted in
  cycles 001 and 002. Every task this section can reach is done.
- T1a is the only task left and it cannot be assigned: it touches `install.sh`
  alone, which is not an owned path. The section is idle until the boundary
  extension is authorized (see Blockers).
- Cycle 004 scoped no assignment and reported `BLOCKED_EXTERNAL`. The blocker
  was re-probed at that scope rather than carried: `install.sh:47-67` still
  ends `… watch.py upgrade.py requirements-telemetry.txt README.md` and names
  none of the three stranded entries; `grep -rn "install.sh" brief.md` returns
  nothing, so the only boundary extension in `brief.md` remains the
  `pm_flow.sh` one authorized 2026-08-24; and
  `zsh tests/packaged_layout_test.sh` exits 1 with the same `got` list as
  cycle 003 (see Blockers).

## Completed tasks and evidence

- T1 — a detached run that outlives its launcher, and a status that reads it.
  Accepted cycle 001. Adds `template/.agentic/pm_flow/run_detach.zsh`,
  `tests/run_detach_test.sh`, `tests/fixtures/stub_detach.zsh` and nothing else
  (`git status --porcelain` in the worktree lists exactly those three as
  untracked; `git diff --stat HEAD` is empty).
  - A1, A2, A4, A6 (`start`) — `zsh tests/run_detach_test.sh` exits 0 in 21s:
    `PASS: launcher process-group SIGHUP leaves supervisor and dispatch alive`,
    `PASS: live, idle, and stale-pid status reporting`,
    `PASS: duplicate start refusal preserves tick state`,
    `PASS: detached runtime stays under the project runs directory`.
  - A1 is load-bearing, not incidental. Deleting the `os.setsid()` line from a
    scratch copy of the tree, so the loop is merely `&!`-backgrounded, turns the
    suite red: `FAIL: the supervisor died with its launcher`, exit 1. The
    detachment mechanism is what the test measures.
  - The mechanism is `python3 -c '… os.setsid(); os.execvp(…)'` at
    `run_detach.zsh:212` and nothing else: no `trap`, no `nohup`, no `setsid`
    binary, no tmux, screen, launchd or systemd anywhere in the file.
  - `os.setsid()` succeeds under interactive job control as well as
    non-interactively — probed both ways, the spawned child reported
    `pgid == sid == pid` in each. There is no EPERM path for an operator who
    types `start` at a terminal.
  - A8, new-suite leg — the suite opens with the `PM_FLOW_*` unset guard
    (`tests/run_detach_test.sh:12-19`). `zsh tests/pm_flow_test.sh` exits 0,
    all 10 groups PASS.

- T2 — graceful stop, and a resume that repeats nothing. Accepted cycle 002.
  Changes exactly the three assigned paths: `git status --porcelain` in the
  worktree lists ` M template/.agentic/pm_flow/run_detach.zsh`,
  ` M tests/run_detach_test.sh`, `?? tests/fixtures/stub_detach_stop.zsh` and
  nothing else. `install.sh` and `pm_flow.sh` untouched.
  - A3 — `zsh tests/run_detach_test.sh` exits 0 in 32s, four new groups PASS
    (`graceful stop outlasts and records the dispatch in flight`,
    `stopping becomes idle with one tick and no stop file`,
    `restart performs the next action without rewriting the stopped result`,
    `stop and restart keep runtime under runs and fixture porcelain empty`).
    Instrumented run of the same suite printed the stopped log verbatim:
    `[tick 1] stop-work: develop`, `develop 001 -> result (developer status:
    DELIVERED)`, then `[…] run-detach stopped by request after tick 1`, with
    `ticks=1` in `run-detach.state`. The group runs at `--max-ticks 4`, so the
    single tick is the stop's doing, not the budget's.
  - A5 — `next` before the stop printed `2 stop-work develop`; the stopped run
    performed `develop` and recorded it; `next` after the stop printed
    `2 stop-work review`; the restart's log reads `[tick 1] stop-work: review`
    and the pre-stop `result.md` mtime is unchanged (`st_mtime_ns` compared
    across the restart). Nothing was re-run, and the supervisor holds no cursor
    of its own — the resume is the driver's level-triggered `next`.
  - A6 (`stop`, second `start`) — `git status --porcelain` in the fixture repo
    is empty after the stopped-run `start` and after `stop`; after the restart
    it is exactly ` M .agentic/pm_flow/detach-repo/project_state/sections.md`,
    the driver's own tracked bookkeeping, which the test commits as
    `tests/run_detach_test.sh:188-192` already does rather than weakening the
    assertion. `find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*"` is
    empty at all three points, and `run-detach.stop` is gone after the loop
    exits.
  - The stop is graceful by construction, not by promise: the only `kill` in
    `run_detach.zsh` is the `kill -0` liveness probe at `:43`, and the file
    contains no `trap`. The stub's dispatch writes its woke marker after the
    stop and the cycle records `DELIVERED`.
  - The assertions have teeth, checked by mutation against scratch copies of
    the developer's tree:
    - `cmd_stop` writing no stop file → `FAIL: status during the stopped
      dispatch: expected to find 'stopping'`, exit 1.
    - both between-tick stop checks deleted from `loop_main` → `FAIL: stopped
      log final line: expected to find 'stopped by request after tick 1'`,
      exit 1.
    - the loop's trailing `rm -f -- "$STOP_FILE"` deleted → `FAIL: the honoured
      stop request was not removed`, exit 1.
  - A8, regression leg — `zsh tests/pm_flow_test.sh` exits 0, all 10 groups
    PASS. `zsh tests/packaged_layout_test.sh` exits 1 on the migration group
    and only that group, as expected while T1a is unauthorized.

- T3 — the command reaches the operator, and the doc says how. Accepted cycle
  003. Changes exactly the three assigned paths: `git status --porcelain` in the
  worktree lists ` M template/.agentic/pm_flow/pm_flow.sh`,
  ` M tests/run_detach_test.sh`, `?? docs/run-detach.md` and nothing else.
  `install.sh`, `driver.zsh`, `agent_exec.sh`, `cli.py` and `run_detach.zsh`
  untouched; `git diff --stat` is `pm_flow.sh | 11 +++`, `run_detach_test.sh |
  137 +++`, so the engine edit is the one `case` arm (`pm_flow.sh:1932-1941`)
  and the one `usage()` line (`:50`) the boundary extension authorizes.
  - A7 (reachable clauses) — `zsh tests/run_detach_test.sh` exits 0 in 56s with
    the new group passing: `PASS: routed run-detach covers help, start, status,
    stop, refusal, and stale-stop restart`. The group routes every command
    through `engine_command run-detach …`, never the script path, and asserts
    `log=$routed_log_path` on the routed `status` against the `log=` the routed
    `start` printed.
  - A7's `help` clause is not vacuous: `git show HEAD:…/pm_flow.sh | grep -c
    run-detach` is `0`, so the word the test looks for exists only because the
    `usage()` line was added.
  - A7's third clause — `zsh tests/packaged_layout_test.sh` exits 1 on the
    migration group and only that group, 8 PASS before it, `got` list
    `.gitignore .project-key artifact_quality.md cards config.json
    local_env.sh.example projects.md run_detach.zsh salvage-legacy `,
    byte-identical to the baseline in Blockers. T3 stranded nothing new and
    removed none of the three.
  - A6 — the routed group's captures printed verbatim from an instrumented run
    (restored byte for byte afterwards, `shasum -a 256` equal before and after):
    `A6 porcelain@506=[]`, `A6 stray-runtime@509=[]`, `A6 porcelain@534=[]`,
    `A6 stray-runtime@537=[]`, `A6 porcelain@546=[]`, `A6 stray-runtime@549=[]`
    — empty after the routed `start`, after the refused second `start` and after
    `stop`. The test commits the driver's own tracked cycle artifacts between
    steps, as `tests/run_detach_test.sh:188-192` does, rather than weakening the
    assertion.
  - A8 (reachable legs) — `zsh tests/run_detach_test.sh` exit 0 in 56s (9 groups
    PASS), `zsh tests/pm_flow_test.sh` exit 0 in 154s (10 groups PASS). The new
    group keeps the suite inside the two-minute budget.
  - The stale-stop case that T2's review carried is now proven, not shipped
    blind. Mutating `run_detach.zsh:221` from `rm -f -- "$PID_FILE" "$STOP_FILE"`
    to `rm -f -- "$PID_FILE"` turns the suite red — `FAIL: a stale stop request
    prevented the routed run from reaching two ticks`, exit 1 — and the file was
    restored to the same sha256.
  - The arm's `--section` guard is load-bearing too. Mutating
    `if [[ "${1:-}" == "start" && -n "$SECTION_OVERRIDE" ]]` to
    `if [[ -n "$SECTION_OVERRIDE" ]]` turns the suite red with
    `ERROR: status takes no arguments`, exit 1. That is the rejection condition
    about appending `--section` to `stop`/`status`, measured rather than assumed.

## Superseded

- The 2026-08-24 claim that "`pyproject.toml:47-51` force-includes all of
  `template/.agentic/pm_flow` into the wheel, so `run_detach.zsh` ships without
  touching a file this section does not own" was true but incomplete: packaging
  the file is not the same as *migrating* it. See the `install.sh` blocker.

## Active decisions

- The supervisor composes `run --max-ticks 1` per tick. The gap between two
  ticks is the only place a graceful stop can land, and it is a place the
  supervisor owns without touching `driver.zsh:2833-2911`.
- Detachment is a new session (`python3 -c 'import os; os.setsid()'`, or
  `nohup` plus `&!` if the result is a session leader), not a SIGHUP-ignoring
  parent. `agent_exec.sh` execs a vendor CLI that may reset the disposition, so
  inheritance of SIG_IGN cannot be relied on for the dispatched child, which
  A1 requires to survive.
- The supervisor re-enters `zsh "$SCRIPT_DIR/pm_flow.sh" … run --max-ticks 1`
  directly, not the `pm-flow` console script: `src/pm_flow/cli.py:77-87`
  exports the resolved layout, the detached process inherits it, and nothing
  then depends on the venv's `bin` being on the detached `PATH`. That
  inheritance is what direct invocation lacks, and direct invocation is the
  documented path until T3: with no `PM_FLOW_REPO_ROOT`/`PM_FLOW_FLOW_DIR` set,
  `pm_flow.sh:17-18` falls back to `$SELF_DIR/../..`, inside the venv for a
  packaged engine. So `start` resolves the tick command once —
  `$PM_FLOW_RUN_DETACH_CMD`, else the sibling `pm_flow.sh` when the layout is in
  the environment, else `pm-flow` from `PATH` — and records it in
  `run-detach.state`.
- A1's SIGHUP goes to the launcher's process *group*, not its pid. A
  non-interactive zsh leaves a background job in the launcher's own group rather
  than giving it one, so a merely backgrounded supervisor dies with that group
  while a session leader survives; signalling the pid alone would let a plain
  `&` implementation pass.
- `pyproject.toml:47-51` force-includes all of `template/.agentic/pm_flow` into
  the wheel, so `run_detach.zsh` ships without touching `pyproject.toml`, which
  is not an owned path.
- Runtime files are `run-detach.pid`, `run-detach.state`, `run-detach.stop` and
  `run-detach-<UTC>.log` under `$RUNS_DIR` (`pm_flow.sh:560`). `*/runs/*` at
  `template/.agentic/pm_flow/.gitignore:15` already excludes them, which is how
  A6 is met without a new ignore rule.
- Liveness is `kill -0` on the pid file, not a second lock. The driver's locks
  (`driver.zsh:2253-2274`) still refuse a concurrent dispatch; `start` only has
  to refuse a second supervisor.

## Blockers

- `zsh tests/packaged_layout_test.sh` exits 1 on main and no task in this
  workplan can make it exit 0 any more. Re-run at the cycle-004 scope,
  2026-08-25, 8 PASS then:
  `FAIL: the migrated flow directory holds project data only: expected
  '.gitignore .project-key config.json local_env.sh.example projects.md
  salvage-legacy ', got '.gitignore .project-key artifact_quality.md cards
  config.json local_env.sh.example projects.md run_detach.zsh salvage-legacy '`.
  Three entries are stranded, not one. `ls template/.agentic/pm_flow/` confirms
  `artifact_quality.md` (artifact-quality's) and `cards/` (persona-cards') now
  sit beside `run_detach.zsh`; `cards` is a directory, so it belongs in
  `COPIED_ENGINE_DIRS`, not `COPIED_ENGINE_FILES`. `install.sh:47-67` still
  lists `pm_flow.sh … README.md` and names none of the three.
- Cause, read in the source rather than inferred: `remove_copied_engine`
  (`install.sh:350-355`) deletes a copied engine file from a migrated flow
  directory only if it is named in `COPIED_ENGINE_FILES`, and
  `packaged_layout_test.sh:905` builds its legacy fixture with
  `/bin/cp -R "$REPO_ROOT/template/.agentic/pm_flow/." "$LEGACY_FLOW/"`, so any
  unregistered new engine file is left behind by design.
- This supersedes cycle 002's carried claim that one line in `install.sh` makes
  the suite exit 0. That was measured against a scratch tree that predates the
  other two entries; the *suite* is now a portfolio-level outcome, and T1a's
  reachable outcome is narrower: `run_detach.zsh` gone from the `got` list.
- What this section still needs, unchanged and now unanswered in four
  successive cycles (001, 002, 003, 004): one line in
  `brief.md` naming `install.sh`'s `COPIED_ENGINE_FILES` entry as this
  section's, on the model of the `pm_flow.sh` extension authorized 2026-08-24.
  `install.sh` is not an owned path and "any file outside Owned paths is
  modified" is a rejection condition, so this section cannot grant it to itself.
- What the portfolio review additionally has to decide, which is new this cycle:
  three sections are each stranding an engine entry, so the registration rule is
  a product-level gap rather than this section's oversight. Either one section
  is given `install.sh` for all three entries, or the rule is enforced where
  engine files are added. Until then A7's "`packaged_layout_test.sh` still exits
  0" and A8's third suite are unreachable from this section's owned paths, and
  T3 must be reviewed on the two suites it can turn green.
- Cycle 001's review recorded the escalation as made in `handoff.md`; it was
  not — the file was still the init scaffold. Corrected in cycle 002 and it
  stays there until answered.

## Active decisions (added cycle 001)

- Any new engine file under `template/.agentic/pm_flow/` has to be registered in
  `install.sh`'s `COPIED_ENGINE_FILES`, or migration strands it and
  `packaged_layout_test.sh` goes red. This is a standing cost of adding an
  engine file, not a one-off, and T3 must not repeat the omission.
- A6 was checked for `start` only, as assigned: `git status --porcelain` is
  empty immediately after `start`, and `find` shows no `run-detach*` file
  outside `<project>/runs/`. The fixture repository does go dirty later in the
  run, when the driver writes cycle artifacts under the tracked `.agentic/`
  tree; that is ordinary driver behaviour, not the supervisor's. A6 across
  start/stop/start is T2's.

## Active decisions (added cycle 002)

- Two facts about the shipped T1 code that T2 has to respect. `cmd_status`
  (`run_detach.zsh:233-236`) derives `stopping` from "pid file live *and* stop
  file present", so the loop's exit has to remove the pid file before the stop
  file or `status` reads `running` again after the stop was honoured. And
  because a hard-killed supervisor leaves `run-detach.stop` behind, `start`
  clears a stale stop file alongside the stale pid file it already clears
  (`run_detach.zsh:197-204`), or the next run stops after one tick for no
  reason.
- T1's test proves nothing about stop ordering, because it runs with
  `--max-ticks 1`: the loop exits at its budget after a single tick either way.
  T2's case has to run with a budget above 1, or a `stop` that does nothing at
  all still passes.
- A5 as the cycle-002 assignment worded it — "the action `next` named before the
  stop is the action taken after the restart" — is unsatisfiable, and the
  shipped test is right not to assert it. The stopped tick *completes* the
  action `next` named (`develop`), so `next` necessarily advances to `review`
  before the restart; asserting the restart repeats `develop` would assert the
  repetition `brief.md`'s scenario 3 forbids. The test instead pins both halves:
  the stopped run's log performs the pre-stop action, and the restart's log
  performs the post-stop one, with the pre-stop artifact's mtime unchanged.
  Any re-wording of A5 in a future assignment must keep that pairing.
- The claim that `start`'s stale-stop-file clearing is unproven is closed by
  T3's group and its mutation; see T3's evidence above.

## Active decisions (added cycle 003)

- The routed and script-path entries resolve one runs directory, pinned by the
  test rather than asserted: the routed `start`'s `log=` is checked to be under
  the same `$RUNS_DIR` the script-path groups use, the test writes its stray
  `run-detach.stop` into that directory and the routed `start` clears it, and
  the stale-stop tick count is read from the same `$STATE_FILE`.
- The routed group exercises project resolution only in the `--project`-given
  case, because `engine_command` (`tests/run_detach_test.sh:141-146`) always
  passes `--project`. `resolve_project`'s no-`--project` fallthrough to
  `$PM_FLOW_FLOW_DIR/$PROJECT_KEY/runs` is unexercised through the arm. Not a
  defect of T3 — the assignment fixed that wrapper — but it is the one routing
  path with no test.
- Two of `brief.md`'s four scenarios are routed end to end (the graceful stop of
  scenario 2 and the refusal of scenario 4); scenario 1's launcher-hangup leg
  and scenario 3's no-repeat assertion stay on the script-path groups from T1
  and T2. The arm is a pure argv rebuild with no behaviour of its own, and both
  mutations show the routed group reaches the supervisor, so re-driving those
  two legs would re-measure the supervisor rather than the arm.

## Next eligible task

- None this section can assign. T1, T2 and T3 are done and T1a is blocked on an
  owned-path authorization it cannot grant itself.
- T1a lands whenever the boundary extension is authorized. Its outcome is
  narrow — `run_detach.zsh` off the migration `got` list — and it does not make
  `packaged_layout_test.sh` exit 0; `artifact_quality.md` and `cards` are other
  sections'.
- What the section is *not* is complete. A7's third clause and A8's third suite
  have no current evidence and cannot get any from an owned path, so `COMPLETE`
  would be a claim the ledger contradicts. Either the portfolio review grants
  the extension and decides who registers the other two entries, or it narrows
  those two criteria to "adds no new stranded entry", which T3's evidence
  already meets. Both are its calls, not this section's.
