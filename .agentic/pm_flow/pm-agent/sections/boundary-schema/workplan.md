# boundary-schema workplan

## Design summary

- One definition per boundary artifact lives in `template/.agentic/pm_flow/schemas/*.json`.
  Everything else reads those files: the stdlib checker, the shell validators, the
  three `config.json` consumers, and the export command. No consumer keeps its own
  copy of a heading list or a cli enum.
- The checker is a stdlib module, `template/.agentic/pm_flow/export.py`, written in
  the shape of `validate_otlp_json` (`trace_export.py:163`): walk the payload, raise
  `ValueError` naming the offending field, no `jsonschema` import. `export.py` is both
  the checker entry point (`check` subcommand) and the export path (`emit`), because
  the brief's owned paths give the section exactly one Python file.
- Markdown stays the source of truth. `export.py` carries the markdown -> JSON
  parsers (brief, handoff, verdict) so that one artifact can be fed to both the
  shell validator and the checker and their accept/reject compared. That comparison
  is the section's real deliverable; the schema files alone are not.
- The shell validators keep their call signatures and their `fail` behaviour. What
  changes is where their required headings and legal tokens come from: the schema
  file, read once per call, instead of a literal list in the function body.
- Section facts already exist as per-section files (`status.txt`, `priority.txt`,
  `owned_paths.txt`, `dependency_handoffs.txt`, `handoff.md`, `brief.md`, `state.md`)
  and `refresh_sections_index` (`pm_flow.sh:627`) already reads most of them. The
  export reads the same files; it does not parse the generated `sections.md` table.

## Interfaces and data changes

- New: `template/.agentic/pm_flow/schemas/section_brief.schema.json`,
  `handoff.schema.json`, `verdict.schema.json`, `config.schema.json`,
  `project_export.schema.json`.
- New: `template/.agentic/pm_flow/export.py` with two subcommands —
  `check --kind {brief|handoff|verdict|config|export} <path>` (exit 0 accept,
  nonzero with the offending field named) and `emit --json` (project projection on
  stdout).
- New verb: `pm-flow export --json`, dispatched in `pm_flow.sh`'s `main` case block
  (`pm_flow.sh:1916-2015`) and listed in `usage()` (`pm_flow.sh:35`).
- Changed, without changing what they accept apart from `acp`:
  `validate_section_brief` (`pm_flow.sh:1149`), `validate_handoff` (`pm_flow.sh:1452`),
  `markdown_verdict_parse` (`pm_flow.sh:929`), `cmd_config`'s binding check
  (`pm_flow.sh:539`), `topology.py`'s `validate_binding` (`topology.py:158`) and
  `FALLBACK_MODELS` (`topology.py:14`), `agent_exec.sh`'s cli guard (`agent_exec.sh:199`).
- Export field names are stable and cycle-free: `sections[]` with
  `key`, `name`, `status`, `priority`, `owned_paths`, `dependencies`,
  `acceptance[] {id, state}`, `handoff {outcome, decisions, interfaces, risks,
  unproven, next_action}`.

## Task T1 — Schemas and the stdlib checker

- Status: done (cycle 001, GO)
- Outcome: `schemas/` holds the four artifact schemas and `export.py check` accepts a
  valid brief, handoff, verdict and config and rejects a corrupted one by naming the
  field. `tests/boundary_schema_test.sh` exists and proves both directions.
- Paths: `template/.agentic/pm_flow/schemas/section_brief.schema.json`,
  `handoff.schema.json`, `verdict.schema.json`, `config.schema.json`;
  `template/.agentic/pm_flow/export.py`; `tests/boundary_schema_test.sh`;
  `tests/fixtures/boundary_schema/**`.
- Reuse: `validate_otlp_json` (`trace_export.py:163`) for the checker shape;
  the heading lists in `validate_section_brief`/`validate_handoff` and the token
  grammar in `markdown_verdict_parse` as the content the schemas must state; the
  header block of `tests/topology_compare_test.sh` for suite conventions.
- Acceptance IDs: A2, A3 (checker side), A5.
- Validation: `zsh tests/boundary_schema_test.sh` exits 0; a corrupted handoff
  fixture makes `python3 export.py check --kind handoff <path>` exit nonzero with
  the offending heading in the message.
- Depends on: None.

## Task T2 — Shell validators derive from the schemas

- Status: done (cycle 002, GO)
- Outcome: `validate_section_brief`, `validate_handoff` and `markdown_verdict_parse`
  read their required headings and legal tokens from `schemas/`, and the suite feeds
  every shared fixture to both the shell validator and `export.py check`, failing if
  the two disagree on any fixture.
