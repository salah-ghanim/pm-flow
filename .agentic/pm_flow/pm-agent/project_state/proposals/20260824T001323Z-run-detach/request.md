A run should survive the process that started it. Today `pm-flow run` is a
foreground child of the shell or tool that launched it; when that launcher
went away on 2026-08-23, the Codex developer it had dispatched was killed
four minutes in, the attempt was recorded as `failed (unknown)`, and the
driver died before retrying, so a second run had to be started by hand with
`nohup … &!`. A person should be able to start a run, close the terminal,
find the run's log, and stop the run deliberately after its current dispatch
finishes. The driver is already level-triggered, so resuming is the same
command; what is lost today is one dispatch's spend and the operator's
attention.
