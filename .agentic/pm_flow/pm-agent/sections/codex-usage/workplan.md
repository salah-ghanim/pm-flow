# codex-usage workplan

## Design summary

- The engine work is on `main` (event capture, liveness, stderr-only
  classification, attempt lifecycle, real-usage mapping) and is proven live:
  the pm-agent store holds real Codex developer attempts whose token columns
  equal their own `.events.jsonl` `turn.completed` usage. What remains is to
  make the proof permanent and free: one tracked test that drives the public
  driver against a stub `codex` replaying `tests/fixtures/codex_events_real.jsonl`
  and asserts the stored attempt, liveness, and classification.
- The test drives the checkout engine directly, the way the template dogfoods
  itself: `PM_FLOW_ENGINE_ROOT=<repo>/template/.agentic/pm_flow`,
  `PM_FLOW_FLOW_DIR=<disposable>/.agentic/pm_flow`,
  `PM_FLOW_REPO_ROOT=<disposable>`, then `zsh -f <engine>/pm_flow.sh tick`. No
  wheel build. Mutations run the same ticks against an edited copy of the
  engine directory, selected by `PM_FLOW_ENGINE_ROOT`.

## Interfaces and data changes

- None. The test reads `attempts` through `store.connect()` and the
  `.events.jsonl` file beside the response envelope.

## Task T1 — Capture events without changing failure semantics

- Status: done (cycle 002, `07848d3`).
- Outcome: `codex exec --json` writes adjacent JSONL; event-only activity keeps
  the process alive; stderr alone drives classification.
- Paths: `template/.agentic/pm_flow/agent_exec.sh` (released since).
- Reuse: the supervision loop.
- Acceptance IDs: A4, A5.
- Validation: superseded by T3's tracked test.
- Depends on: green-suite.

## Task T2 — Persist the attempt lifecycle and real tokens

- Status: done (on `main`). Cycles 004–005 were NO_GO on harness grounds only:
  the reviewer could not run Codex inside the nested sandbox.
- Outcome: every dispatch creates one `attempts` row; Codex usage from
  `turn.completed` fills its token columns.
- Paths: `driver.zsh`, `telemetry.py` (released since).
- Reuse: `attempts` schema unchanged; `attempt-start` inserts `persona_id`,
  `binding_id`, `persona_stack`.
- Acceptance IDs: A1, A3.
- Validation (A1, live, 2026-08-23): `.agentic/pm_flow/pm-agent/runs/pm_flow.db`
  attempts 3 and 7 (`develop persona-packs 010` / `011`, cli `codex`, status
  `ok`) store 4945750 / 33155 / 4671744 / 9565 / 4978905 and
  2086060 / 28331 / 1992192 / 8239 / 2114391, each equal to
  `usage_from_codex_events` over its own `result.response.events.jsonl`
  (probe: `cycles/006/pm_probe_store.zsh`).
- Depends on: T1.

## Task T3 — Track the replay test

