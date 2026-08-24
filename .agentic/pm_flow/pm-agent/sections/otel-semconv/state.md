# otel-semconv section PM state

## Current task

- None. T3 was accepted in cycle 004 and was the last workplan task.

## Completed tasks and evidence

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
- The export route was settled by probe, not assumption. `trace_export.py
  --otlp` imports the OpenTelemetry SDK (`trace_export.py:183-194`);
  `ls .venv/lib/python3*/site-packages` shows only `pm_flow` and its dist-info,
  and `ls tests/packaging-build-wheelhouse` shows hatchling, packaging,
  pathspec, pluggy, tomlkit, trove_classifiers - no OTel. `pm_flow_test.sh`
  installs `--no-index` from that wheelhouse, so the wire route cannot be
  assumed and a network install must not be added to the suite. T2 therefore
  feeds one receiver by two routes with identical assertions: the driver's own
  `telemetry_autoexport` when the SDK is importable, and
  `trace_export.py --file --replay` POSTed by the test when it is not.
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

- None. The cycle-003 duplication defect is closed by T3, accepted cycle 004:
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

- None. T3 was the last task and is accepted, so every workplan task is done.
  Every brief acceptance ID has current evidence except A6, which the brief
  allows to be recorded unproven and which the handoff carries as such. The
  section is a candidate for COMPLETE at cycle 005; the only work that would
  reopen it is `persona-cards` rewording
  `template/.agentic/pm_flow/catalog.py:250`, at which point the test's
  one-file A4 exemption is deleted.
