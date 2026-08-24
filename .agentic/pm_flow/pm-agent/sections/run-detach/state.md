# run-detach section PM state

## Current task

- None assigned. T1 accepted in cycle 001; T1a is next and needs an owned-path
  authorization first (see Blockers).

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

- `zsh tests/packaged_layout_test.sh` exits 1 with T1 merged, and stays red
  until T1a lands. Observed:
  `FAIL: the migrated flow directory holds project data only: expected
  '.gitignore .project-key config.json local_env.sh.example projects.md
  salvage-legacy ', got '… projects.md run_detach.zsh salvage-legacy '`.
  Cause, read in the source rather than inferred: `remove_copied_engine`
  (`install.sh:350-355`) deletes a copied engine file from a migrated flow
  directory only if it is named in `COPIED_ENGINE_FILES` (`install.sh:47-67`),
  and `packaged_layout_test.sh:905` builds its legacy fixture with
  `/bin/cp -R "$REPO_ROOT/template/.agentic/pm_flow/." "$LEGACY_FLOW/"`, so an
  unregistered new engine file is left behind by design.
  Fix, already proven: adding the single line `run_detach.zsh` to
  `COPIED_ENGINE_FILES` in a scratch copy of the developer's tree makes the
  suite exit 0 with all 13 groups passing, including
  `PASS: a copied-engine repository migrates losslessly and keeps running`.
  This is not the developer's failure — `install.sh` was outside the three
  writable paths the assignment named, and the assignment was wrong to require
  A8 in full without it.
- That fix needs an owned-path extension. `install.sh` is not in `brief.md`'s
  Owned paths and "any file outside Owned paths is modified" is a rejection
  condition, so this section cannot authorize it for itself. Escalated in
  `handoff.md` for the next portfolio review, on the model of the `pm_flow.sh`
  extension authorized 2026-08-24. The observation that unblocks it is one line
  in `brief.md` naming `install.sh`'s `COPIED_ENGINE_FILES` entry as this
  section's.

## Active decisions (added this cycle)

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

## Next eligible task

- T1a (register `run_detach.zsh` in `install.sh`; A8's packaged-layout leg) —
  one line, and it returns the repository to three green suites. Assignable as
  soon as the boundary extension above is authorized.
- Then T2 (graceful stop and resume; A3, A5), then T3 (routing arm, operator
  doc, end-to-end; A7), whose `pm_flow.sh` case arm and `help` line are already
  this section's under the 2026-08-24 extension.
