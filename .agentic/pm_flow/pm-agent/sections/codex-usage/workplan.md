# codex-usage workplan

## Design summary

- The engine work is on `main` (event capture, liveness, stderr-only
  classification, attempt lifecycle, real-usage mapping). What remains is to
  make its proof permanent: one tracked test that drives the public driver
  with a stubbed `codex` replaying `tests/fixtures/codex_events_real.jsonl`
  and asserts the stored attempt, liveness, and classification.

## Interfaces and data changes

- None. The test reads `attempts` through the store module and the
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

- Status: done (on `main`; cycles 004–005 NO_GO on harness grounds only: the
  reviewer could not run Codex inside the nested sandbox).
- Outcome: every dispatch creates one `attempts` row; Codex usage from
  `turn.completed` fills its token columns.
- Paths: `driver.zsh`, `telemetry.py` (released since).
- Reuse: `attempts` schema unchanged.
- Acceptance IDs: A1, A3.
- Validation: superseded by T3's tracked test and the reviewer's A1 probe.
- Depends on: T1.

## Task T3 — Track the replay test

- Status: pending.
- Outcome: `tests/codex_usage_test.sh` builds a disposable project, installs a
  stub `codex` on `PATH` that replays the captured stream to its `-o` file and
  events to stdout, drives one `tick` through the public driver, and asserts:
  one completed attempt whose token columns equal the stream's
  `turn.completed.usage` (76195 / 1274 / 62464 / 402 / 77469); no termination
  when only the event file grows past a shortened `heartbeat_stall_seconds`;
  classification unchanged by failure-looking event text; two mutations fail
  (lifecycle call removed; usage read from a field real Codex never emits).
- Paths: `tests/codex_usage_test.sh`, `tests/fixtures/codex_events_real.jsonl`.
- Reuse: `driver_tick` and the disposable-project setup from
  `tests/pm_flow_test.sh`; the probe recorded in `cycles/005/result.md`.
- Acceptance IDs: A1, A3, A4, A5, A6.
- Validation: `zsh tests/codex_usage_test.sh` exits 0 and prints one PASS line
  per assertion above; `zsh tests/pm_flow_test.sh` exits 0. Reviewer probe for
  A1: the attempt row of the developer dispatch that delivered this task
  equals its own `.events.jsonl` `turn.completed` usage.
- Depends on: T2.

## Integration and end-to-end validation

- T3 is the end-to-end task: it drives the real driver, not the parser.

## Risks and rollback

- Codex may change its event schema; the captured fixture pins today's. A
  drift shows as the replay passing while a live dispatch records nothing,
  which the reviewer's A1 probe on a live developer dispatch catches.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T3 | Live developer attempt row equals its `turn.completed` usage |
| A2 | retired | Delivered as store-ledger A2 |
| A3 | T3 | Replay of the captured stream; two mutations fail |
| A4 | T3 | Event-only growth past the stall budget is not killed |
| A5 | T3 | Event text cannot change classification |
| A6 | T3 | Both suites exit 0 |
