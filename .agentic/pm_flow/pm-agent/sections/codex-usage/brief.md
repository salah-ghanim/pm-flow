## Objective

- Every Codex dispatch is recorded as fully as a Claude one: its token counts
  reach the store, and its child process inherits the trace context.

## Current baseline

- `agent_exec.sh` runs `codex exec --json` and writes the event stream to
  `<response>.events.jsonl`; stderr alone feeds `classify_failure`.
- `driver.zsh` brackets every dispatch with `telemetry_begin_attempt` and
  `telemetry_end_attempt`; `telemetry.py usage_from_codex_events` reads the
  `turn.completed` usage event into the `attempts` token columns.
- `tests/fixtures/codex_events_real.jsonl` is a stream captured from a real
  Codex run. No tracked test exercises the path above; the proof so far is an
  untracked probe script.

## Deliverables

- `tests/codex_usage_test.sh`: a tracked, deterministic replay of one dispatch
  through the public driver against the captured stream, asserting the stored
  attempt row, event-only liveness, and stderr-only classification.

## User-visible scenarios

1. A Codex-bound role is dispatched; `pm-flow cost` afterwards shows that
   attempt with non-zero input, output, cached and reasoning tokens equal to
   the `turn.completed` event in its `.events.jsonl`.
2. A Codex dispatch that emits only events for longer than the heartbeat stall
   budget is not killed as stalled.

## Interfaces produced

- `attempts` rows for Codex dispatches carry `input_tokens`, `output_tokens`,
  `cache_read_tokens`, `reasoning_tokens`, `total_tokens`.
- `<response>.events.jsonl` beside every Codex response envelope.

## Interfaces consumed

- `tests/fixtures/codex_events_real.jsonl`.
- The stub harness conventions from `green-suite` (`driver_tick`).

## Scope

- In: the tracked replay test and any fixture it needs.
- Out: cost presentation (`store-ledger`), attribute naming (`otel-semconv`),
  any engine change. An engine defect the test exposes is reported as a
  boundary conflict, not fixed from here.

## Non-goals

- A second event parser, a token ledger, or direct shell-side SQLite access.
- Exercising Codex over HTTPS or with alternative sandboxes.

## Priority

- must-have: without recorded Codex tokens, half the seats in a default install
  cost nothing on paper and no cross-model comparison is possible.

## Owned paths

- `tests/codex_usage_test.sh`
- `tests/fixtures/codex_events_real.jsonl`

## Dependencies

- green-suite

## Constraints and fixed decisions

- Real Codex reports usage on `turn.completed`; nothing reads
  `total_token_usage`.
- The event stream never enters the attempt log or the response envelope.
- The reviewer's own evidence for A1 is the developer dispatch that delivered
  the test: a Codex-bound developer run whose attempt row matches its own
  `.events.jsonl`.

## Acceptance

- A1: After a real Codex dispatch, `pm-flow cost` (or a direct read of
  `attempts`) shows input, output, cached-input and reasoning tokens equal to
  that dispatch's `turn.completed` usage.
- A2: Retired. Cost presentation is `store-ledger` A2; this section supplies
  the stored row it reads.
- A3: `zsh tests/codex_usage_test.sh` exits 0 and replays the captured real
  stream, not a synthetic one; removing the `telemetry_end_attempt` call or
  reading a usage field real Codex does not emit makes it fail.
- A4: In that test, a dispatch whose only output is event-stream growth past
  `heartbeat_stall_seconds` is not terminated as stalled.
- A5: In that test, an event stream containing failure-looking strings does not
  change `classify_failure`'s verdict; only stderr does.
- A6: `zsh tests/pm_flow_test.sh` and `zsh template/.agentic/pm_flow/tests/run.zsh`
  exit 0 with the new test in the tree.

## Rejection conditions

- The replay proves the parser against a stream the test itself generated.
- A file outside Owned paths is modified.
- A6 is met by skipping or weakening a suite.

## Open questions

- None.
