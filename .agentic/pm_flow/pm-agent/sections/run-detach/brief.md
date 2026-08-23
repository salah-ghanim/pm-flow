## Objective

- A run started from a terminal keeps going when that terminal or the process
  that launched it goes away, and a person can find its log and stop it.

## Current baseline

- `pm-flow run` (`src/pm_flow/cli.py` → `zsh pm_flow.sh run`) is a foreground
  child of whatever launched it. When that launcher died mid-cycle on
  2026-08-23, the Codex developer it had dispatched was killed four minutes
  in, the attempt was recorded as `failed (unknown)`, and the driver died
  before retrying; a second `run` had to be started by hand with
  `nohup … &!`.
- The driver is level-triggered, so resuming is the same command; only the
  spend of the killed attempt is lost.

## Deliverables

- `pm-flow run --detach [--max-ticks n]`: starts the run in its own session,
  immune to the launcher's hangup, writes to
  `.agentic/pm_flow/<project>/runs/run-<stamp>.log`, prints that path and
  the pid, and returns.
- `pm-flow run --stop`: ends a detached run after its current dispatch.
- `pm-flow status` shows a detached run's pid and log when one is live.

## User-visible scenarios

1. `pm-flow run --detach --max-ticks 20` prints `pid=… log=…` and returns;
   closing the terminal does not end the run; `tail -f <log>` shows ticks.
2. `pm-flow run --stop` while a developer is mid-dispatch: the dispatch
   finishes, its review runs, no further tick starts, and `status` no longer
   lists a live run.
3. A second `run --detach` while one is live is refused with the live pid.

## Interfaces produced

- The `--detach` and `--stop` flags; the run log path convention.

## Interfaces consumed

- `.driver.lock` in the project directory; `pm_flow.sh run`.

## Scope

- In: detaching, the log, the stop signal, the status line, tests.
- Out: a service manager integration; running as a different user.

## Non-goals

- Surviving a reboot.
- Changing what a tick does.

## Priority

- nice-to-have: `nohup pm-flow run … &!` already works by hand; without this
  a run started carelessly dies with its terminal and one attempt's spend is
  lost.

## Owned paths

- `src/pm_flow/detach.py`
- `tests/run_detach_test.sh`

## Dependencies

- topology-compare

## Constraints and fixed decisions

- The flags are parsed in `src/pm_flow/cli.py`, owned by `topology-compare`
  until it closes; that is the dependency. The detach logic itself lives in
  `detach.py`.
- Stop is cooperative: a marker file the driver checks between ticks, never
  a signal to a dispatched role.

## Acceptance

- A1: In `tests/run_detach_test.sh`, a stub-driven `run --detach` returns
  within two seconds with `pid=` and `log=`; killing the launching shell with
  `SIGHUP` leaves the run alive and it completes its ticks into the log.
- A2: `run --stop` during a stub dispatch lets that dispatch and its review
  finish and starts no further tick; the log ends with a stop line.
- A3: `run --detach` while a run is live exits non-zero naming the live pid
  and starts nothing.
- A4: `pm-flow status` prints the live run's pid and log path, and nothing
  after it ends.
- A5: `zsh tests/run_detach_test.sh` and `zsh tests/pm_flow_test.sh` exit 0.

## Rejection conditions

- A detached run is stopped by a signal to a dispatched role.
- Two runs can drive one project at once.
- A file outside Owned paths is modified.

## Open questions

- None.
