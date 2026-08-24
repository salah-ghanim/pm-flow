# otel-semconv section PM state

## Current task

- T2, eligible now that T1 is accepted (cycle 002, GO_WITH_CHANGES): emit the
  `invoke_agent` → `chat` pair, prove it through an independent OTLP receiver,
  and cover A1, A2, A6, A7. T2 also deletes the working-tree ownership
  assertion T1 left at the tail of `tests/otel_semconv_test.sh`.

## Completed tasks and evidence

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

- None. One defect outlives cycle 002 and is carried into T2, not a blocker:
  `tests/otel_semconv_test.sh` ends with a `git status --porcelain` assertion
  that fails on any path outside the three owned ones. Observed on a copy with
  one unrelated edit: `FAIL: modified path is outside this assignment:
   M README.md`, exit 1. That is a cycle-scoped ownership check, and as a
  permanent regression test it breaks A7 in any dirty checkout - including the
  main checkout today, whose `.agentic/` state files are modified. T2 deletes
  it; the ownership check stays where it belongs, in review.
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

- T2. T1 has landed, so its only dependency is satisfied.