- Status: done (cycle 007, GO; awaiting the driver's commit). Cycle 006 built
  the test on a worktree 63 commits behind `main`, where the stub's scope
  answer was `UNPARSED`; cycle 007 gave the stub `main`'s scope answer
  (`retire_workplan_scaffold`, `## Workplan task` / `T1`), dropped the
  `engine-baseline` copy, and the test passes on `main`'s engine
  (`ec8130f`) with every row and both mutation PASS lines below.
- Outcome: `tests/codex_usage_test.sh` exits 0 and prints one `PASS` line per
  assertion below, each proven against the public driver:
  1. A scope tick through a stub `codex` that replays the fixture stores one
     `attempts` row with `cli=codex`, `status=ok`, and token columns
     13937 / 5 / 12032 / 0 / 13942 (input / output / cache_read / reasoning /
     total), equal to the fixture's `turn.completed.usage`; the
     `.events.jsonl` beside the response is byte-identical to the fixture.
  2. A developer dispatch that emits only events (no `-o` write, no stderr)
     for longer than `heartbeat_stall_seconds` completes `ok` with the same
     tokens; `heartbeat.txt` carries no `stalled with no progress`.
  3. Control for 2: the same dispatch emitting nothing is terminated
     (`failure_reason=stall`, heartbeat shows `stalled with no progress for
     3s`), so the budget is real.
  4. A failing dispatch whose event stream carries failure-looking values
     (`rate limit`, `429`, `refused`) and empty stderr is classified
     `unknown`; the same events with stderr `rate limit exceeded` are
     classified `usage_limit`. Read from `attempts.failure_reason` and the
     response envelope.
  5. Mutation: an engine copy whose `driver.zsh` lacks the
     `telemetry_end_attempt "$response_json" "$output_md" ok` line leaves the
     row without tokens (assertion 1 fails there).
  6. Mutation: an engine copy whose `telemetry.py` reads only
     `total_token_usage` (drop `"usage"` from the key tuple in
     `usage_from_codex_events`) stores no tokens (assertion 1 fails there).
- Paths: `tests/codex_usage_test.sh`, `tests/fixtures/codex_events_real.jsonl`
  (read only; do not regenerate).
- Reuse: the untracked `tests/codex_usage_test.sh` already in the section
  worktree (cycle 006; passes except for the stub's scope answer); the
  `PM_FLOW_*` unset loop, `assert_*`, `output_value`, the `config.json`
  rewrite block, `init-section` brief, `drain_project_work` and `driver_tick`
  from `tests/pm_flow_test.sh`; the stub shape from
  `tests/fixtures/stub_success.zsh` on `main` (prompt is the last argv; answer
  by `Task:` marker; `retire_workplan_scaffold` before the scope answer, which
  carries `## Workplan task` / `T1`; answer `Task: review the portfolio`).
- Acceptance IDs: A1, A3, A4, A5, A6.
- Validation: `zsh tests/codex_usage_test.sh` exits 0 under the inherited
  pm-flow environment (it must unset `PM_FLOW_*` itself); `zsh
  tests/pm_flow_test.sh` and `zsh template/.agentic/pm_flow/tests/run.zsh`
  exit 0. Reviewer probe for A1: the attempt row of the developer dispatch
  that delivered this task (`sections/codex-usage/cycles/007/result.response.json`
  in the live store) equals its own `result.response.events.jsonl`
  `turn.completed` usage; `cycles/006/pm_probe_store.zsh` prints the
  comparison for every Codex row in the store.
- Depends on: T2.

## Integration and end-to-end validation

- T3 is the end-to-end task: it drives the real driver, not the parser.

## Risks and rollback

- Codex may change its event schema; the captured fixture pins today's. A
  drift shows as the replay passing while a live dispatch records nothing,
  which the reviewer's A1 probe on a live developer dispatch catches.
- A pm-flow run exports seventeen `PM_FLOW_*` selectors into every dispatch.
  A test that does not unset them drives the live pm-agent project instead of
  its disposable one (observed in cycle 006's probe).
- `file_mtime` has one-second granularity, so a liveness stub must write
  events at 1s intervals against a 3s budget, not 1s against 2s.
- The driver's `sync_section_worktree` merges `main` into the section
  worktree before each dispatch, but silently gives up while the worktree has
  uncommitted edits to files `main` also changed (cycles 004-006). A stub or
  test modelled on a stale fixture then passes locally and fails on `main`;
  the reviewer must run the test against `main`, not only the worktree.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T3 | Live developer attempt row equals its `turn.completed` usage |
| A2 | retired | Delivered as store-ledger A2 |
| A3 | T3 | Replay of the captured stream; two mutations fail |
| A4 | T3 | Event-only growth past the stall budget is not killed; silence is |
| A5 | T3 | Event text cannot change classification; stderr can |
| A6 | T3 | Both suites exit 0 |
