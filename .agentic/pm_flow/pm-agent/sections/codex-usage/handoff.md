## Outcome

- A1: live probe `cycles/006/pm_probe_store.zsh` prints `"match": true` for real Codex developer attempts 3, 7, 15, 18; attempt 18 stores 1202445/11665/1142528/5210/1214110, equal to its own `cycles/007/result.response.events.jsonl` `turn.completed` usage. Engine on `main` since `07848d3`.
- A2: retired; store-ledger A2 reads the row this section stores.
- A3: `zsh tests/codex_usage_test.sh` rc=0 on `main` (`8c6a9cb`), replaying `tests/fixtures/codex_events_real.jsonl`; rows 1/3/6 store 13937/5/12032/0/13942; removing `telemetry_end_attempt` leaves `running|None…`, reading only `total_token_usage` leaves `ok|None…`, both asserted. Test at `3660ae7`, merged `09cded8`.
- A4: same run: silent dispatch → `error|stall` at 3s; event-only dispatch runs 6–7s past the budget and completes `ok` with fixture tokens. `3660ae7`.
- A5: same run: `cmp`-identical event streams store `unknown` with empty stderr and `usage_limit` with stderr `rate limit exceeded`. `3660ae7`.
- A6: `zsh tests/pm_flow_test.sh` rc=0, ten `PASS:`; `zsh template/.agentic/pm_flow/tests/run.zsh` rc=0, `pass=73 fail=0`. `09cded8`.

## Decisions

- Codex usage comes from `turn.completed.usage` only; `total_token_usage` is never read.
- The event stream lives in `<response>.events.jsonl` and never enters the attempt log, the response envelope, or `classify_failure`.
- Tests reach the checkout engine via `PM_FLOW_ENGINE_ROOT`/`PM_FLOW_FLOW_DIR`/`PM_FLOW_REPO_ROOT` and `zsh -f pm_flow.sh`, after unsetting every inherited `PM_FLOW_*`.
- A stub's scope answer must satisfy `validate_scoped_assignment`: `## Workplan task` naming one `T<n>`, scaffold marker retired.

## Interfaces

- `attempts` rows with `cli=codex` carry `input_tokens`, `output_tokens`, `cache_read_tokens`, `reasoning_tokens`, `total_tokens` (store-ledger).
- `<response>.events.jsonl` beside every Codex response envelope.
- `tests/fixtures/codex_events_real.jsonl`: pinned real stream, never regenerated.
- `tests/codex_usage_test.sh`: stub-`codex` pattern with modes `replay`/`slow-events`/`silent`/`fail-events`/`fail-stderr`.

## Risks

- Codex event-schema drift: the replay keeps passing while live dispatches store nothing. Revealed by the probe printing `"match": false` or a fresh Codex attempt with `None` tokens.
- The stub's ASSIGN text is copied from `stub_success.zsh`, not shared; a scope-parser change surfaces as `UNPARSED` in tick 1.
- `file_mtime` is 1s-granular: a `heartbeat_stall_seconds` below 3 makes the liveness assertion flaky. The test takes ~60s.

## What is unproven

- A4 and A5 were demonstrated only against the stub `codex`: no real Codex run was observed emitting events past the stall budget or failure strings on stdout. Settled by a live dispatch whose `.events.jsonl` grows past `heartbeat_stall_seconds` with `heartbeat.txt` free of `stalled`.
- Reasoning tokens: the fixture carries `reasoning_output_tokens: 0`, so the test cannot catch a parser dropping that field; the live rows (5210, 8239, 9565, 14032) are the only evidence.
- `pm-flow cost` output for these rows was not exercised here; A1 rests on a direct `attempts` read.
- The `PM_FLOW_*` unset was inferred from the mktemp store path; `printenv` in the reviewer's shell was denied.

## Next action

- Product officer: unblock store-ledger A2 against `attempts` rows 3/7/15/18 in the pm-agent store.
- After any Codex CLI upgrade, run `zsh .agentic/pm_flow/pm-agent/sections/codex-usage/cycles/006/pm_probe_store.zsh`; recapture the fixture only on a mismatch.
