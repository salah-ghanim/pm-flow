# otel-semconv workplan

## Design summary

- One module pins the revision and owns every standard name; `telemetry.py`
  calls it. The proof is an independent OTLP/HTTP receiver in the test fed by
  the real record-then-export path, with a Jaeger query as the viewer check
  when Docker is present.
- `semconv.py` lives in the package (`src/pm_flow/semconv.py`) but is consumed
  by an engine script that runs under plain `python3` and is standard-library
  only. It is therefore loaded **by path**, resolved from `telemetry.py`'s own
  `__file__`, not by `import pm_flow.semconv`: an installed-package import would
  read the installed copy and make A5's "edit the revision in a copy" prove
  nothing.
- Today the driver records one span per dispatch (`attempt-start` with the
  default `AGENT` kind, no `--span-kind`), so no `chat` child exists anywhere.
  `driver.zsh` is not an owned path, so `telemetry.py` creates the pair itself:
  one `invoke_agent` span (the row the `attempts` table already points at) and
  one `chat` child carrying the model call. The driver's contract - the printed
  `span_id`, the traceparent handed to the child CLI, the `attempt-end`
  lookup - is unchanged.

## Interfaces and data changes

- `semconv.REVISION`, `semconv.SPAN_OPERATIONS`, `semconv.attributes_for`.
- New span attribute `pm_flow.semconv.revision`; no schema change. The `chat`
  child uses the existing `spans.parent_span_id` and `spans.attempt_id`
  columns, so the `attempts` row is reached by
  `spans.parent_span_id = attempts.span_id` (equivalently `spans.attempt_id`).
- `attributes_for` gates the usage names on the operation: `gen_ai.usage.*` is
  emitted only when the operation resolves to `chat`. Today it emits them for
  whatever kind it is handed (`semconv.py:55-56`), which is `AGENT` at
  `attempt-end`, so the usage currently lands on the parent. The OpenInference
  `llm.token_count.*` names stay exactly where they are - out of scope.

## Task T1 — Pin the revision and centralise the names

- Status: done — accepted cycle 002 (GO_WITH_CHANGES). A3, A4, A5 met and
  mutation-proven. Carried into T2: `tests/otel_semconv_test.sh` currently ends
  with a `git status --porcelain` ownership assertion that fails on any
  unrelated working-tree change, so A7 cannot hold in a dirty checkout; T2
  deletes it (it is a review-time check, not a regression test).
- Outcome: `src/pm_flow/semconv.py` declares the pinned GenAI conventions
  revision, the span operation names, and `attributes_for(attempt)`;
  `telemetry.py` builds its GenAI attributes only through it and stamps
  `pm_flow.semconv.revision` on every span it writes; no other file in
  `template/` or `src/` contains a `gen_ai.` literal, prose included.
- Paths: `src/pm_flow/semconv.py`, `template/.agentic/pm_flow/telemetry.py`,
  `tests/otel_semconv_test.sh`.
- Reuse: the GenAI block of `semconv_attributes` in `telemetry.py` lines
  245-260 (move, do not duplicate; the OpenInference, `llm.*` and `pm_flow.*`
  blocks stay where they are); `insert_span` (telemetry.py:352) as the one
  choke point where the revision is stamped, since `cmd_span_start` builds its
  attributes from `parse_attrs` and never reaches `semconv_attributes`;
  `store.py`'s span writer; the copy-the-engine-into-a-temp-repo setup at the
  head of `tests/store_ledger_test.sh`.
- Acceptance IDs: A3, A4, A5.
- Validation: `zsh tests/otel_semconv_test.sh` - records one attempt through
  `telemetry.py` and asserts the revision attribute on every written span and
  the names the pinned revision defines; the A4 grep matches only
  `src/pm_flow/semconv.py`; a copy of the tree with `REVISION` switched to the
  second pin emits the alternate names.
- Depends on: None.

## Task T2 — Emit the invoke_agent → chat pair and prove it through a receiver

- Status: done — accepted cycle 003 (GO_WITH_CHANGES). A1, A2, A6, A7 met; A3
  and A5 re-asserted on the receiver. Three negatives proven by review-side
  mutation. Carried into T3: the child is built by the same
  `semconv_attributes` call as the parent, so `llm.token_count.*`,
  `pm_flow.cost_usd`, `pm_flow.cache_*`, `pm_flow.reasoning_tokens` and the
  `input.value` / `output.value` bodies are now written twice per dispatch.
