# Run pm-flow in the background

Use `run-detach` when a run should continue after you close its launching
terminal:

```sh
pm-flow run-detach start
```

The command returns after printing the supervisor PID and log path:

```text
pid=12345
log=<project>/runs/run-detach-<UTC>.log
```

Use `--section` to limit the run to one section, and `--max-ticks` to limit
the number of ticks:

```sh
pm-flow --section <section> run-detach start --max-ticks 10
```

Follow the `log=` path printed by `start` to watch the run, for example with
`tail -f <project>/runs/run-detach-<UTC>.log`. From another terminal, inspect
the supervisor with:

```sh
pm-flow run-detach status
```

Status is `running`, `stopping`, or `idle`, followed by the PID, start time,
completed tick count, and log path.

## Stop and resume

Request a stop with:

```sh
pm-flow run-detach stop
```

Stopping is graceful only. The dispatch already in flight always finishes and
is recorded; the supervisor then starts no further tick and exits. To stop
immediately instead, use `kill <pid>` with the PID printed by `start` or
`status`.

After a graceful stop or a completed run, resume with the same start command:

```sh
pm-flow run-detach start
```

pm-flow reads the section state on disk, so the resumed run continues with the
next action rather than repeating the completed dispatch.

## Runtime files

All detached-run files live under `<project>/runs/` and are gitignored:

- `run-detach.pid` — the live supervisor PID.
- `run-detach.state` — start time, tick count, section, log, and engine state.
- `run-detach.stop` — the graceful-stop request while one is pending.
- `run-detach-<UTC>.log` — supervisor and dispatch output for one run.

The routed `pm-flow run-detach ...` command is the normal entry point. If that
route is unavailable, the engine script is a fallback:

```sh
zsh <engine>/run_detach.zsh --project <project> start
zsh <engine>/run_detach.zsh --project <project> status
zsh <engine>/run_detach.zsh --project <project> stop
```

For the direct form, the resolved pm-flow layout must already be present in
the environment so the script can find the project workspace and tick engine.