- Paths: `template/.agentic/pm_flow/pm_flow.sh`,
  `template/.agentic/pm_flow/export.py`,
  `template/.agentic/pm_flow/schemas/**`, `tests/boundary_schema_test.sh`,
  `tests/fixtures/boundary_schema/**`.
- Reuse: the T1 schemas and parsers; `assert_matches` (`pm_flow.sh:911`) and `fail`
  as the existing rejection path; the function-extraction harness in
  `template/.agentic/pm_flow/tests/verdict_parser.zsh:19-33`, which already calls the
  shell validators without running `main`.
- Acceptance IDs: A3, A5.
- Validation: `zsh tests/boundary_schema_test.sh` exits 0 and its output names each
  fixture with both verdicts; `zsh tests/pm_flow_test.sh` and
  `zsh template/.agentic/pm_flow/tests/verdict_parser.zsh` exit 0.
- Depends on: T1.
- Shell comparison is against the *pair* `validate_section_brief` +
  `extract_section_priority` for briefs, because both real call sites
  (`pm_flow.sh:1688`/`:1691`, `driver.zsh:3593`/`:3600`) run them together and the
  priority contract lives in the second.
- One real disagreement to close, observed this cycle: a brief whose Priority bullet
  is `- must-have` with no loss text is accepted by `export.py check --kind brief`
  and rejected by `extract_section_priority`. The schema is the definition, so it
  states the loss requirement and the checker enforces it; the shell keeps its
  message. Closed in cycle 002: `parse_brief` now returns `priority_loss` and
  `section_brief.schema.json` requires it with `"pattern": "\\S"`, so both sides
  reject `brief_priority_missing_loss.md`.

## Task T3 — One cli definition across the three config consumers

- Status: done (cycle 003, GO)
- Outcome: `config.schema.json` is the only place the cli and difficulty enums are
  written. A role bound to cli `acp` passes `pm-flow config`, `topology.py`'s binding
  check and `agent_exec.sh`'s guard; a cli outside the enum fails all three with a
  message naming the cli.
- Paths: `template/.agentic/pm_flow/schemas/config.schema.json`,
  `template/.agentic/pm_flow/pm_flow.sh`, `template/.agentic/pm_flow/topology.py`,
  `template/.agentic/pm_flow/agent_exec.sh`, `tests/boundary_schema_test.sh`,
  `tests/fixtures/boundary_schema/**`.
- Reuse: the existing guards at `pm_flow.sh:539`, `topology.py:158`,
  `agent_exec.sh:199`; `copilot`'s empty `FALLBACK_MODELS` entry as the precedent for
  a cli with an unconstrained model list; the schema-reading inline python blocks
  already in `pm_flow.sh` (`:1092-1119`, `:1424-1449`) for the load-or-fail shape.
- Acceptance IDs: A4, A5.
- Validation: `zsh tests/boundary_schema_test.sh` exits 0; `zsh tests/topology_compare_test.sh`
  and `zsh tests/agent_bindings_test.sh` exit 0.
- Depends on: T1.
- Two facts observed at cycle 003 scoping that change what this task must do:
  1. `config.schema.json` writes the cli and difficulty enums **twice** — once in the
     single-binding arm (`:29`) and once in the panel arm (`:41`). "One definition"
     is not reached by pointing three consumers at a file that contradicts itself
     twice over; the seat shape has to be hoisted into `$defs` and referenced, which
     means `validate_schema` needs minimal `$ref` support.
  2. `topology.py` conflates two different questions in `cli not in registry`
     (`:193`). `model_registry` prefers the store's `clis` table over
     `FALLBACK_MODELS` (`:83`), and that table is seeded by `catalog.py:227`, which
     is owned by `persona-packs` and lists no `acp`. Adding `acp` to
     `FALLBACK_MODELS` alone therefore leaves an `acp` seat rejected on any flow with
     a store — including this one. Legality of a cli comes from the schema enum;
     the registry only constrains models, looked up with `registry.get(cli, [])`.

## Task T4 — `pm-flow export --json`, the end-to-end scenario

- Status: done (cycle 004, GO)
- Delivered: `schemas/project_export.schema.json` (handoff node is
  `{"$ref": "handoff.schema.json#"}`, priority is
  `{"$ref": "section_brief.schema.json#/properties/priority"}`, `acceptance[].state`
  is the two-value enum), `export.py`'s `emit` subcommand and external-`$ref`
  resolver, the `export)` arm at `pm_flow.sh:2031` and its `usage()` line at `:48`,
  and eight new suite cases with four fixture sections.
- Outcome: in a flow directory, `pm-flow export --json` exits 0 and prints JSON
  covering every section directory, validated against `project_export.schema.json`
  before it reaches stdout; a section with a corrupt handoff makes the command exit
  nonzero naming the field rather than emitting invalid JSON.