- Outcome: `telemetry.py` records a `chat` child under each dispatch's
  `invoke_agent` span and puts the usage attributes on the child; the test
  starts a standard-library OTLP/HTTP receiver, drives one stub dispatch
  through the public driver, and asserts on what the receiver decoded - the
  tree, the usage equal to the `attempts` row, and the revision on every
  span. A5's revision switch is re-asserted on what the receiver sees rather
  than on the stored attributes. The cycle-scoped `git status --porcelain`
  ownership assertion T1 left at the tail of the test is deleted. With Docker
  present the A6 Jaeger command is run and its response recorded; absent, the
  result says so.
- Paths: `template/.agentic/pm_flow/telemetry.py`, `tests/otel_semconv_test.sh`.
- Reuse: T1's mapping; `driver.zsh`'s own export path - `telemetry_autoexport`
  (driver.zsh:728-735) posts to `config_setting telemetry otlp_endpoint` at run
  end, so setting `{"telemetry":{"otlp_endpoint":…}}` in the disposable
  project's `config.json` feeds the receiver with no test-side transport and no
  edit outside owned paths; `install.sh` + `init-section` + a stub `claude` on
  `PATH`, as `tests/pm_flow_test.sh:937-1010` sets up; `trace_export.py`
  unchanged and called by path, since no `pm-flow trace` subcommand exists yet
  (it belongs to `trace-commands`).
- Acceptance IDs: A1, A2, A6, A7.
- Validation: `zsh tests/otel_semconv_test.sh` exits 0 in a dirty checkout; a
  mutation that drops the `chat` child's usage attributes fails it;
  `zsh tests/pm_flow_test.sh` and `zsh tests/store_ledger_test.sh` exit 0;
  `curl -s 'http://localhost:16686/api/traces?service=pm-flow'` shows
  `invoke_agent` and `chat` for the exported trace, or Docker is recorded
  absent.
- Depends on: T1.

### Export route — T2's premise was wrong, corrected by the cycle 006 probe

T2 decided the route on the premise that `trace_export.py --otlp` imports the
OpenTelemetry SDK. That is false of the file as it stands: the SDK is imported
only by the `grpc` branch (trace_export.py:259-274), `--protocol` defaults to
`http` (trace_export.py:475), and the `http` branch posts OTLP/JSON with stdlib
`urllib` alone (trace_export.py:218-256). The module says so itself at
trace_export.py:24 - "Only `--protocol grpc` imports the SDK".
`git log -S'args.protocol == "http"'` attributes the stdlib route to
`54da8ab chore(trace-commands): accepted cycle 002`, a section that owns the
file.

What is still true: the SDK is not installed on this host
(`import opentelemetry` → `ModuleNotFoundError` under
`/Users/salah/code/personal/pm-flow/.venv/bin/python3`), and a network install
must not be added to a deliberately offline suite. What changes is the
conclusion - the wire route works without the SDK, so the driver's own
`telemetry_autoexport` (driver.zsh:775-781) already delivers a complete payload
by itself.

Two routes into one receiver, the assertions identical:

- The driver's `telemetry_autoexport` POSTs OTLP/JSON at run end to the endpoint
  the disposable project's `config.json` names. No test-side transport;
  preferred whenever it arrives.
- The receiver could not bind TCP, so nothing reached it: after the same driver
  run, `trace_export.py --file … --replay` writes OTLP/JSON from the real
  serialiser and the test POSTs those lines to the same receiver at
  `/v1/traces`.

The test prints which route delivered. The fallback is a stated limit - the HTTP
hop is the test's, the payload is pm-flow's - and it is not to be preferred when
the driver's own export lands. Running both unconditionally, which is what the
suite does today, is exactly the defect T4 fixes.

## Task T3 — Stop the non-convention attributes being written twice per dispatch

- Status: done — accepted cycle 004 (GO). A1, A2, A3, A7 met on the receiver,
  both negatives reproduced review-side, and the parent's attribute set proven
  byte-identical to HEAD by a differential probe of `semconv_attributes`.
