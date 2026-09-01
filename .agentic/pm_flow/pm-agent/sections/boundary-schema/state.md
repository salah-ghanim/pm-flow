# boundary-schema section PM state

## Current task

- T3 — one cli definition across `pm_flow.sh`'s `cmd_config`, `topology.py` and
  `agent_exec.sh`. T2 accepted at cycle 002.

## Completed tasks and evidence

- T2 — shell validators derive from the schemas. Acceptance A3, A5.
  Accepted cycle 002.
  - Delivered: `validate_section_brief`, `validate_handoff`,
    `handoff_budget_report`, `markdown_verdict_parse`, `refresh_sections_index`'s
    index preamble and `cmd_init_section`'s handoff template all read
    `schemas/{section_brief,handoff}.schema.json` at call time;
    `markdown_verdict_parse` is now a pipe into `export.py verdict`;
    `parse_brief` returns `priority_loss` and the schema requires it.
    Three new fixtures: `brief_priority_missing_loss.md`,
    `brief_priority_unknown.md`, `handoff_over_bytes.md`.
  - A3: `zsh tests/boundary_schema_test.sh` exits 0 and prints eleven markdown
    fixtures with two agreeing verdicts each (5 ACCEPT pairs, 6 REJECT pairs),
    two missing-schema rows, and `driver verdict token sets: 12 literals use 9
    schema-defined sets`.
  - A3 (definition, not duplication): with `schemas/section_brief.schema.json`
    deleted from an engine copy the shell rejects with
    `ERROR: cannot load section brief schema at …/section_brief.schema.json`;
    same for `handoff.schema.json` and `validate_handoff`. No accept, no fallback.
  - A3 (comparison is not decorative), PM's own mutations,
    `sections/boundary-schema/probe_mutation_002.zsh`:
    stubbing `validate_handoff` to `return 0` in a copy →
    `FAIL: handoff_missing_unproven.md disagreement: checker=REJECT shell=ACCEPT`,
    exit 1; removing `priority_loss` from the schema's `required` →
    `FAIL: brief_priority_missing_loss.md disagreement: checker=ACCEPT
    shell=REJECT`, exit 1. Both columns can fail, and loosening the schema is
    caught rather than rewarded.
  - A5: `boundary_schema_test.sh`, `pm_flow_test.sh`, `topology_compare_test.sh`,
    `agent_bindings_test.sh` and
    `template/.agentic/pm_flow/tests/verdict_parser.zsh` (`pass=35 fail=0`)
    all exit 0 in the developer worktree.
  - No behaviour change, PM's own A/B (`sections/boundary-schema/probe_no_stricter.zsh`):
    `validate_section_brief`, `extract_section_priority`, `validate_handoff` and
    `handoff_budget_report` extracted from main's `pm_flow.sh` and from the
    worktree's, run over all 22 live section briefs, all 22 live handoffs and the
    nine fixtures — `diff` of the two result sets is empty, including the report
    strings (`It is 527 words; the cap is 500.`,
    `It is 8575 bytes; the cap is 8192.`).
  - Verdict contract byte-identical (`sections/boundary-schema/probe_verdict_contract.zsh`):
    on both engines an accepted verdict gives exit 0 and the two lines
    `GO_WITH_CHANGES` / `GO_WITH_CHANGES rewire the validator first`; a rejected one
    gives exit 1 and `response Decision must begin with one of ['GO',
    'GO_WITH_CHANGES', 'NO_GO'], got 'MAYBE not sure yet'`;
    `extract_markdown_decision_line` returns the same line and the same exit codes.

- T1 — schemas and the stdlib checker. Acceptance A2, A3 (checker side), A5.
  Accepted cycle 001.
  - Delivered: `schemas/{section_brief,handoff,verdict,config}.schema.json`,
    `template/.agentic/pm_flow/export.py` (317 lines, imports only
    `argparse`/`json`/`pathlib`/`re`/`sys`), `tests/boundary_schema_test.sh`,
    ten fixtures under `tests/fixtures/boundary_schema/`.
  - A2: `python3 <flow>/export.py check --kind handoff <fixture>` — valid handoff
    exit 0; `handoff_missing_unproven.md` exit 1 with
    `handoff.What is unproven is required`. Equivalent pairs observed for brief
    (`brief.headings.Scope is required`;
    `brief.acceptance_ids[0] must match pattern '^\`?A[0-9]+\`?\s*[:.—-]'`),
    verdict (`response Decision must begin with one of ['GO', 'GO_WITH_CHANGES',
    'NO_GO'], got 'MAYBE …'`) and config
    (`config.roles.developer.cli must be one of ['claude', 'codex', 'copilot',
    'acp'], got 'unknown'`).
  - A3: `zsh tests/boundary_schema_test.sh` prints all ten fixtures with their
    verdicts (5 ACCEPT / 5 REJECT) and exits 0. Mutation check: with
    `validate_schema` stubbed to `return payload` in a temp copy, the suite fails
    at `brief_missing_scope.md verdict: expected 'REJECT', got 'ACCEPT'` — the
    reject path is genuinely under test.
  - A5: in the developer worktree, `boundary_schema_test.sh`, `pm_flow_test.sh`,
    `topology_compare_test.sh` and `agent_bindings_test.sh` all exit 0. No tracked
    file was modified (`git diff --stat HEAD` empty); the four new paths are the
    only additions.
  - Runtime-loading proved: deleting `schemas/handoff.schema.json` from a copy makes
    `check --kind handoff` exit 1 with `cannot load handoff schema at …`, so the
    schema files are read, not embedded.

## Active decisions

- The checker lives inside `export.py`, not a separate module: the brief's owned
  paths grant the section one Python file plus `schemas/**`, and the export path and
  the tests are the only two callers.
