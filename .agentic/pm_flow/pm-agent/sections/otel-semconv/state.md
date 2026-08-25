# otel-semconv section PM state

## Current task

- None. T4 was the last unfinished task and was accepted at cycle 006. The
  section's own suite is the section-end gate and it passes from this host.

## Reopened by portfolio review 007 — closed by T4, cycle 006

The section was marked COMPLETE at cycle 005 while `zsh
tests/otel_semconv_test.sh` exited 1 here with `secondary: span … revision is
'v1.37.0', expected 'v1.36.0'`. The cause was in the test, never in the
section's code: the receiver got four payloads, two per tree, and
`assert_received_tree 2` read the primary's second copy. The duplicate came from
running both export routes unconditionally — `telemetry_autoexport` ships a full
payload over stdlib `urllib` on its own (see the corrected active decision
below), and `export_tree` shipped the same spans again.

T4 fixed both halves: the test now selects by the tree's own trace id and runs
its replay POST only when the driver's export did not arrive. The suite exits 0
here, twice in a row, and both routes have now been observed delivering. The
portfolio note's separate suspicion — the dispatch resolving `pm_flow.semconv`
through the host editable venv — was disproved by the cycle-006 probe and stays
disproved: each tree's dispatch loads its own copied module, which is why the
two trees still report different revisions.

## Section-end verification, cycle 005 (on merged `main`) — superseded

The claim below that `zsh tests/otel_semconv_test.sh` exits 0 on `main` did not
reproduce at cycle 006 and is superseded by T4's evidence, which does. Everything
else in it — the T3 code being on `main`, the A4 grep, the A6 docker probe,
`pm_flow_test.sh` — still stands.

- The accepted T3 code is on `main`:
  `grep -n 'include_non_convention_attributes' template/.agentic/pm_flow/telemetry.py`
  → `247` (the keyword-only default), `263` and `304` (the two gated blocks),
  `633` and `742` (the two child call sites passing `False`).
- A1, A2, A3, A5: `zsh tests/otel_semconv_test.sh` exits 0 on `main` and prints
  `ROUTE: stdlib OTLP/JSON fallback via trace_export.py --file --replay` with no
  `bind prohibited` suffix, so the receiver bound a real TCP socket;
  `TREE primary: 61e56eb0442d29d7 invoke_agent -> b37abcf1cb062168 chat
  parent=61e56eb0442d29d7 input_tokens=31 output_tokens=13`, the same tree for
  the secondary pin, both `SPLIT` lines identical to cycle 004, and all six PASS
  lines.
- A4: the grep matches `src/pm_flow/semconv.py` lines 8, 9, 24-28, 32, 33 and
  the one exempted comment at `template/.agentic/pm_flow/catalog.py:250`.
  The reword has not landed yet, so the exemption stays.
- A6 remains unproven, and the probe was re-run this cycle rather than carried
  over: `docker ps` → exit 1,
  `failed to connect to the docker API at unix:///Users/salah/.docker/run/docker.sock
  … dial unix … connect: no such file or directory`. The brief's escape hatch
  applies; `docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one`
  plus `curl -s 'http://localhost:16686/api/traces?service=pm-flow'` is what
  settles it.
- A7: `zsh tests/pm_flow_test.sh` exits 0 on `main` with 10 PASS lines, after
  the other sections' merges, so nothing merged since cycle 004 has regressed
  this section.

## Completed tasks and evidence

