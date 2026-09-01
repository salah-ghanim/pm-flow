## Assessment

The request asks for a validated JSON projection at the flow's boundary: JSON Schemas for brief, handoff, and verdict record; one export command emitting the project as schema-validated JSON; and one schema for `config.json` that ends the `acp` disagreement. It serves two plan completion criteria directly: "Section state - brief, acceptance, handoff - is exportable as validated JSON in one command … and one schema settles what the flow's own validators accept" is this request almost verbatim, and the ticket-tracker criterion ("A section is visible in an external ticket tracker …") needs this projection to exist first — the owner names that future section as a dependent.

Probes run, all against the checkout on `main`:

- `grep -n "validate_section_brief\|validate_handoff\|markdown_verdict_parse" template/.agentic/pm_flow/pm_flow.sh` — the three shape validators exist as shell/inline-python at `pm_flow.sh:1149`, `:1452`, `:929`. No schema backs any of them.
- `grep` over `pm_flow.sh`'s dispatch — subcommands include `trace export` (OTLP spans only) and `list-sections` (regenerates the markdown index). No JSON project export exists; `src/pm_flow/cli.py` passes unknown verbs straight through to `pm_flow.sh`, so no CLI-side change is needed.
- The three-way `acp` disagreement is real and located: `agent_exec.sh:199` accepts `{"claude","codex","copilot","acp"}` and has a full `acp)` execution arm at `:669`; `pm_flow.sh:539` rejects anything outside `{"claude","codex","copilot"}`; `topology.py`'s registry (lines 15–23) lists claude/codex/copilot only.
- `trace_export.py:163` has `validate_otlp_json` — the self-contained stdlib validator style the owner cites as precedent exists.
- No `schemas/` directory exists in `template/.agentic/pm_flow/` or `src/pm_flow/`. No live or cancelled section covers this: `outcome-record` owns telemetry/semconv paths, `real-install` owns installer paths; neither claims `pm_flow.sh`, `topology.py`, `agent_exec.sh`, or a schemas directory.

One interface risk found and handled below: new engine files must appear in `install.sh`'s copied-engine lists or the packaged layout leaves them behind (the exact failure mode `packaged_layout_test.sh` shows today), and `install.sh` is owned by `real-install`. Acceptance is scoped to the checkout so this is a hand-over constraint, not a dependency.

## Section: boundary-schema

### Objective
- One sentence: section state and `config.json` have schema-backed definitions, and one command emits the project as JSON validated against them, so external systems consume the flow without parsing markdown.

### Current baseline
- Shape rules live only as shell/inline-python: `validate_section_brief` (`template/.agentic/pm_flow/pm_flow.sh:1149`), `validate_handoff` (`:1452`), the verdict token grammar in `markdown_verdict_parse` (`:929`).
- Three consumers disagree on `config.json`: `agent_exec.sh:199` accepts `acp`, `pm_flow.sh:539` rejects it, `topology.py`'s registry omits it.
- `validate_otlp_json` in `template/.agentic/pm_flow/trace_export.py:163` is the stdlib self-contained validator pattern to follow.
- No `schemas/` directory and no JSON export verb exist; `pm-flow` (via `src/pm_flow/cli.py`) forwards unknown subcommands to `pm_flow.sh`, so a new verb needs only a dispatch arm there.

### Deliverables
- JSON Schema files for the boundary artifacts — section brief, handoff, cycle verdict/decision record, and `config.json` — under `template/.agentic/pm_flow/schemas/`.
- A stdlib schema checker (no `jsonschema` dependency) usable by the export path and by tests.
- A `pm-flow export --json`-style subcommand (verb at manager's discretion, registered in `pm_flow.sh`'s dispatch and usage) that emits the current project — sections with key, status, priority, owned paths, dependencies, acceptance IDs and their state, plus each section's parsed handoff fields — validated on the way out.
- `pm_flow.sh`'s brief/handoff/verdict validators and `topology.py`'s and `agent_exec.sh`'s cli checks derive from or provably agree with the schemas; an `acp` binding validates in all three.
- A test suite `tests/boundary_schema_test.sh` with fixtures proving schema/validator agreement on both valid and invalid inputs.

### User-visible scenarios
1. In a flow directory with sections, run `pm-flow export --json` (or the chosen verb): valid JSON arrives on stdout; picking any section key from `project_state/sections.md`, its status, priority, and handoff fields (Outcome, Decisions, Interfaces, Risks, What is unproven, Next action) appear under stable field names matching the markdown.
2. Pipe the output to `python3 -m json.tool`: it parses; re-running the command yields the same shape (stable field names).
3. Edit `config.json` to bind a role to cli `acp` and run `pm-flow config`: it validates; the same config passes `topology.py`'s binding check and `agent_exec.sh`'s guard instead of being rejected by one and accepted by another.
4. Corrupt a fixture handoff (e.g. an illegal status token) and run the export or checker against it: nonzero exit with a message naming the offending field, and the shell validator rejects the same fixture.
5. Run `zsh tests/boundary_schema_test.sh`: exits 0 on `main`.

