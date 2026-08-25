## Outcome
- A1 — launcher's process group is SIGHUPed; supervisor and in-flight dispatch survive and the cycle records the stub's normal status. `PASS: launcher process-group SIGHUP leaves supervisor and dispatch alive`; deleting `os.setsid()` turns it red. `9a2a1e7`.
- A2 — `PASS: live, idle, and stale-pid status reporting`; a pid file whose process is gone reads `idle`, exit 0. `9a2a1e7`.
- A3 — stop mid-dispatch records the result, starts no tick, last log line `run-detach stopped by request after tick 1`, `status` idle — at `--max-ticks 4`, so the budget is not doing the work. `605e2f8`.
- A4 — `PASS: duplicate start refusal preserves tick state`: non-zero exit, live pid and log printed. `9a2a1e7`.
- A5 — `next` named `develop` pre-stop, `review` post-stop; the restart's log runs `review` and the pre-stop `result.md` mtime is unchanged. `605e2f8`.
- A6 — fixture porcelain empty after start, stop and restart; no `run-detach*` outside `<project>/runs/`. `605e2f8`, `3c5ae8f`.
- A7 — `pm-flow run-detach` routes and appears in `help` (`pm_flow.sh:1932`, `:50`); `packaged_layout_test.sh` exits 0, 13/13. `3c5ae8f`, `99fe986`.
- A8 — all three suites exit 0 (9/9, 10/10, 13/13), re-measured on merged `main` at `9afcf0f`; the new suite opens with the `PM_FLOW_*` guard.

## Decisions
- One tick = `run --max-ticks 1`; the between-tick gap is the only stop point. The driver's loop, locks and attempt classification are untouched.
- Detachment is `python3 -c 'os.setsid(); os.execvp(…)'` — no nohup, setsid binary, tmux or launchd. Signal disposition cannot be inherited across `agent_exec.sh`'s vendor CLI.
- Stop is graceful only: the sole `kill` is a `kill -0` liveness probe; no trap.
- Any new file under `template/.agentic/pm_flow/` must be registered in `install.sh`'s `COPIED_ENGINE_FILES`/`_DIRS` or migration strands it. Standing cost, not a one-off.

## Interfaces
- `pm-flow run-detach start [--max-ticks N] [--section KEY] | stop | status`; `start` prints `pid=` and `log=`. `--section` is accepted on `start` only.
- Runtime under `$RUNS_DIR`: `run-detach.pid`, `.state`, `.stop`, `run-detach-<UTC>.log`; already gitignored by `*/runs/*`.
- `template/.agentic/pm_flow/run_detach.zsh`, `docs/run-detach.md`, `tests/run_detach_test.sh`, `tests/fixtures/stub_detach{,_stop}.zsh`.
- `install.sh:67,68,83` now registers `run_detach.zsh`, `artifact_quality.md`, `cards`.

## Risks
- `tests/packaged_layout_test.sh:670-675` keeps a shorter private copy of both registry arrays, now further out of step with `install.sh`; `assert_data_only` therefore checks fewer names than it could. The strict `ls -A` at `:1018-1020` covers the gap. Bringing the copy to parity would reveal any divergence.
- A hard-killed supervisor leaves `run-detach.stop` behind; `start` clears it. A regression shows as a run stopping after one tick.

## What is unproven
- `resolve_project`'s no-`--project` fallthrough to `$PM_FLOW_FLOW_DIR/$PROJECT_KEY/runs` is unexercised — the test's `engine_command` always passes `--project`. Settled by one routed `start` with it omitted.
- Only stub agents were dispatched; no real vendor CLI has been hung up mid-dispatch. Settled by a real detached run whose terminal is closed.
- Linux is claimed in the brief but every run was macOS. Settled by the suite on Linux.

## Next action
- None here. Portfolio: the `packaged_layout_test.sh:670-675` array copy needs an owner.
