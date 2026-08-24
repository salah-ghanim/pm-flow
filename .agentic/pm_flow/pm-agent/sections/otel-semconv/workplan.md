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

### Export route, decided by probe

`trace_export.py --otlp` imports the OpenTelemetry SDK and exits with
instructions when it is missing (`trace_export.py:183-194`). The SDK is not
installed: `.venv/lib/python3*/site-packages` holds only `pm_flow`, and
`tests/packaging-build-wheelhouse` - the pinned, hashed, `--no-index`
wheelhouse `pm_flow_test.sh:167-182` builds from - carries hatchling and its
build deps and nothing else. So the test cannot assume the wire route works and
must not add a network install to a suite that is deliberately offline.

Two routes into one receiver, the assertions identical:

- SDK importable: the driver's own `telemetry_autoexport` POSTs protobuf to the
  receiver; the test decodes it with `opentelemetry.proto`, which is present
  whenever the exporter is.
- SDK absent: after the same driver run, `trace_export.py --file … --replay`
  writes OTLP/JSON from the real serialiser and the test POSTs those lines to
  the same receiver at `/v1/traces`.

The test prints which route ran. The fallback is a stated limit - the HTTP hop
is the test's, the payload is pm-flow's - and it is not to be preferred when
the SDK is there.

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

## Integration and end-to-end validation

- T2 is the end-to-end gate and carries the viewer confirmation the brief names:
  it proves scenario 1 through the real record-then-export path. T3 is the last
  task and re-runs that same gate, so the end-to-end proof is the one that
  stands at section end.

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
| A1, A2 | T2, T3 | Receiver shows the tree; usage equals the store, and each aggregatable key is on exactly one span of the pair |
| A3 | T1, T2 | Revision attribute on every span |
| A4 | T1 | Grep matches only `semconv.py` |
| A5 | T1, T2 | Revision switch changes names in a copy, then in the receiver |
| A6 | T2 | Jaeger API returns the tree, or recorded unproven |
| A7 | T2 | Both suites exit 0 |
