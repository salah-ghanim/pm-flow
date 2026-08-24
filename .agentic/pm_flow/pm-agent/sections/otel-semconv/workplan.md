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

- Status: pending.
- Outcome: `telemetry.py` records a `chat` child under each dispatch's
  `invoke_agent` span and puts the usage attributes on the child; the test
  starts a standard-library OTLP/HTTP receiver, drives one stub dispatch
  through the public driver, exports with `trace_export.py --otlp`, and asserts
  the tree, the usage equal to the `attempts` row, and the revision on every
  span. A5's revision switch is re-asserted on what the receiver sees rather
  than on the stored attributes. With Docker present the A6 Jaeger command is
  run and its response recorded; absent, the result says so.
- Paths: `template/.agentic/pm_flow/telemetry.py`, `tests/otel_semconv_test.sh`.
- Reuse: T1's mapping; the disposable-project setup from `tests/pm_flow_test.sh`;
  `trace_export.py` unchanged.
- Acceptance IDs: A1, A2, A6, A7.
- Validation: `zsh tests/otel_semconv_test.sh` exits 0; a mutation that drops
  the `chat` child's usage attributes fails it; `zsh tests/pm_flow_test.sh` and
  `zsh tests/store_ledger_test.sh` exit 0;
  `curl -s 'http://localhost:16686/api/traces?service=pm-flow'` shows
  `invoke_agent` and `chat` for the exported trace, or Docker is recorded
  absent.
- Depends on: T1.

## Integration and end-to-end validation

- T2 is the end-to-end gate and carries the viewer confirmation the brief names;
  it is the last task because it proves scenario 1 through the real
  record-then-export path.

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
- A path-resolved module is one more way for an engine copy to be incomplete.
  The loader must be proven in all three layouts a run really uses: the source
  checkout, the installed package (`pm_flow/engine` beside `pm_flow/`), and an
  engine directory copied on its own, as `store_ledger_test.sh` does.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T2 | Receiver shows the tree; usage equals the store |
| A3 | T1, T2 | Revision attribute on every span |
| A4 | T1 | Grep matches only `semconv.py` |
| A5 | T1, T2 | Revision switch changes names in a copy, then in the receiver |
| A6 | T2 | Jaeger API returns the tree, or recorded unproven |
| A7 | T2 | Both suites exit 0 |
