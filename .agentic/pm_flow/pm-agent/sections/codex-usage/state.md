# codex-usage section PM state

## Objective

- Make Codex dispatches retain their JSONL event stream for token accounting,
  treat that stream as liveness without exposing it to failure classification,
  and pass the dispatch trace context to the child process.

## Owned paths

- `template/.agentic/pm_flow/agent_exec.sh`

## Plan

- Cycle 001 validated the existing Codex JSONL, trace, liveness, token parsing,
  and stderr-isolation behavior, then exposed supervisor stream pollution.
- Cycle 002 preserved the declaration fix and disabled zsh background-job
  niceness so supervisor stdout and stderr satisfy their contracts.

## Decisions and evidence

- Cycle 001 was `NO_GO`: the direct probe exited 1 because sandbox-denied
  `nice(5)` polluted supervisor stderr, although the suite passed and the
  `events_seen` mutation proved the stdout declaration fix.
- Cycle 002 technically satisfies every assigned acceptance criterion.
  `unsetopt BG_NICE` prevents zsh from attempting the background `nice(2)` call;
  it does not filter or redirect the warning.
- The independent Cycle 002 fake-Codex probe exited 0. It proved `exec --json`,
  exact `TRACEPARENT` propagation, event-only liveness beyond the two-second
  stall limit, a non-empty response-adjacent events file, token-total recovery,
  final response delivery through `-o`, exact four-line supervisor stdout,
  empty successful supervisor stderr, and stderr-only network classification.
- The clean-environment full suite exited 0 with all nine PASS groups.
- Restoring loop-local `events_seen` made the probe exit 1 after leaking
  `events_seen=<mtime>` records. Removing `unsetopt BG_NICE` made it exit 1
  after reproducing `nice(5) failed: operation not permitted` on supervisor
  stderr. Both mutations were applied only to disposable installed copies.
- Only `template/.agentic/pm_flow/agent_exec.sh` changed; `git diff --check`
  passed. No parser, driver, test, or sandbox-permission change was accepted.
- Cycle 002 cannot be accepted in this review context because the mandatory
  one-commit handoff cannot be created: Git ref creation and new object writes
  under `.git` are denied by the managed filesystem. The implementation must
  not be reissued; the review/commit step must be retried with writable Git
  metadata.

## Current assignment

- Do not issue another implementation assignment. Re-run the acceptance commit
  in a context that can write Git objects and refs, then integrate the already
  validated owned-path diff with this state and handoff.

## Dependencies

- `green-suite`: satisfied; its suite remains green under the validated change.
- External review environment: blocked on permission to create `.git` object,
  index-lock, and ref-lock files required by the mandated scoped commit.

## Review history

- Cycle 001: `NO_GO`; direct probe failed the quiet-stderr contract.
- Cycle 002: `NO_GO`; all technical checks and mutations passed, but the
  required accepted-cycle commit was impossible under the review sandbox.
