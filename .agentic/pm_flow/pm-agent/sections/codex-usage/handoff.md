# codex-usage handoff

## Outcome

Cycle 002 is technically validated but not accepted. Codex dispatch behavior
meets every assigned criterion, but the manager could not create the mandatory
commit because the managed sandbox denied Git object and ref writes.

## Decisions

- Preserve the current owned-path diff; do not send it through another
  implementation cycle.
- Keep `events_seen` in the function-level local declaration because a repeated
  loop-local declaration prints its value in zsh.
- Keep `unsetopt BG_NICE` at supervisor startup. This prevents zsh's background
  `nice(2)` attempt rather than hiding the resulting warning.
- Retry the review commit only in a context with writable Git metadata.

## Interfaces

- Codex stdout is `<response-without-.json>.events.jsonl`.
- Codex stderr remains the attempt log and the only classifier input.
- The final response is read from the path supplied to Codex with `-o`.
- `TRACEPARENT` reaches the child unchanged.
- `telemetry.py usage_from_codex_events` consumes the retained JSONL and
  recovers input, cached-input, output, reasoning, and total token counts.

## Evidence

- Independent direct probe: exit 0, including exact four-record supervisor
  stdout and empty successful supervisor stderr.
- Independent clean suite: exit 0 with all nine PASS groups.
- Disposable `events_seen` mutation: exit 1 on stdout leakage.
- Disposable `BG_NICE` mutation: exit 1 on the managed-sandbox niceness warning.
- `git merge --ff-only main` failed creating `ORIG_HEAD.lock`; direct Git object
  writes failed with `unable to create temporary file: Operation not permitted`.

## Risks

- The validated source diff is currently staged because `git add` could reuse
  its existing blob, while both attempts to restore the index were denied when
  creating `index.lock`. The file content itself is unchanged.
- The focused acceptance probe is temporary rather than a tracked repository
  test because this section owns only `agent_exec.sh`; the tracked suite passed.

## What is unproven

- No product behavior remains unproven. Only the required durable Git commit is
  missing.

## Next action

- Re-run the manager commit with Git metadata write permission, committing only
  `template/.agentic/pm_flow/agent_exec.sh`, this `state.md`, and this
  `handoff.md`, then integrate the section branch.