- T4 — accepted cycle 006 (GO_WITH_CHANGES). Acceptance IDs A1, A2, A3, A5, A7.
  - Reviewed at
    `/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/otel-semconv`.
    `git status --porcelain` there shows exactly ` M tests/otel_semconv_test.sh`;
    `git diff --stat HEAD` is `1 file changed, 83 insertions(+), 43 deletions(-)`.
    `telemetry.py`, `semconv.py`, `trace_export.py` and `driver.zsh` untouched,
    as the assignment required.
  - The fix: `assert_received_tree` reads `SELECT DISTINCT trace_id FROM spans`
    off the store it is already handed, fails if that is not exactly one row,
    then folds every line of `received.jsonl` into `spans_by_id` keyed on
    `spanId` for spans whose `traceId` matches. `wait_for_payload_count` is
    replaced by `wait_for_trace_tree`, which polls the same predicate
    (`received_trace_tree_present`) for an `invoke_agent` parent with a `chat`
    child on that trace, same 100-try / 0.05s budget, and fails naming the
    trace id. `export_tree` runs its `--file --replay` POST only when that
    predicate is already false, and prints which route delivered. The
    `opentelemetry` import probe and the `EXPORT_ROUTE == SDK*` branch are gone.
  - A1, A2, A3, A5, A7: `zsh tests/otel_semconv_test.sh` exits 0 twice in a row
    on this seat. Both runs print `ROUTE primary: driver telemetry_autoexport`
    and `ROUTE secondary: driver telemetry_autoexport` — the receiver bound TCP
    here, so the payload arrived from the driver's own export with **no
    test-side transport at all**, the strongest evidence the section has for
    scenario 1. Run 1: `TREE primary: b0f09aa1761e9936 invoke_agent ->
    0f28bdc3a05d099a chat parent=b0f09aa1761e9936 input_tokens=31
    output_tokens=13`, `TREE secondary: fbdee39840c6c0e5 invoke_agent ->
    9cf4092c035609fc chat parent=fbdee39840c6c0e5 …`. Run 2: `4a626ca7929f9e9e`
    / `57e20b337a4d510c`. Both `SPLIT` lines byte-identical to cycle 004, and
    all six PASS lines, including
    `PASS: changing only the pin changes the receiver provider attribute` —
    which is where the two revisions being different is asserted, each tree
    against its own loaded `semconv.py`.
  - The by-trace selection is proven necessary, not just present. The
    assignment's prescribed negative — revert to `splitlines()[ordinal-1]` —
    cannot fail on its own, because the same task removed the duplicate export
    that made the ordinals wrong; the developer reported this honestly rather
    than manufacturing the message. Reviewed with the precondition restored, in
    a copy of the whole tree (`cycles/006/review/`, deleted after):
    - Duplicate arrival alone, selection intact: after `export_tree … primary`,
      append the primary's payload to `received.jsonl` a second time
      (`REVIEW: received.jsonl now has 2 payloads`) → exit 0, all six PASS
      lines. The selection is robust to however many payloads a tree delivers.
    - Duplicate arrival plus the ordinal revert → exit 1 with exactly the
      prescribed message, `secondary: span a942e17fd6b2691e revision is
      'v1.37.0', expected 'v1.36.0'`. Same fixture, same duplicate, one line of
      selection different: that line is what closes the defect.
  - A1, negative: the `chat` child's `insert_span` replaced by `_ = (…)` in a
    copy of `telemetry.py` → exit 1,
    `FAIL: receiver never got trace fe8e2aa1445c13762936664ede39dcb3 with
    invoke_agent parent and chat child`. It fails at the wait, not at
    `expected exactly one chat child, got 0`, because the wait is now itself the
    tree assertion — the suite still fails and names the trace, so the new
    selection did not turn the assertions into no-ops. That run also printed
    `ROUTE primary: test replay POST (OTLP/JSON over TCP)`, so the fallback
    branch is exercised on the same host that takes the driver route when the
    tree is intact.
  - A7: `zsh tests/pm_flow_test.sh` exits 0 with 10 PASS lines;
    `zsh tests/store_ledger_test.sh` → `store ledger tests passed`, exit 0.
  - A4 still holds: the grep over `template/` and `src/` matches
    `src/pm_flow/semconv.py` lines 8, 9, 24-28, 32, 33 and the one exempted
    comment, which is now at `template/.agentic/pm_flow/catalog.py:254` — the
    file has shifted by four lines since it was recorded as 250 elsewhere in
    this file. The test exempts by file name, not by line, so the shift is
    cosmetic. No `gen_ai.` literal was introduced in the test's own strings; the
    new code uses the `"gen" + "_ai."` splitting convention throughout.