- Outcome: only the attributes the pair genuinely needs on both spans are on
  both. The `chat` child keeps `gen_ai.*`, `openinference.span.kind=LLM`,
  `llm.model_name` / `llm.provider` / `llm.system` and its own identity; the
  aggregatable and bulky ones stay on exactly one span —
  `llm.token_count.prompt|completion|total`, `pm_flow.cost_usd`,
  `pm_flow.cache_read_tokens`, `pm_flow.cache_write_tokens`,
  `pm_flow.reasoning_tokens`, `input.value` / `input.mime_type` and
  `output.value` / `output.mime_type`. All eight stay on the `invoke_agent`
  parent and are dropped from the child, so the parent's attribute set is
  byte-identical to today; `llm.token_count.*` staying on the parent is T2's
  contract, and the same side is chosen for the rest so no key moves.
- Why: T2 builds the child from the same `semconv_attributes(...)` call as the
  parent (telemetry.py:624-630, 733-738), so every one of those is emitted on
  both rows. A stock backend that sums `llm.token_count.*` or
  `pm_flow.cost_usd` over a trace now reports double, which is the opposite of
  the brief's objective, and the prompt and result bodies are stored and
  exported twice per dispatch.
- Paths: `template/.agentic/pm_flow/telemetry.py`, `tests/otel_semconv_test.sh`.
- Reuse: `semconv_attributes`' existing keyword surface. Dropping `usage` from
  the child call is not enough on its own — the child's `gen_ai.usage.*` is
  derived from that same `usage` (telemetry.py:272-283), so A2 would break.
  The function takes one new keyword-only flag that suppresses the
  OpenInference token counts, the `pm_flow.` cost/cache/reasoning block and the
  body attributes while still handing the real `usage` to `attributes_for`; the
  two child calls (telemetry.py:624-630, 733-738) pass it and nothing else
  changes, so the parent's attributes stay byte-identical.
- Acceptance IDs: A1, A2, A3, A7 (regression — the pair, the usage split and
  the revision must all still hold).
- Validation: `zsh tests/otel_semconv_test.sh` asserts on the receiver that
  each of the named keys appears on exactly one span of the pair, that the
  parent still carries `llm.token_count.prompt|completion` equal to the
  `attempts` row, and that the child still carries `gen_ai.usage.*`;
  reverting either child call to the shared attribute set fails it;
  `zsh tests/pm_flow_test.sh` and `zsh tests/store_ledger_test.sh` exit 0.
- Depends on: T2.

## Task T4 — Select the receiver's payloads by trace, not by arrival ordinal

- Status: done — accepted cycle 006 (GO_WITH_CHANGES). A1, A2, A3, A5, A7 met
  on this host, twice in a row. Both routes observed on one host: the driver's
  `telemetry_autoexport` delivered on the review seat, the test's replay POST on
  the developer's (bind prohibited) and in the missing-child negative.
- Outcome: `zsh tests/otel_semconv_test.sh` exits 0 on this host, and stays
  correct however many payloads a tree delivers. The test stops indexing
  `received.jsonl` by ordinal and instead selects, for each tree, the spans
  whose `traceId` is the one that tree's own store recorded, deduplicated by
  `spanId`; a tree whose trace never arrives fails with that trace id named.
  The stale SDK-based route probe is replaced by what actually happened: the
  driver's own `telemetry_autoexport` is the primary route and the test's
  `--file --replay` POST is the fallback for a receiver that could not bind
  TCP. The printed `ROUTE` line names which route delivered.
- Why: probed this cycle, see `cycles/006/probe_findings.md`. The receiver
  gets **four** payloads, two per tree, byte-identical within a tree.
  `assert_received_tree 2` therefore reads the primary's second payload and
  reports `secondary: span … revision is 'v1.37.0', expected 'v1.36.0'`. The
  section's code is correct: the secondary store holds `v1.36.0` on all three
  rows and its `trace.otlp.jsonl` carries `v1.36.0`. The duplicate exists
  because `trace_export.py --otlp` needs the SDK only for `--protocol grpc`
  (trace_export.py:24, 218-256, 475), so `telemetry_autoexport`
  (driver.zsh:775-781) already ships a full payload over stdlib `urllib`, and
  `export_tree` ships the same spans again.
- Paths: `tests/otel_semconv_test.sh`. `telemetry.py` and `semconv.py` are not
  expected to change; if they do, the change needs its own justification
  because no evidence so far points at them.
