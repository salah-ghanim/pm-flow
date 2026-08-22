# codex-usage handoff

## Outcome

Cycle 001 is rejected and uncommitted. The Codex event-stream behavior works,
and moving `events_seen` out of the polling loop prevents zsh from printing its
value into the driver's stdout metadata. The exact direct probe nevertheless
exited 1 because the managed sandbox denied zsh's background niceness adjustment
and the harness required supervisor stderr to be completely empty.

## Decisions

- Do not accept Cycle 001: its required direct command returned 13 passed and 1
  failed. A passing full suite does not override that rejection condition.
- Preserve the returned declaration move in the developer worktree for the next
  attempt; the mutation check showed that reverting it leaks four
  `events_seen=<mtime>` lines during a five-second dispatch.
- The warning mechanism is established: zsh's default background-job niceness
  adjustment attempted `nice(5)`, and the managed sandbox denied it.

## Interfaces

- Codex is invoked as `codex exec --json`; its stdout goes to
  `<response-without-.json>.events.jsonl`, while its stderr remains the failure
  classifier input.
- `TRACEPARENT` reaches the fake child unchanged.
- `telemetry.py usage_from_codex_events` parsed the emitted totals without
  modification.

## Risks

The current probe calls its capture “child stderr” but actually captures the
supervisor process's stderr. That masks whether a line came from the redirected
attempt log or from zsh itself. Cycle 002 needs to make this boundary observable
without weakening the rejection of JSONL leakage.

## What is unproven

No acceptance run has completed with all direct-probe assertions passing in the
review environment. The implementation therefore remains unaccepted despite
the core behavior evidence and the full-suite pass.

## Next action

Scope Cycle 002 to preserve the declaration fix and remove the observed
quiet-stderr failure through the smallest owned-path correction or a direct
attempt-log observation. Re-run both probes, the stdout mutation, and the full
suite before acceptance.