- `schemas/` is the single definition; the shell validators read it rather than
  keeping a parallel list. A schema file that exists but is duplicated by hand in
  `pm_flow.sh` is a rejection condition in the brief, not a shortcut.
- Export field names are stable and never carry a cycle number:
  `sections[] {key, name, status, priority, owned_paths, dependencies,
  acceptance[] {id, state}, handoff {outcome, decisions, interfaces, risks,
  unproven, next_action}}`.
- Acceptance state is derived, not stored: an ID from `brief.md`'s Acceptance
  bullets is `met` when it appears under `state.md`'s completed-evidence heading,
  otherwise `open`. The schema pins that enum so no consumer invents a third value.
- `acp` becomes valid everywhere (fixed by the brief). `topology.py` gets an `acp`
  entry with an empty model list, matching how `copilot` is already left
  unconstrained at `topology.py:14`.
- The export reads the per-section files directly (`status.txt`, `priority.txt`,
  `owned_paths.txt`, `dependency_handoffs.txt`, `brief.md`, `handoff.md`,
  `state.md`), not the generated `sections.md` table, which is a rendered view.

## Blockers

- None observed. `topology_compare_test.sh` was reported failing with
  `sync: cannot find pm_flow.persona_card` by the developer at cycles 001 and 002 and
  did not reproduce either time: run from this review against the developer worktree
  it prints `PASS: topology compare reports literal metrics, limits, personas, and
  copy retention` and exits 0. It is a developer-sandbox artefact. Stop listing it as
  a known exemption in assignments; ask instead for the exact command and cwd, since
  two cycles of "could not do" have both been false.

## Carried into T3 and T4

- `template/.agentic/pm_flow/tests/verdict_parser.zsh` is the in-engine regression
  guard for anything touching the verdict path: it extracts `markdown_verdict_parse`
  and four neighbours by regex (`verdict_parser.zsh:19-33`), sets `SCRIPT_DIR` to the
  engine root (`:18`), and exercises 35 presentation cases. Baseline `pass=35 fail=0`
  at cycle 002. Keep it in the A5 list for every remaining task.
- `validate_section_brief` has a wide blast radius: eleven suites build briefs
  inline (`artifact_quality`, `store_ledger`, `packaged_layout`, `run_detach`,
  `otel_semconv`, `topology_compare`, `codex_usage`, `agent_bindings`,
  `persona_cards`, `trace_commands`, `pm_flow`). It must keep accepting exactly what
  it accepts today; cycle 002's A/B over 53 real artifacts is the baseline to re-run
  if T3 or T4 touches it.
- `pm_flow.sh` has no source guard — line 2019 is a bare `main "$@"` — so any
  harness that calls a validator directly must extract the functions rather than
  source the file as shipped.
- Every engine consumer of a schema now hard-fails when `schemas/` or `export.py` is
  absent, by design. `install.sh`'s `COPIED_ENGINE_FILES` (`install.sh:47-69`) still
  lists neither, and it is `real-install`'s file. Cycle 001's addition was inert in an
  installed layout; cycle 002's rewiring is not. The escalation to `real-install` is
  to add `export.py` and the `schemas/` directory to the copied-engine lists — this
  section must not edit `install.sh`, and the brief scopes acceptance to the checkout,
  so this is a handoff item, not a blocker.
- In zsh, never name a probe variable `path` — it is tied to `PATH` and assigning to
  it blanks the command search path. Cost one wasted probe run this cycle.

## Baseline observed this cycle

- Section directories under `.../pm-agent/sections/` carry `name.txt`, `status.txt`,
  `priority.txt`, `summary.txt`, `owned_paths.txt`, `dependency_handoffs.txt`,
  `run_path.txt`, `updated_at.txt`, `brief.md`, `handoff.md`, `state.md`,
  `workplan.md`. 22 sections exist.
- The three `config.json` consumers confirmed to disagree: `agent_exec.sh:199`
  allows `{claude, codex, copilot, acp}`, `pm_flow.sh:539` allows
  `{claude, codex, copilot}`, `topology.py:14` registers only
  `{claude, codex, copilot}` and `validate_binding` (`topology.py:158`) rejects any
  cli outside that registry.
- `driver.zsh:1227` calls `markdown_verdict_parse` but the function itself lives in
  `pm_flow.sh:929`, so the verdict work needs no edit to another section's file.
- `schemas/`, `export.py`, the suite and the fixtures exist (T1) and the shell
  validators now read them (T2). The export verb does not exist; that is T4.
- After T2 the only heading-shaped literal left in `pm_flow.sh` is
  `extract_assignment_sections`' `WANTED`/`TITLES` list (`:975-977`), which describes
  the assignment prompt, not a boundary artifact, and has no schema. Out of scope
  unless a later brief adds one.
- `refresh_sections_index`'s generated preamble line is now schema-derived and reads
  "…carries only outcome, decisions, interfaces, risks, what is unproven, and next
  action" where it used to read "outcomes … and the next action". Cosmetic; nothing
  in `tests/`, `template/` or `src/` matches on the phrase.
- `verdict.schema.json`'s `x-allowed-token-sets` enumerates nine kinds. Confirmed
  complete against `driver.zsh`: the twelve CSV literals there reduce to exactly
  those nine distinct sets.

## Next eligible task

- T3 — one cli definition across the three `config.json` consumers. Depends only on
  T1. `config.schema.json` becomes the sole place the cli and difficulty enums are
  written; `cmd_config` (`pm_flow.sh:539`), `validate_binding` (`topology.py:158`)
  and the cli guard (`agent_exec.sh:199`) read it, and `acp` validates in all three.
