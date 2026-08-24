# run-detach section handoff

## Outcome

- T1 accepted (cycle 001): `pm-flow` runs can now be started detached. `zsh
  <engine>/run_detach.zsh start` returns having printed `pid=` and `log=`, and
  both the supervisor and the agent child it dispatched survive a SIGHUP aimed
  at the launching terminal's process group; the dispatch is recorded with the
  developer's normal status. `status` reads `running` or `idle` with pid, start
  time, tick count and log path. A second `start` while one is live is refused.
  A1, A2, A4 and A6-for-`start` are met by `zsh tests/run_detach_test.sh`,
  exit 0 in 21s, four PASS groups.
- T2 (graceful stop and a resume that repeats nothing) is assigned in cycle 002.
  `stop` does not exist yet; the command surface is `start` and `status`.

## Decisions

- The supervisor composes `pm-flow run --max-ticks 1` one tick at a time rather
  than changing the driver's loop. The gap between two ticks is the only place
  a graceful stop can land, and it is a place the supervisor owns.
- Detachment is a new session — `python3 -c 'import os; os.setsid(); …'` and
  nothing else. Not a SIGHUP trap: `agent_exec.sh` execs a vendor CLI that may
  reset an inherited disposition, so the dispatched child would be unprotected.
  This is load-bearing, not incidental: deleting that one line turns the suite
  red with `FAIL: the supervisor died with its launcher`.
- Runtime files (`run-detach.pid`, `.state`, `.stop`, `run-detach-<UTC>.log`)
  live under `<project>/runs/`, already excluded by `*/runs/*` in
  `template/.agentic/pm_flow/.gitignore:15`. No new ignore rule was needed.

## Interfaces

- New command surface `run-detach start [--max-ticks N] [--section <key>] |
  stop | status`, today reachable only as `zsh <engine>/run_detach.zsh …`. The
  `pm-flow run-detach` routing arm is T3's, under the boundary extension
  authorized 2026-08-24.
- `start` prints exactly two machine-readable lines, `pid=<n>` and
  `log=<project>/runs/run-detach-<UTC>.log`.
- Nothing in `driver.zsh`, `agent_exec.sh`, `cli.py` or the store changed, and
  nothing about them needs to.

## Risks

- **`zsh tests/packaged_layout_test.sh` is red on main and stays red until this
  section is allowed to touch `install.sh`.** Observed: `FAIL: the migrated flow
  directory holds project data only: expected '… projects.md salvage-legacy ',
  got '… projects.md run_detach.zsh salvage-legacy '`. Cause read in the source,
  not inferred: `remove_copied_engine` (`install.sh:350-355`) deletes a copied
  engine file from a migrated flow directory only if it is named in
  `COPIED_ENGINE_FILES` (`install.sh:47-67`), and `packaged_layout_test.sh:905`
  builds its legacy fixture by copying the whole engine template in. Any
  unregistered new engine file is stranded by design.
- **The request, unchanged from cycle 001 and still unanswered.** Add one line
  to `brief.md`'s Owned paths naming `install.sh`'s `COPIED_ENGINE_FILES`
  entry as this section's, on the model of the `pm_flow.sh` extension
  authorized 2026-08-24. `install.sh` is not an owned path and "any file
  outside Owned paths is modified" is a rejection condition, so this section
  cannot grant it to itself. The fix is proven: adding the single line
  `run_detach.zsh` to that array in a scratch copy makes the suite exit 0 with
  all 13 groups passing, including `PASS: a copied-engine repository migrates
  losslessly and keeps running`.
- Cycle 001's review said this was escalated here. It was not — `handoff.md`
  was still the init scaffold, so no portfolio review could have seen the
  request. That is corrected with this file; the delay is the section's, not
  the reviewer's.
- **The omission generalises.** Registering a new engine file in `install.sh` is
  a standing cost of adding one, for every section, not a one-off of this one.
- T1a is held rather than blocking. It touches `install.sh` alone, so T2
  proceeds in parallel; only T3 is genuinely gated, since it claims A8 in full
  and cannot be accepted while a suite is red.

## What is unproven

- `stop` in every respect: that it is graceful, that the in-flight dispatch is
  never signalled, that no further tick starts, and that a `start` after a stop
  resumes without repeating a tick (A3, A5). T2 is assigned to prove it.
- The `stopping` state ships unexercised by design — `cmd_status` has the
  branch, but nothing creates `run-detach.stop` until T2.
- A6 has been checked after `start` only. Across start/stop/start it is T2's.
  Note the fixture repository does go dirty later in a run, when the driver
  writes cycle artifacts under the tracked `.agentic/` tree; that is ordinary
  driver behaviour, not the supervisor's.
- A7 entirely: no routing arm, no `help` line, no `docs/run-detach.md`.

## Next action

- Cycle 002 develops T2. The portfolio review's part is the one-line owned-path
  extension for `install.sh` above; without it the repository keeps a red suite
  and T3 cannot be accepted.