- T3 — accepted cycle 004 (GO). Acceptance IDs A1, A2, A3, A7.
  - Reviewed at
    `/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/otel-semconv`.
    `git status --short` there shows exactly
    ` M template/.agentic/pm_flow/telemetry.py` and
    ` M tests/otel_semconv_test.sh`; `git diff --stat HEAD` is
    `2 files changed, 54 insertions(+), 15 deletions(-)`. `src/pm_flow/semconv.py`,
    `driver.zsh` and `trace_export.py` are untouched.
  - The fix: one keyword-only `include_non_convention_attributes=True` on
    `semconv_attributes` (telemetry.py:247) gating the three `llm.token_count.*`
    puts (263) and the `pm_flow.` cost/cache/reasoning block plus the
    `input.value` / `output.value` bodies (304); passed as `False` at the two
    child call sites only (633 `attempt-start`, 742 `attempt-end`). The
    `SEMCONV` branch still receives the real `usage`, so the child's convention
    usage is untouched.
  - A1, A3: `zsh tests/otel_semconv_test.sh` exits 0 and prints
    `ROUTE: stdlib OTLP/JSON fallback via trace_export.py --file --replay`,
    `TREE primary: c3e689945daa9ad5 invoke_agent -> bfb8e2385742aaf4 chat
    parent=c3e689945daa9ad5 input_tokens=31 output_tokens=13`, the same tree for
    the secondary pin, and six PASS lines including the new
    `PASS: non-convention usage and bodies stay only on the invoke_agent parent`.
    The revision loop (otel_semconv_test.sh:447-453) still asserts
    `pm_flow.semconv.revision` on every received span, parent and child.
  - A1, A3 (T3's own split): both pins print
    `SPLIT …: parent_only=llm.token_count.prompt,llm.token_count.completion,
    llm.token_count.total,pm_flow.cost_usd,input.value,input.mime_type,
    output.value,output.mime_type
    child_kept=gen_ai.usage.input_tokens,gen_ai.usage.output_tokens,
    openinference.span.kind,llm.model_name`. The assertion
    (otel_semconv_test.sh:495-517) reads `parent["attributes"]` and
    `child["attributes"]` off the receiver payload, not the `spans` table:
    absence from the child is checked for all eleven keys unconditionally,
    presence on the parent only for keys the run produced.
  - A2: the same run. The child's `gen_ai.usage.*` is still compared against
    `SELECT a.input_tokens, a.output_tokens FROM spans child JOIN attempts a ON
    child.parent_span_id = a.span_id WHERE child.span_id = ?`
    (otel_semconv_test.sh:470-489) and the parent is still asserted to carry
    neither key (465-466). The join passing also re-proves `attempts.span_id`
    still points at the `invoke_agent` parent.
  - The parent's attribute set is byte-identical to HEAD, proven not argued.
    `cycles/004/probe_attrs.py` loads `telemetry.py` by path and dumps
    `semconv_attributes(span_kind="AGENT", …)` for a usage dict carrying all
    seven counters; `cycles/004/review_parent_identical.sh` runs it against the
    working tree, swaps in `git show HEAD:…/telemetry.py`, runs it again and
    diffs. `parent diff exit=0`. The HEAD build rejects the new keyword
    (`semconv_attributes() got an unexpected keyword argument
    'include_non_convention_attributes'`), so the two builds really are
    different code. The same probe shows the gate removes exactly eleven keys
    from the child — the three `llm.token_count.*`, `pm_flow.cost_usd`,
    `pm_flow.cache_read_tokens`, `pm_flow.cache_write_tokens`,
    `pm_flow.reasoning_tokens` and both body pairs — and nothing else, leaving
    24 keys including all `gen_ai.*`, `openinference.span.kind`,
    `llm.model_name` / `llm.provider` / `llm.system`,
    `llm.invocation_parameters`, `session.id` and the `pm_flow.` identity block.
  - Both negatives reproduced review-side (`cycles/004/review_negatives.sh`,
    each mutation restored from a copy of the file):
    - gate dropped at the `attempt-end` child call (line 742) →
      `primary: non-convention attribute duplicated on chat child:
      llm.token_count.prompt`, exit 1.
    - gate dropped at the `attempt-start` child call (line 633) →
      `primary: non-convention attribute duplicated on chat child: input.value`,
      exit 1, so the body duplication is caught independently of the counts.
  - A7 (`cycles/004/review_suites.sh`): `zsh tests/otel_semconv_test.sh` = 0,
    `zsh tests/pm_flow_test.sh` = 0 (10 PASS lines),
    `zsh tests/store_ledger_test.sh` = 0 (`store ledger tests passed`), and
    `zsh tests/otel_semconv_test.sh` = 0 again with an untracked
    `PM_REVIEW_UNTRACKED_PROBE.txt` in the tree.
  - A4 still holds: the grep over `template/` and `src/` matches only
    `src/pm_flow/semconv.py` and the exempted comment at
    `template/.agentic/pm_flow/catalog.py:250`.
  - Not covered by the suite, covered by the probe: the stub emits no cache or
    reasoning tokens, so `pm_flow.cache_read_tokens`,
    `pm_flow.cache_write_tokens` and `pm_flow.reasoning_tokens` never enter
    `produced_parent_only` and their presence-on-parent side is unasserted in
    the run. Their absence from the child *is* asserted unconditionally, and
    the probe shows all three on the parent and off the child.

- T2 — accepted cycle 003 (GO_WITH_CHANGES). Acceptance IDs A1, A2, A6, A7,
  with A3 and A5 re-asserted on the receiver.
  - Reviewed at
    `/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/otel-semconv`.
    `git status --porcelain` there shows exactly
    ` M template/.agentic/pm_flow/telemetry.py` and
    ` M tests/otel_semconv_test.sh` — no path outside the two writable ones,
    and `src/pm_flow/semconv.py` is untouched (the usage gate went into
    `semconv_attributes`' caller instead, telemetry.py:272-275).
  - A1, A3, A5: `zsh tests/otel_semconv_test.sh` exits 0 and prints
    `ROUTE: stdlib OTLP/JSON fallback via trace_export.py --file --replay`,
    `TREE primary: d495f0b3b5695521 invoke_agent -> 64d16a501343b8dc chat
    parent=d495f0b3b5695521 input_tokens=31 output_tokens=13`, then the same
    tree for the secondary pin and five PASS lines. On this seat the receiver
    bound TCP (the route string has no `bind prohibited` suffix), so the
    payload crossed a real HTTP socket; the SDK is still absent, so the payload
    itself is `trace_export.py --file --replay` output, not anything the test
    assembled.
  - A2: the same run. The receiver's `chat` child usage is compared against
    `SELECT a.input_tokens, a.output_tokens FROM spans child JOIN attempts a ON
    child.parent_span_id = a.span_id WHERE child.span_id = ?`, and the parent is
    asserted to carry neither `gen_ai.usage.*` key.
  - Three review-side mutations, each on an rsync copy of the worktree, each
    deleted afterwards (`cycles/003/review_mutation.zsh`,
    `cycles/003/review_negatives.zsh`):
    - child usage dropped (`usage=usage` → `usage={}` at the `attempt-end`
      child call) → `primary: child input usage is None, attempt has 31`,
      `MUTATION_EXIT=1`.
    - child `insert_span` replaced by `pass` → `primary: expected exactly one
      chat child, got 0`, exit 1.
    - usage gate removed (`convention_usage = usage`) → `primary: convention
      usage remained on invoke_agent parent`, exit 1.
  - A7: `zsh tests/pm_flow_test.sh` exits 0 with 10 PASS lines;
    `zsh tests/store_ledger_test.sh` → `store ledger tests passed`, exit 0;
    `zsh tests/otel_semconv_test.sh` exits 0 with an untracked
    `REVIEW-DIRTY-PROBE.txt` in the worktree (`DIRTY_EXIT=0`), so the T1
    ownership gate is genuinely gone —
    `grep -rn 'git status --porcelain' tests/otel_semconv_test.sh` is empty.
  - A4 still holds: the grep over `template/` and `src/` matches only
    `src/pm_flow/semconv.py` and the exempted comment at
    `template/.agentic/pm_flow/catalog.py:250`.
  - A6 unproven, as the brief allows. Not settled from this seat either: this
    session's shell refused `docker info` (`This command requires approval`)
    and refused to stat `/Users/salah/.docker/run/docker.sock`. The developer's
    own run of `docker run -d -p 4318:4318 -p 16686:16686
    jaegertracing/all-in-one` returned exit 1 with `dial unix
    /Users/salah/.docker/run/docker.sock: connect: no such file or directory`.
    That command plus `curl -s
    'http://localhost:16686/api/traces?service=pm-flow'` remains what settles
    it.

- T1 — accepted cycle 002. Acceptance IDs A3, A4, A5.
  - A3, A5: `zsh tests/otel_semconv_test.sh` exits 0 and prints
    `resolved semconv.py: …/secondary/src/pm_flow/semconv.py`, then the three
    PASS lines. The test records a run span, a `span-start` row and an attempt
    through the real `telemetry.py` CLI and reads the `spans` table back; all 3
    rows carry `pm_flow.semconv.revision`. The secondary tree has only
    `REVISION` edited to `v1.36.0` and its rows carry `gen_ai.system` with
    `gen_ai.provider.name` absent; the primary is the reverse.
  - A4: `grep -rn 'gen_ai\.' template/ src/ --include='*.py' --include='*.zsh'
    --include='*.sh'` matches `src/pm_flow/semconv.py` and the one exempted
    comment at `template/.agentic/pm_flow/catalog.py:250`, nothing else. The
    telemetry.py prose matches at 12, 15, 27 and 162 are gone.
  - Mutation proof, run on a git-initialised copy of the worktree
    (`cycles/002/review/mutate.sh`): dropping the `insert_span` stamp gives
    `span … revision is None, expected 'v1.37.0'`; emitting both provider names
    gives `unexpected provider attribute gen_ai.system`; a stray
    `STRAY = "gen_ai.usage.cost"` in telemetry.py gives
    `FAIL: standard GenAI literal outside the mapping module`. Baseline on the
    same copy exits 0.
  - Both suites exit 0: `zsh tests/store_ledger_test.sh` → `store ledger tests
    passed`; `zsh tests/pm_flow_test.sh` → 10 PASS lines, exit 0.
  - `git -C <worktree> status --porcelain` shows only
    ` M template/.agentic/pm_flow/telemetry.py`, `?? src/pm_flow/semconv.py`,
    `?? tests/otel_semconv_test.sh`.

## Active decisions

- The revision is stamped per span at record time; `trace_export.py` stays with
  trace-commands.
- `semconv.py` is loaded from `telemetry.py` by path, resolved from `__file__`,
  not by `import pm_flow.semconv`. Reasons observed this cycle: the driver runs
  `python3 "$SCRIPT_DIR/telemetry.py"` (driver.zsh:698, 774, 796) with no
  guarantee the package is importable there; `telemetry.py` is standard-library
  only by design; and `tests/store_ledger_test.sh` runs it out of an engine
  directory copied on its own with no package beside it. An installed-package
  import would also read the installed copy and make A5's edit-in-a-copy prove
  nothing.
- No `chat` span exists today: `driver.zsh:767` calls `attempt-start` without
  `--span-kind`, so every dispatch is a single `AGENT` span. `driver.zsh` is not
  an owned path, so `telemetry.py` writes the `invoke_agent` parent and the
  `chat` child itself (T2), leaving the printed `span_id`, the traceparent and
  the `attempt-end` lookup unchanged.
- A2 is joined as `spans.parent_span_id = attempts.span_id` (the `chat` child's
  parent), because the `attempts` row keeps pointing at the `invoke_agent` span.
  Repointing `attempts.span_id` at the child would change the traceparent handed
  to the child CLI for no gain.
- Token counts are only known at `attempt-end`: `cmd_attempt_end`
  (telemetry.py:653-706) assembles `usage` from the response envelope and the
  codex event stream, then merges it onto the parent span through `finish_span`.
  So the `chat` child is inserted at `attempt-start` (the parent exists, the
  start time is right) and finished at `attempt-end`, and `attributes_for` gates
  `gen_ai.usage.*` on the `chat` operation so the counts stop landing on the
  parent. `llm.token_count.*` is OpenInference and stays where it is.
- No `chat` child is written when `SEMCONV` is `None`. The pair is a
  convention-defined structure, and the copied-engine layout has no convention
  module; inventing a child there would put a bare span in the tree the degrade
  path is meant to keep out.
- **Corrected cycle 006.** T2's export route rested on "`trace_export.py --otlp`
  imports the OpenTelemetry SDK (`trace_export.py:183-194`)". That is false of
  the file: the SDK is imported only by the `grpc` branch
  (trace_export.py:259-274), `--protocol` defaults to `http`
  (trace_export.py:475), and the `http` branch posts OTLP/JSON with stdlib
  `urllib` alone (trace_export.py:218-256). trace_export.py:24 says so outright
  — "Only `--protocol grpc` imports the SDK" — and
  `git log -S'args.protocol == "http"'` attributes that route to
  `54da8ab chore(trace-commands): accepted cycle 002`.
  Still true: the SDK is absent here (`import opentelemetry` →
  `ModuleNotFoundError` under `/Users/salah/code/personal/pm-flow/.venv/bin/python3`),
  `ls tests/packaging-build-wheelhouse` shows hatchling, packaging, pathspec,
  pluggy, tomlkit, trove_classifiers and no OTel, and `pm_flow_test.sh` installs
  `--no-index` from it, so no network install may be added to the suite.
  Changed: the wire route does not need the SDK, so the driver's own
  `telemetry_autoexport` (driver.zsh:775-781) is the primary route and
  `trace_export.py --file --replay` POSTed by the test is the fallback for a
  receiver that could not bind TCP. Running both unconditionally is what
  produces the duplicate payloads T4 fixes.
- **Confirmed cycle 006, both branches observed.** The route is no longer
  inferred from what is installed; the test asks the receiver whether the tree's
  trace already arrived and prints the answer. On the review seat the driver's
  own export delivered both trees (`ROUTE …: driver telemetry_autoexport`) with
  no test-side transport. On the developer's seat TCP and Unix binds were both
  refused, the receiver fell back to a FIFO, the driver's POST to
  `http://localhost` reached nothing, and the test's replay POST delivered
  (`ROUTE …: test replay POST (OTLP/JSON request stream; bind prohibited)`).
  Same assertions, same serialiser, both green. A tree that arrives by neither
  route now fails with its trace id named rather than being read past.
- The receiver is fed without editing anything outside owned paths.
  `telemetry_autoexport` (driver.zsh:728-735) reads
  `config_setting telemetry otlp_endpoint` and fires at run end, and the stock
  `config.json` has no `telemetry` block, so the disposable project's config
  gets one pointing at the receiver.
- `pm-flow trace export` does not exist as a subcommand yet: `grep -rln 'trace
  export' template/ src/ tests/` matches only `driver.zsh`,
  `requirements-telemetry.txt` and an on-demand fixture, and that command
  belongs to `trace-commands`. The brief's scenario 1 names it, but this section
  proves the scenario by calling `trace_export.py` by path, as driver.zsh:732
  does.
- Adding the child row is safe for the other suites: `grep -rn 'FROM spans\|
  spans\b' tests/pm_flow_test.sh tests/store_ledger_test.sh` returns nothing, so
  neither reads or counts the `spans` table.
- `tests/fixtures/stub_success.zsh` emits `{"is_error":false,"result":…,
  "session_id":""}` with no `usage` block, so a dispatch driven by it records
  null tokens and A2 would compare nothing to nothing. T2's stub must emit a
  usage block `usage_from_response` (telemetry.py:166-176) reads:
  `input_tokens`, `output_tokens`, optionally `cache_read_input_tokens` and
  `cache_creation_input_tokens`.
- Both pins are verified against the registry, not assumed. `fetch.sh --url
  https://raw.githubusercontent.com/open-telemetry/semantic-conventions/v1.37.0/model/gen-ai/registry.yaml`
  reports `gen_ai.provider.name`, `gen_ai.operation.name`, `gen_ai.agent.name`,
  `gen_ai.request.model`, `gen_ai.usage.input_tokens` and
  `gen_ai.usage.output_tokens` present, and `gen_ai.system`,
  `gen_ai.request.reasoning_effort` and `gen_ai.usage.cost` absent. The same
  fetch at `v1.36.0` reports `gen_ai.system` present and
  `gen_ai.provider.name` absent. So the provider rename is a genuine
  revision difference, and `thinking` correctly keeps the `pm_flow.` prefix -
  no revision defines a reasoning-effort request attribute.
- The loader resolves `semconv.py` from a candidate list and degrades openly
  when none exists; all three layouts are now observed, not inferred. Installed
  (a simulated wheel: `pm_flow/semconv.py` beside `pm_flow/engine/telemetry.py`)
  resolves and records `gen_ai.provider.name=anthropic`,
  `gen_ai.request.model=claude-opus-5`, revision `v1.37.0`. The checkout layout
  is what `otel_semconv_test.sh` drives. The engine copied alone resolves
  nothing: `SEMCONV_PATH` is `None`, `run-start` and `attempt-start` both exit
  0, and the rows carry `openinference.span.kind` and `pm_flow.*` with no
  GenAI names and no revision. Original reasoning, still accurate: installed,
  where
  `template/.agentic/pm_flow` is force-included as `pm_flow/engine`
  (pyproject.toml), so `__file__/../../semconv.py` is the package copy; the
  source checkout, `template/.agentic/pm_flow/../../../src/pm_flow/semconv.py`;
  and an engine directory copied alone (`store_ledger_test.sh:52`), where no
  copy exists. In that third layout the recorded span carries the `pm_flow.*`
  attributes and no GenAI names - a stated limit, not a duplicated mapping, and
  not a dispatch failure. `v1.37.0` is confirmed to exist as a
  semantic-conventions release tag.
- The usage gate ended up in the caller, not in `attributes_for`. The workplan
  said `attributes_for` would gate `gen_ai.usage.*` on the operation; cycle 003
  instead computes `convention_usage` in `semconv_attributes`
  (telemetry.py:272-275) and hands `attributes_for` an empty usage dict unless
  the span kind maps to `chat`. `semconv.py` is therefore unmodified, which the
  assignment allowed. Accepted, with one consequence recorded: `attributes_for`
  is a published interface (brief, Interfaces produced) and still emits
  `gen_ai.usage.*` for whatever `span_kind` it is handed, so a future second
  caller must gate it too. `telemetry.py` is the only caller today.
- The duplicated attributes are removed from the `chat` child, not moved to it.
  Both sides were considered: OpenInference puts the bodies and token counts on
  the LLM span, but `llm.token_count.*` staying on the `invoke_agent` parent is
  already T2's accepted contract and a rejection condition of cycle 003, and
  splitting the set — counts on the parent, bodies on the child — would leave a
  reader guessing which span to open. So all eight keys stay on the parent and
  the parent's attribute set is byte-identical to today; the child is what
  changes.
- Dropping `usage` from the child's `semconv_attributes` call is not a valid
  fix on its own. The child's `gen_ai.usage.*` is derived from that same
  `usage` argument (telemetry.py:272-283), so an empty usage would satisfy T3
  by breaking A2. The call must keep receiving `usage` and suppress only the
  non-convention consumers of it.
- A name the pinned revision does not define is not emitted under `gen_ai.`.
  This retires `gen_ai.usage.cost` (telemetry.py:260), which no revision
  defines; the same number is already recorded as `pm_flow.cost_usd`.
- A3's stamp goes in `insert_span` (telemetry.py:352), not in
  `semconv_attributes`. Observed cycle 002: `cmd_span_start` (telemetry.py:453-458)
  builds its attributes from `parse_attrs` and never calls `semconv_attributes`,
  so a stamp applied only in the mapping would miss every `span-start` row while
  A3 says *every* emitted span. `insert_span` is the one choke point all writers
  (`cmd_run_start`, `cmd_span_start`, `cmd_attempt_start`, and T2's `chat` child)
  pass through.
- The three layouts the loader must survive are settled by inspection, not
  guessed: installed is `pyproject.toml:51` force-including
  `template/.agentic/pm_flow` as `pm_flow/engine`, so `semconv.py` sits one
  directory above `telemetry.py`'s own; the checkout is three directories above
  plus `src/pm_flow/`; the copied engine is `store_ledger_test.sh:52`
  (`cp -R template/.agentic/pm_flow …`) with no `src/` anywhere near it.
  `pm_flow_test.sh` builds a wheel and resolves the engine out of the installed
  package (`pm_flow_test.sh:181-196`), so T2's end-to-end proof runs in the
  installed layout, where the loader resolves.

## Blockers

- None external, and none open. The ordinal-indexing defect that reopened the
  section is closed by T4, accepted cycle 006: the suite exits 0 here twice in a
  row, stays correct under a deliberately duplicated arrival, and still fails
  when the `chat` child is removed.
- The cycle-003 duplication defect is closed by T3, accepted cycle 004:
  the receiver now shows each of the eleven non-convention keys on the
  `invoke_agent` parent only, and reverting either child call site fails the
  test. No stock backend double-counts token totals or cost over a trace, and
  no dispatch stores its prompt and result twice.
- The T1 `git status --porcelain` gate is gone, confirmed this cycle: the grep
  for it is empty and the suite exits 0 with an untracked probe file present.
- Docker availability for A6 is still unsettled, now on both seats: the
  developer's `docker run …` returned `connect: no such file or directory` for
  `/Users/salah/.docker/run/docker.sock`, and this review seat's shell refused
  both `docker info` and a stat of that socket. A6's own escape hatch covers
  it; the Jaeger command plus `curl -s
  'http://localhost:16686/api/traces?service=pm-flow'` is what settles it, and
  the handoff carries it as unproven.
- One cross-section request is open, not a blocker: A4's grep matches a
  prose comment at `template/.agentic/pm_flow/catalog.py:250`, a file owned by
  `persona-cards`. The test exempts that one file for comment lines only; the
  reword goes upward in the handoff.
- Cycle 001 returned BLOCKED with an empty tree
  (`git status --porcelain` on the worktree printed nothing; no
  `src/pm_flow/semconv.py`, no `tests/otel_semconv_test.sh`) and the review
  returned NO_GO with all three acceptance IDs NOT MET. Both claimed
  blockers were probed and neither holds:
  - "the copied engine layout breaks `store_ledger_test.sh`" -
    `grep -n 'spans\|attributes' tests/store_ledger_test.sh` returns nothing:
    that suite asserts the cost and attempt ledger, never the `spans` table.
    `driver.zsh:700, 774, 796` swallow a telemetry failure (`|| return 0`,
    `|| true`, `2>/dev/null`), so even an unresolvable loader cannot break a
    dispatch there.
  - "the sanctioned fetch route is prohibited" - `zsh fetch.sh --url
    https://github.com/open-telemetry/semantic-conventions/releases/tag/v1.37.0`
    exited 0 and returned the release page, confirming the tag exists. The
    `nice(5) failed` lines are a non-fatal warning the sandbox prints for any
    backgrounded job; `pm_flow_test.sh` printed them and still exited 0.

## Next eligible task

- None. Every workplan task is done and every brief acceptance ID except A6 has
  standing evidence from this host, recorded above. A6 keeps the brief's own
  escape hatch: Docker is absent here, so it is carried as unproven with the
  Jaeger command as what settles it.
- Two follow-ups belong to whoever picks them up, and neither reopens this
  section on its own:
  - `persona-cards` rewording the `gen_ai.*` mention in
    `template/.agentic/pm_flow/catalog.py` (line 254 as of cycle 006), at which
    point the test's one-file A4 exemption is deleted.
  - A host with Docker settling A6 by running the brief's Jaeger command.
