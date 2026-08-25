Owner request. Priority: must-have. The role-facing files (brief, workplan,
state, handoff) stay markdown and stay the source of truth — that is settled;
do not migrate state into a database. What is missing is a validated structured
projection at the boundary, so external systems (ticket trackers first: Jira,
GitHub Issues, Plane, Linear) can consume section state without parsing
markdown, and so the flow's own validators stop disagreeing with each other.

Wanted outcomes:

1. A JSON Schema for each boundary artifact: section brief, handoff, and cycle
   verdict/decision record. The existing shape rules in `pm_flow.sh`
   (`validate_section_brief`, `validate_handoff`, the verdict token grammar in
   `markdown_verdict_parse`) become one schema-backed definition each; the shell
   validators keep working but derive from or agree with the schemas.
2. A `pm-flow export --json` command (name at implementer's discretion) that
   emits the current project as validated JSON: sections with key, status,
   priority, owned paths, dependencies, acceptance IDs and their state, plus
   each section's parsed handoff fields (Outcome / Decisions / Interfaces /
   Risks / What is unproven / Next action). Machine-readable, stable field
   names, schema-validated on the way out.
3. One JSON Schema for `config.json`, ending the current three-way disagreement:
   `acp` is an accepted cli in `agent_exec.sh` but rejected by `pm-flow config`
   validation and by `topology.py`'s registry. One definition, all three
   consumers agree, and an ACP binding validates everywhere it runs.

Constraint: stdlib only, like the rest of the engine — a schema checker in the
style of the existing self-contained validator in `trace_export.py` is fine; do
not add a jsonschema dependency. Suggested owned paths: a new
`template/.agentic/pm_flow/schemas/` (or `src/pm_flow/schemas/`), the export
command's file, the validator call sites in `pm_flow.sh`, `topology.py`'s
binding checks, and a new test suite. No dependencies on other sections; the
future ticket-integration section will depend on this one.
