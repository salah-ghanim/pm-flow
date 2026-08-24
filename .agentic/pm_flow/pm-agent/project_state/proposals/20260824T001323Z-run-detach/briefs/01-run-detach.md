### Objective
- A run started with one command keeps going after its launcher exits or hangs up, tells the operator where its log is, and stops on request only after the dispatch in flight has finished and been recorded.

### Current baseline
- `pm-flow run` is a foreground child: `src/pm_flow/cli.py:81-87` → `pm_flow.sh:1923-1926` → `driver.zsh:2769-2852` (`cmd_run`), flag `--max-ticks` only; no pid file, no stop request, stdout only.
- The driver is level-triggered (`driver.zsh:3`): the same command resumes, and `pm-flow next` (`driver.zsh:2856`) shows the queue without dispatching; `pm-flow status` at `driver.zsh:2874`.
- Concurrency is refused by the driver's own locks (`driver.zsh:2198-2216`, `pm_flow.sh:876-885`), released when the process dies.
- A hangup that reaches `agent_exec.sh:836` ends the attempt as `failed (unknown)` (`agent_exec.sh:923-930`).
- Runtime records live under `<project>/runs/`, gitignored at `template/.agentic/pm_flow/.gitignore:15`; `PM_FLOW_RUNS_DIR` comes from `paths.py:252`.
- Test pattern: the `PM_FLOW_*` unset guard at `tests/pm_flow_test.sh:12-19`, agent doubles in `tests/fixtures/stub_*.zsh`.
- Host tooling: `/usr/bin/nohup` present, no `setsid` on macOS.

### Deliverables
- `template/.agentic/pm_flow/run_detach.zsh` with `start [--max-ticks N] [--section <key>]`, `stop`, `status`.
- `start` returns within seconds, prints the pid and the log path under `<project>/runs/`, and passes `--project`/`--section` through unchanged.
- `stop` records a stop request; the supervisor finishes the dispatch in flight, records it, starts no further tick, writes a final log line, and exits.
- `status` prints `running`, `stopping` or `idle` with pid, start time, tick count and log path; a pid file whose process is gone reads `idle`.
- `tests/run_detach_test.sh` and the stub agents it needs.
- `docs/run-detach.md`: how to start, find the log, stop, and resume.
- The `pm-flow run-detach` routing arm and `help` line in `pm_flow.sh`, once that file is this section's (see Constraints).

### User-visible scenarios
1. In a terminal, `pm-flow run-detach start`; it prints `pid=… log=<project>/runs/run-detach-<UTC>.log` and returns. Close the terminal. Minutes later, from a new terminal, `pm-flow run-detach status` reads `running`, the log has grown, and the dispatch that was in flight at the close ends with the developer's normal status, not `failed (unknown)`.
2. During a dispatch, `pm-flow run-detach stop` prints that the run will stop after the current dispatch; `status` reads `stopping`; when the dispatch ends, the log's last line says it stopped by request after tick N and `status` reads `idle`.
3. `pm-flow run-detach start` again: the next tick continues the same section's next action; nothing repeats.
4. `pm-flow run-detach start` while a run is live is refused, printing the live pid and log path, and starts nothing.

### Interfaces produced
- The `run-detach start|stop|status` command surface and its printed `pid=`/`log=` lines.
- The pid, stop-request and log files under `<project>/runs/`, named in `docs/run-detach.md`.

### Interfaces consumed
- `pm-flow run --max-ticks`, `pm-flow next`, `pm-flow status` and the driver's exit and lock conventions (`driver.zsh:2769-2852`, `2198-2216`), unchanged.
- `PM_FLOW_RUNS_DIR` and the layout from `src/pm_flow/paths.py`.
- The fixture pattern of `tests/pm_flow_test.sh` and `tests/fixtures/stub_*.zsh`.

### Scope
- In: the supervisor script, its three commands, launcher-independence, graceful stop, the log location, the test, the operator doc, and (gated) the routing arm.
- Out: any change to how the driver loops, locks, dispatches, retries, or classifies attempts.

