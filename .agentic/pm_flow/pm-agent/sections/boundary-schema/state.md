# boundary-schema section PM state

## Current task

- T2 — the shell validators read their headings and tokens from `schemas/`, and the
  suite compares both sides on every shared fixture.

## Completed tasks and evidence

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

- None observed. Cycle 001's reported `topology_compare_test.sh` failure
  (`sync: cannot find pm_flow.persona_card`) did not reproduce: the suite passes on
  `main` and in the developer worktree when run from this review. Treat it as a
  developer-sandbox artefact, not a section blocker.

## Carried into T2

- `parse_brief` requires the Priority token, `validate_section_brief` does not.
  Probe: a `brief_valid.md` copy with `- critical: …` under Priority gives
  `export.py check --kind brief` exit 1
  (`brief.priority must be one of ['must-have', 'nice-to-have'], got ''`) while
  `validate_section_brief` accepts it. This is not a mismatch invented in T1 —
  `extract_section_priority` (`pm_flow.sh:1188`) rejects the same brief and runs on
  the same path, at `pm_flow.sh:1691`, immediately after `validate_section_brief`
  (`:1688`). T2's comparison must call the pair, not `validate_section_brief` alone,
  or it will read a real agreement as a disagreement.
- The T1 fixtures already agree with today's shell validators on all eight markdown
  fixtures (probed by sourcing `pm_flow.sh` with its trailing `main "$@"` stripped);
  the over-budget handoff reports 527 words on both sides. T2 inherits a consistent
  fixture set.
- `pm_flow.sh` has no source guard — line 2019 is a bare `main "$@"` — so any
  harness T2 writes to call a validator directly must strip or neutralise that line
  rather than sourcing the file as shipped.

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
- `schemas/`, `export.py`, the suite and the fixtures now exist (T1). The export
  verb does not; that is T4.
- `verdict.schema.json`'s `x-allowed-token-sets` enumerates nine kinds. Confirmed
  complete against `driver.zsh`: the twelve CSV literals there reduce to exactly
  those nine distinct sets.

## Next eligible task

- T2 — shell validators derive from the schemas. Depends only on T1, now accepted.
