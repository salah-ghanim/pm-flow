# codex-usage workplan

## Design summary

- Capture Codex JSONL separately from diagnostics, treat event-file growth as
  liveness, parse real `turn.completed.usage`, and bracket every dispatch with
  the existing telemetry attempt lifecycle. Keep replay deterministic and use
  a host canary only for the authenticated external contract.

## Interfaces and data changes

- `<response>.events.jsonl` is the Codex event stream; stderr remains the
  attempt log and sole failure-classification input.
- `TRACEPARENT` is inherited by the child.
- `attempts` stores Codex identity and token columns; cost presentation remains
  owned by `store-ledger`.

## Task T1 — Capture events without changing failure semantics

- Status: completed (cycles 001–002; `07848d3`).
- Outcome: `codex exec --json` writes adjacent JSONL, event-only activity keeps
  the process alive, stderr alone drives classification, and supervisor output
  stays parseable.
- Paths: `template/.agentic/pm_flow/agent_exec.sh`.
- Reuse: `usage_from_codex_events` and existing supervision loop.
- Acceptance IDs: A3, A4, A5.
- Validation: fixture dispatch, event-only liveness past the stall threshold,
  stderr classification probe, exact four-record supervisor output.
- Depends on: green-suite.

## Task T2 — Persist the real attempt lifecycle and tokens

- Status: completed technically (cycles 004–005; present on `main`).
- Outcome: begin/end lifecycle calls create one attempt and map real Codex usage
  into the schema's existing token columns.
- Paths: `driver.zsh`, `telemetry.py`, real event fixture.
- Reuse: `runs`, `attempts`, topology/persona/binding tables.
- Acceptance IDs: A1, A3, A6.
- Validation: the developer host canary stored input 76195, output 1274,
  cached input 62464, reasoning 402, total 77469 matching one real event; schema
  and lifecycle-removal mutations produced no completed attempt.
- Depends on: T1.

## Task T3 — Make deterministic replay permanent

- Status: pending.
- Outcome: a tracked public-`tick` test proves dispatch, lifecycle, exact token
  mapping, event liveness, stderr isolation, and telemetry non-fatality using
  the captured real-Codex stream.
- Paths: `tests/codex_usage_test.sh`,
  `tests/fixtures/codex_events_real.jsonl`, and only the owned engine files if a
  defect is exposed.
- Reuse: the cycle-005 probe logic and real captured fixture; do not synthesize
  a private event schema.
- Acceptance IDs: A1, A3, A4, A5, A6.
- Validation: `zsh tests/codex_usage_test.sh` passes; mutations removing
  lifecycle wiring and reading the wrong usage fields fail.
- Depends on: T2.

## Task T4 — Run an authenticated host canary

- Status: pending; reviewer sandbox cannot nest the authenticated Codex client.
- Outcome: one host-level dispatch produces usable role output, a non-empty
  event stream, a closed run, and one completed attempt whose token columns
  exactly equal `turn.completed.usage`.
- Paths: no product write unless T3 exposes a defect; evidence belongs in the
  cycle record.
- Reuse: the same assertions as T3 against a real `codex` executable.
- Acceptance IDs: A1, A4, A6.
- Validation: run outside the nested reviewer sandbox and record versions,
  command, event values, store values, and exit status.
- Depends on: T3 and credentials.

## Task T5 — Verify user-visible cost through store-ledger

- Status: waiting on `store-ledger`; no codex-owned implementation is allowed.
- Outcome: `pm_flow.sh cost` reports the stored Codex tokens/spend without
  parsing JSONL.
- Paths: none in this section; evidence-only verification.
- Reuse: the completed attempt from T4 and store-ledger's reader.
- Acceptance IDs: A2.
- Validation: run `pm_flow.sh cost` for the canary run and match its Codex row
  to the store.
- Depends on: T4, store-ledger.

## Integration and end-to-end validation

- T3 is the next assignable task. T4 is a live canary, not a substitute for
  replay. T5 verifies the downstream presentation contract without crossing
  section ownership.

## Risks and rollback

- Codex event schemas may change. Replay detects known-schema drift; the host
  canary detects CLI/service drift. Roll back lifecycle integration without
  deleting captured events or stored attempts.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T3, T4 | Stored tokens exactly match real event usage |
| A2 | T5 | Cost output reads the stored Codex attempt |
| A3 | T1, T3 | Real captured fixture drives parser and lifecycle |
| A4 | T1, T3, T4 | Event-only dispatch is not killed as stalled |
| A5 | T1, T3 | Only stderr affects classification |
| A6 | T2, T3, T4 | Deterministic suite and authenticated canary pass |