### Interfaces produced
- `template/.agentic/pm_flow/schemas/*.json` — the boundary schemas the future ticket-integration section will consume.
- The export subcommand and its JSON output shape (stable field names).
- The stdlib schema-checker entry point.

### Interfaces consumed
- `project_state/` markdown files (brief, handoff, sections index, verdict records) as the source of truth — read, never restructured.
- `config.json` as shipped in the template.
- The existing validator call sites in `pm_flow.sh` it must stay compatible with.

### Scope
- In: schema definitions, the checker, the export command, aligning the three `config.json` consumers, the new test suite and fixtures.
- Out: any change to the markdown formats themselves; migrating state to SQLite; `install.sh` registration of the new files (owned by `real-install`); any ticket-tracker integration; editing the shipped `config.json` defaults.

### Non-goals
- The ticket-tracker section (GitHub Issues first) — it depends on this; do not start it here.
- An import direction (JSON back into markdown).
- Schemas for non-boundary artifacts (workplans, transcripts, store rows, OTLP payloads — the last already has `validate_otlp_json`).
- Loosening or tightening what the validators accept beyond making the three `config.json` consumers agree; existing green suites must stay green.

### Priority
- must-have: the plan's completion criterion "section state is exportable as validated JSON in one command, and one schema settles what the flow's own validators accept" cannot be met without it, and the ticket-tracker criterion is blocked until it exists.

### Owned paths
- template/.agentic/pm_flow/schemas/**
- template/.agentic/pm_flow/export.py
- template/.agentic/pm_flow/pm_flow.sh
- template/.agentic/pm_flow/topology.py
- template/.agentic/pm_flow/agent_exec.sh
- tests/boundary_schema_test.sh
- tests/fixtures/boundary_schema/**

### Dependencies
- None.

### Constraints and fixed decisions
- Markdown stays the source of truth; the JSON is a projection. Do not migrate state into a database (owner decision and plan's out-of-scope list).
- Stdlib only — no `jsonschema` or any new dependency; follow the `validate_otlp_json` pattern in `trace_export.py`.
- `install.sh` is owned by `real-install`: do not edit it. Hand the list of new engine files (`schemas/`, `export.py`) to the owner for registration in its copied-engine lists; acceptance here is checked against the checkout, not an installed layout.
- Do not touch `src/pm_flow/semconv.py`, `telemetry.py`, or `driver.zsh` (`outcome-record` owns them); `src/pm_flow/cli.py` needs no change — it forwards unknown verbs to `pm_flow.sh`.
- The `acp` resolution direction is fixed: `acp` becomes valid everywhere (it has a working execution arm in `agent_exec.sh` and the plan guarantees ACP binding); do not resolve the disagreement by removing it.

### Acceptance
- A1: `pm-flow export --json` (or the registered verb) on the pm-agent project exits 0 and emits JSON containing every section listed in `project_state/sections.md` with key, status, priority, owned paths, dependencies, acceptance IDs, and parsed handoff fields — checked by running the command and comparing one known section (e.g. `otel-semconv`) against its markdown, per scenario 1.
- A2: the emitted JSON is validated against the shipped schemas on the way out: a fixture with an illegal field fails export/checking with nonzero exit naming the field — checked by scenario 4 and the suite.
- A3: schema/validator agreement is proven, not asserted: the suite feeds shared valid and invalid fixtures to both the shell validators (`validate_section_brief`, `validate_handoff`, `markdown_verdict_parse`) and the schema checker and requires identical accept/reject on every fixture.
- A4: a `config.json` binding a role to cli `acp` passes `pm-flow config`, `topology.py`'s binding check, and `agent_exec.sh`'s guard; a cli outside the shared definition fails all three — checked per scenario 3.
- A5: `zsh tests/boundary_schema_test.sh` exits 0 on `main`, and the previously green suites touching changed files (`pm_flow_test.sh`, `topology_compare_test.sh`, `agent_bindings_test.sh`) still exit 0.

### Rejection conditions
- The schemas exist but the shell validators are hand-kept duplicates with no test forcing agreement — the "one definition" outcome is the point, not the files.
- Export output that requires reading the markdown to interpret (unparsed blobs for handoff fields, unstable or cycle-numbered field names).
- Any per-dispatch write into the host repository, a new runtime dependency, or an edit to `install.sh` or another section's owned paths.
- Green tests achieved by weakening what a validator rejects rather than by aligning definitions.

### Open questions
- None.

## Decision

CUT — the request is a plan completion criterion nearly verbatim ("exportable as validated JSON in one command … one schema settles what the flow's own validators accept"), nothing on `main` provides it (no schemas directory, no JSON export verb, and a confirmed three-way `acp` disagreement at `agent_exec.sh:199` / `pm_flow.sh:539` / `topology.py`), and its paths are claimable without touching either live section.