### Non-goals
- Classifying a launcher hangup as a harness kill in the attempt record (`agent_exec.sh`, `driver.zsh`; agent-bindings and store-ledger territory).
- A hard-kill mode; `kill <pid>` exists.
- Auto-restart on usage-limit reset (`resume_claude.sh` at the repo root stays untracked and out).
- A service unit (launchd, systemd), a tmux/screen wrapper, a board or TUI, multi-project supervision.

### Priority
- nice-to-have: every completion criterion is reachable with a hand-run `nohup pm-flow run … &!`; this section saves one dispatch's spend and the operator's attention per launcher death and keeps harness kills out of the measured attempt record.

### Owned paths
- `template/.agentic/pm_flow/run_detach.zsh`
- `tests/run_detach_test.sh`
- `tests/fixtures/stub_detach*.zsh`
- `docs/run-detach.md`

### Dependencies
- `trace-commands` (owns `template/.agentic/pm_flow/pm_flow.sh`, where the routing arm goes).

### Constraints and fixed decisions
- No edit to `driver.zsh`, `agent_exec.sh`, `cli.py`, or `pm_flow.sh` while another section owns it; the supervisor composes existing commands (`run --max-ticks`, `next`, `status`) around the driver rather than changing the loop.
- `pm_flow.sh` joins this section's paths for one `case` arm and one `help` line only, at the first portfolio review after `trace-commands` reports done; until then the script is invoked directly and the doc says so.
- Stock macOS and Linux only: `nohup`, zsh job control or `os.setsid` from python3; no `setsid` binary, tmux, screen, launchd or systemd.
- `stop` is graceful only: the in-flight dispatch, including its child agent, is never signalled.
- Runtime files (pid, stop request, log) live under `<project>/runs/` and nowhere tracked.
- One live detached run per project; `start` reuses the driver's refusal rather than adding a second locking scheme beyond the pid liveness check.

### Acceptance
- A1: In `tests/run_detach_test.sh`, a launching shell runs `start`, the stub developer writes a marker then sleeps past the launcher's death, the launcher is sent SIGHUP and exits while the marker exists; the dispatch completes and the cycle records the stub's normal status, not `failed (unknown)`.
- A2: `status` reads `running` with pid, start time and log path while live, `idle` afterwards; with the pid file left behind and the process gone it reads `idle` and exits 0.
- A3: `stop` issued while a dispatch is in flight: the dispatch's result is recorded, no further tick starts, the log's last line names the tick it stopped after, `status` reads `idle`; checked in the test with a stub whose dispatch outlasts the stop.
- A4: A second `start` while one is live exits non-zero, prints the live pid and log path, and the tick count is unchanged.
- A5: After `stop` then `start`, the fixture section's next action is the one `pm-flow next` listed before the stop; the log shows no repeated tick.
- A6: `git status --porcelain` in the fixture repository is empty after start, stop and start again; every runtime file is under `<project>/runs/`.
- A7: Once the routing arm is this section's, `pm-flow run-detach status` and `pm-flow help` reach the script and list the command; `zsh tests/packaged_layout_test.sh` still exits 0.
- A8: `zsh tests/run_detach_test.sh`, `zsh tests/pm_flow_test.sh` and `zsh tests/packaged_layout_test.sh` exit 0; the new test opens with the `PM_FLOW_*` unset guard from `tests/pm_flow_test.sh:12-19`.

### Rejection conditions
- Survival is shown for the supervisor alone while the dispatched child dies, or the SIGHUP lands before the marker or after the stub has finished.
- `stop` signals the driver or its agent child, or a hard-kill mode is added.
- Any file outside Owned paths is modified, including `pm_flow.sh` before its release.
- The mechanism needs a binary or service absent from stock macOS.
- A runtime file lands outside `<project>/runs/` or shows in `git status`.

### Open questions
- None.

## Decision
CUT — no live section, cancelled reason, or existing command covers a run that outlives its launcher; it serves the plan's order-of-work bullet (the project-wide run two reviews call for) and the objective-metrics principle, on new paths, nice-to-have behind the five live must-haves.