- Reuse: `assert_received_tree` (otel_semconv_test.sh:412-533) keeps every
  assertion it makes today — only how it picks `spans` changes. The tree's
  trace id comes from the store the function is already handed:
  `SELECT DISTINCT trace_id FROM spans` on `$db`, which must return exactly one
  row for a single-run fixture. `wait_for_payload_count`
  (otel_semconv_test.sh:45-61) becomes a wait for that trace id to appear with
  its `invoke_agent` parent and `chat` child, keeping the same 100-try, 0.05s
  budget and the same `fail` on timeout. The receiver already records
  `traceId` per span (otel_semconv_test.sh:117, 152), so no receiver change is
  needed.
- Route probe: delete the `opentelemetry` import test at
  otel_semconv_test.sh:243-260 and the `EXPORT_ROUTE == SDK*` branch at 379-380
  — both rest on the false premise. `export_tree` runs the `--file --replay`
  POST only when the tree's trace has not already arrived from the driver, and
  prints `ROUTE <label>: driver telemetry_autoexport` or
  `ROUTE <label>: test replay POST (…)` accordingly. Both routes are the real
  serialiser; the driver's needs no test-side transport at all, so it is the
  one to prefer, and the brief's rejection condition about feeding the receiver
  from the mapping module stays satisfied either way.
- Acceptance IDs: A1, A2, A3, A5, A7 (all regressions — the suite must prove
  them again from this host).
- Validation: `zsh tests/otel_semconv_test.sh` exits 0 twice in a row and
  prints both `TREE primary:` and `TREE secondary:` lines with different
  revisions; a mutation that reverts the selection to `splitlines()[ordinal-1]`
  reproduces `secondary: span … revision is 'v1.37.0', expected 'v1.36.0'`; a
  mutation that drops the `chat` child from `telemetry.py` still fails the
  suite, so the new selection did not turn the assertions into no-ops;
  `zsh tests/pm_flow_test.sh` and `zsh tests/store_ledger_test.sh` exit 0.
- Validation, corrected at review of cycle 006: the ordinal-revert negative
  above is unsound *on its own*, because the same task removes the duplicate
  export that made the ordinals wrong. With one payload per tree,
  `splitlines()[ordinal-1]` is accidentally correct again and the mutation
  passes. The negative must restore the precondition as well as the defect:
  inject a second copy of the primary tree's payload into `received.jsonl`
  after `export_tree … primary`, then revert the selection. Both halves proven
  at review — see `state.md`. The missing-child negative now fails at
  `wait_for_trace_tree` rather than at `expected exactly one chat child, got 0`;
  the wait is itself the tree assertion, so exit 1 with the trace id named is
  the correct observation.
- Depends on: T3.

## Task T5 — Prove A6 against a stock backend's own query API

- Status: done — accepted cycle 007 (GO). A6 proven live against `pm-flow-jaeger`
  on the review seat, with A1, A2, A3 re-asserted through the backend and A7
  held. Four review-side negatives fire (wrong trace id, absent revision tag,
  attempts row off by one, forced-unreachable skip path). The developer's own
  seat had no Docker socket and took the `SKIP:` path, so the live evidence is
  the review's — see `state.md`. This closes the last acceptance ID; every ID in
  the brief now has standing evidence.
- Why now: A6 says a Jaeger instance "queried at `/api/traces?service=pm-flow`
  returns the exported trace with the A1 span tree", and allows the handoff to
  record it unproven *only* "if Docker is not available on the host". At cycles
  003-006 it was not: `docker ps` exited 1 with
  `dial unix /Users/salah/.docker/run/docker.sock: connect: no such file or
  directory`. Probed again at cycle 007 and the condition has flipped —
  `docker ps` exits 0 and shows `jaegertracing/all-in-one` up 13 hours as
  `pm-flow-jaeger`, publishing 4318 and 16686. The escape hatch no longer
  applies, so A6 has to be earned.
- Outcome: `tests/otel_semconv_test.sh` exports the primary tree's real
  recorded run to a Jaeger instance over OTLP and asserts the A1 tree back out
  of Jaeger's **own query API**, not out of the test's receiver. Every
  assertion is made against what a stock backend decoded, stored and re-served:
  one `invoke_agent` span, exactly one `chat` child whose `CHILD_OF` reference
  points at it, the child's `gen_ai.usage.*` equal to the `attempts` row, and
  `pm_flow.semconv.revision` on every span of the trace. Where no Jaeger and no
  Docker exist, the check prints one explicit `SKIP` line naming what would
  settle it and the suite stays green.