- Paths: `template/.agentic/pm_flow/export.py`,
  `template/.agentic/pm_flow/schemas/project_export.schema.json`,
  `template/.agentic/pm_flow/pm_flow.sh`, `tests/boundary_schema_test.sh`,
  `tests/fixtures/boundary_schema/**`.
- Reuse: `refresh_sections_index`'s `first_line` reader (`pm_flow.sh:668`) for the
  per-section text files; T1's `parse_brief`/`parse_handoff` and `validate_schema`;
  the `main` case block (`pm_flow.sh:1983-2084`) and `usage()` heredoc
  (`pm_flow.sh:35`); the suite's engine-copy-as-flow-directory harness
  (`boundary_schema_test.sh:42-56`).
- Acceptance IDs: A1, A2, A5.
- Validation: `pm-flow export --json | python3 -m json.tool` parses, and the
  `otel-semconv` entry's status and priority match its `status.txt`/`priority.txt`
  and its handoff fields match `handoff.md`; `zsh tests/boundary_schema_test.sh` exits 0.
- Depends on: T1, T2, T3.
- Facts observed at cycle 004 scoping (`probe_export_004.zsh`) that fix what this
  task must do:
  1. The live project is exportable today. All 22 sections pass both
     `export.py check --kind brief` and `--kind handoff`, and all eight per-section
     text files exist in all 22 directories. So A1's "exits 0 on the pm-agent
     project" is reachable without touching any markdown; if the emit path fails on
     a live section, that is a defect in the emit path, not in the data.
  2. `parse_brief`'s `acceptance_ids` are whole bullet lines, not identifiers —
     `"A1: On a run recorded after this change, an OTLP receiver independent of"`.
     The export's `acceptance[].id` must be the bare token (`A1`), extracted with the
     same `^`?A[0-9]+`?` prefix the schema pattern already pins
     (`section_brief.schema.json:81`), so the two cannot drift.
  3. `state.md` heading names are not a contract. `## Completed tasks and evidence`
     exists in 18 of 22 sections; `agents-md`, `green-suite`, `installer` and
     `worktree-isolation` use free-form headings instead. A derivation keyed on that
     one heading reports every ID `open` for four sections, three of which are
     `done`. The rule must therefore be heading-name-independent in the positive
     direction and use headings only to exclude: an ID is `met` when its bare token
     appears in `state.md` outside the `Blockers` and `Next eligible task` sections,
     `open` otherwise.
  4. `priority.txt` is multi-line — line 1 is the token, the rest is the loss text.
     Read the first line only, as `first_line` does.
- Carried from the cycle-003 review: `validate_schema`'s `$ref` resolver swallows an
  unresolvable pointer inside a `oneOf` arm when another arm matches. Harmless while
  both arms of `config.schema.json` share one `$ref`; it becomes real the moment
  `project_export.schema.json` gives two arms different pointers. Resolve pointers
  before the arms are tried, or let the unresolvable-pointer error escape the arm
  loop rather than joining the collected messages.
  Closed in cycle 004: `SchemaReferenceError` is re-raised out of the `oneOf` arm
  loop (`export.py:141-142`). PM probe: a schema whose arm 0 matches and whose arm 1
  holds `#/$defs/typo-that-does-not-exist` now raises
  `unresolvable schema pointer '#/$defs/typo-that-does-not-exist'` instead of
  accepting, and a missing referenced *file* raises `cannot load referenced schema
  at …` — while `{"$ref": "handoff.schema.json#"}` still resolves.

## Risks and rollback

- Rewiring three long-lived validators can quietly loosen them. The suite must
  assert rejection, not only acceptance, for every heading a validator used to
  require; a fixture that passes both sides for the wrong reason is the failure mode.
- A schema read on every validator call adds a file dependency to a hot path. If
  `schemas/` is missing the validator must fail loudly, never fall back to accepting.
- Rollback per task is a single-file revert: schemas and `export.py` are new, and the
  validator edits are confined to the named functions.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T4 | `pm-flow export --json` output compared field by field against one section's markdown |
| A2 | T1, T4 | corrupt fixture -> nonzero exit naming the field, from both `check` and `emit` |
| A3 | T1, T2 | suite output showing identical accept/reject from shell validator and checker on every shared fixture |
| A4 | T3 | an `acp` binding passing all three consumers; an unknown cli failing all three |
| A5 | T1-T4 | `boundary_schema_test.sh`, `pm_flow_test.sh`, `topology_compare_test.sh`, `agent_bindings_test.sh` all exit 0 |
