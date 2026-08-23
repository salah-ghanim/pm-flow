# codex-usage section PM state

## Current task

- None. Section complete (cycle 008 scope, 2026-08-23). T3 is committed:
  `tests/codex_usage_test.sh` landed at `3660ae7` and was merged to `main` at
  `09cded8`; `git ls-files` tracks both the test and the fixture and
  `git status --short tests template` is empty.

## Completed tasks and evidence

- T1 / A4, A5: cycle 002 GO; `07848d3`.
- T2 / A1: on `main`. Live evidence, 2026-08-23, from the pm-agent store
  (`cycles/006/pm_probe_store.zsh`): attempts 3, 7 and 15 are real Codex
  developer dispatches (`develop persona-packs 010` / `011`, `develop
  codex-usage 006`, status `ok`) whose stored input / output / cache_read /
  reasoning / total equal `usage_from_codex_events` over their own
  `result.response.events.jsonl`: 4945750 / 33155 / 4671744 / 9565 / 4978905,
  2086060 / 28331 / 1992192 / 8239 / 2114391 and
  5503419 / 29397 / 5174016 / 14032 / 5532816 (`"match": true` for all
  three; `codex rows total: 3`, cycle-006 review). codex-usage's own
  cycle-005 dispatches predate the fix and have no row, which is expected.
- T2 / A3 (lifecycle wiring and real-usage parser): cycle 005 developer run
  showed one completed attempt equal to its `turn.completed` event, and two
  mutations failing (`cycles/005/result.md`); the reviewer reproduced the
  mutations and the full suite but not the live dispatch (nested sandbox
  denied Codex). Tracked proof is T3.
- T3 / A1, A3, A4, A5, A6: cycle 007 GO, 2026-08-23, reviewed in the section
  worktree at `ec8130f` = `main` (`cycles/007/pm_review_checks.zsh`).
  - A3: `zsh tests/codex_usage_test.sh` rc=0, store path under
    `$TMPDIR/codex-usage-test.*`, first tick `result=scope 001 -> ASSIGN`;
    rows `1|pm|codex|ok|None|13937|5|12032|0|13942`,
    `3|developer|codex|ok|None|13937|5|12032|0|13942`,
    `6|pm|codex|ok|None|13937|5|12032|0|13942`; `result.response.events.jsonl`
    byte-identical to the fixture; mutation rows
    `1|pm|None|running|None|...` (no `telemetry_end_attempt`) and
    `1|pm|codex|ok|None|None|None|None|None|None` (only `total_token_usage`).
    Negative checks on scratch copies: dropping `retire_workplan_scaffold`
    fails tick 1; an empty replay stream leaves rows 1 and 6 without tokens
    and fails; a no-op mutation `sed` trips the `cmp` guard.
  - A4: row `2|developer|codex|error|stall`, heartbeat `stalled with no
    progress for 3s`; event-only dispatch ran 7s with no new stalled line.
  - A5: rows `4|pm|codex|error|unknown` and `5|pm|codex|error|usage_limit`
    from `cmp`-identical event streams; tick-4 `review.response.json`
    `failure_reason` = `unknown`.
  - A1: `cycles/006/pm_probe_store.zsh` prints `"match": true` for attempt
    18 (`develop codex-usage 007`, 1202445 / 11665 / 1142528 / 5210 /
    1214110 against `cycles/007/result.response.events.jsonl`) alongside 3,
    7 and 15; `codex rows total: 4`.
  - A6: `zsh tests/pm_flow_test.sh` rc=0 with ten `PASS:` lines;
    `zsh template/.agentic/pm_flow/tests/run.zsh` rc=0, `pass=73 fail=0`,
    `all suites passed`.
  - Drift: `git status --short` shows only `?? tests/codex_usage_test.sh`;
    fixture and engine unchanged. The stub's ASSIGN text equals
    `stub_success.zsh:74-90` except the emitter (`print -r --` vs `emit`).
  - Post-commit re-run (cycle 008 scope, `main` at `8c6a9cb`): `zsh
    tests/codex_usage_test.sh` rc=0, store under
    `$TMPDIR/codex-usage-test.yXKzRw`, `result=scope 001 -> ASSIGN`, the same
    six rows, `event-only dispatch ran 6s past the 3s budget`, both mutation
    PASS lines.

## Active decisions

- Engine paths are released; this section owns only the test and fixture.
- A2 is retired to store-ledger.
- The tracked test drives the checkout engine via `PM_FLOW_ENGINE_ROOT`,
  `PM_FLOW_FLOW_DIR`, `PM_FLOW_REPO_ROOT` and `zsh -f pm_flow.sh`, not a
  wheel build; mutations are engine-directory copies selected the same way.
- The test asserts the fixture's numbers (13937 / 5 / 12032 / 0 / 13942),
  not the cycle-005 live numbers the workplan previously carried.
- The test must unset every inherited `PM_FLOW_*` first: a dispatched test
  otherwise drives the live pm-agent project (observed in cycle 006's probe).
- The stub's scope answer must satisfy `main`'s `validate_scoped_assignment`
  (`pm_flow.sh:1080`): a `## Workplan task` heading whose first line names
  exactly one `T<n>` that is a task heading in the section's `workplan.md`,
  and no `pm-flow-workplan-template` marker left in that file. The
  `init-section` scaffold defines `## Task T1 — …`, so `retire_workplan_scaffold`
  (copied from `tests/fixtures/stub_success.zsh:10-17`) plus `T1` is enough.
- Review runs the test against `main` (or an export of it), not only in the
  worktree; the worktree is where it was built, `main` is where it lands.

## Blockers

- None.

## Next eligible task

- None. T1–T3 are done and committed; A1, A3–A6 are evidenced (A2 retired).
  The tracked test is the permanent proof; `cycles/006/pm_probe_store.zsh`
  against a live Codex dispatch is the schema-drift check.