- Paths: `tests/otel_semconv_test.sh`. No implementation file is expected to
  change; the engine already emits what A6 wants, as the live instance shows.
- Reuse: `export_tree`'s exporter invocation — `trace_export.py --otlp <url>
  --replay` is the brief's own documented usage (trace_export.py:10) and
  appends `/v1/traces` itself (trace_export.py:223-224), so the stdlib route
  needs no SDK, exactly as T4 established. The tree's trace id is the
  `SELECT DISTINCT trace_id FROM spans` the test already computes. The
  `attempts` join is the one `assert_received_tree` already runs.
- Selection: by this run's own trace id via `/api/traces/<traceID>`, for the
  same reason T4 stopped indexing by ordinal — the live Jaeger already holds
  203 unrelated `pm-flow` spans from the real install, so
  `/api/traces?service=pm-flow` unfiltered would assert on someone else's run.
  Probed at cycle 007: `/api/traces/<traceID>` returns HTTP 200 with the full
  tree, `references[].refType == "CHILD_OF"` giving the parent, and the usage
  and revision tags present.
- Instance handling: reuse a Jaeger already answering on 16686 and never tear
  it down — `pm-flow-jaeger` is the user's, it predates the test, and both
  ports are already bound so the brief's `docker run` would fail against it.
  Only if nothing answers may the test start its own with the brief's command,
  and then it removes only the container id it started.
- Acceptance IDs: A6 (primary), with A1, A2, A3 re-asserted through the backend
  and A7 held.
- Validation: `zsh tests/otel_semconv_test.sh` exits 0 and prints a
  `JAEGER primary: <traceID> invoke_agent -> <spanID> chat` line plus
  `PASS: a stock backend re-serves the invoke_agent -> chat tree`; pointing the
  Jaeger query at a trace id that was never exported fails with that id named;
  `zsh tests/pm_flow_test.sh` and `zsh tests/store_ledger_test.sh` exit 0.
- Depends on: T4.

## Integration and end-to-end validation

- T2 is the end-to-end gate and carries the viewer confirmation the brief names:
  it proves scenario 1 through the real record-then-export path. T3 refined what
  each span of the pair carries. T4 made that gate pass from this host by
  selecting each tree's payload by trace id. T5 is the last task: it closes the
  one acceptance ID the section has never proven, by asserting the same tree
  through a stock backend's query API rather than through the test's own
  receiver. The end-to-end proof standing at section end is T4's plus T5's.

## Known conflict outside owned paths

- `template/.agentic/pm_flow/catalog.py:250` mentions `gen_ai.*` in a comment
  and is owned by `persona-cards`, so A4's grep cannot be clean from here. The
  test exempts that one file by name, and only for a match on a comment line;
  a `gen_ai.` literal in its code still fails. The reword is escalated in the
  handoff and the exemption is deleted when it lands.

## Risks and rollback

- The conventions move between revisions; the pin confines the churn to one
  edit. Rollback: revert `telemetry.py` to its literal block; stored spans are
  unaffected.
- The wire route depends on a package the repository does not ship, so on a
  host without the SDK the strongest evidence available is the OTLP/JSON
  fallback. Rollback: none needed; the fallback is the same payload.
- A `chat` child is a new row every dispatch writes. No other suite reads the
  `spans` table (`grep -rn 'FROM spans\|spans\b' tests/pm_flow_test.sh
  tests/store_ledger_test.sh` returns nothing), so nothing counts rows and
  breaks. Rollback: stop writing the child; the parent is unchanged.
- A path-resolved module is one more way for an engine copy to be incomplete.
  The loader must be proven in all three layouts a run really uses: the source
  checkout, the installed package (`pm_flow/engine` beside `pm_flow/`), and an
  engine directory copied on its own, as `store_ledger_test.sh` does.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T2, T3, T4 | Receiver shows the tree; usage equals the store, and each aggregatable key is on exactly one span of the pair |
| A3 | T1, T2, T4 | Revision attribute on every span |
| A4 | T1 | Grep matches only `semconv.py` |
| A5 | T1, T2, T4 | Revision switch changes names in a copy, then in the receiver |
| A6 | T5 | Jaeger's own query API re-serves the exported trace with the A1 tree. Docker is available as of cycle 007, so the brief's unproven escape hatch no longer applies |
| A7 | T2, T4, T5 | Both suites exit 0 |
