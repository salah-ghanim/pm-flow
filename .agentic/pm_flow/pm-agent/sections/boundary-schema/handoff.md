## Outcome
- A1 — `pm-flow export --json` exits 0 in the repo: `export keys=22 dirs=22 identical=True`, `json.tool` parses, two runs byte-identical, nothing written. The `boundary-schema` entry matches its `status.txt`, `priority.txt`, `owned_paths.txt` and all six `handoff.md` fields. `60c11e2`.
- A2 — deleting `## What is unproven` from a live-copy handoff makes export exit 1 with empty stdout and `export.sections[otel-semconv].handoff.What is unproven is required`. `60c11e2`.
- A3 — the suite prints eleven fixtures with two agreeing verdicts each (5 ACCEPT, 6 REJECT pairs) and two missing-schema rows where the shell rejects rather than falls back. `427040b`, extended `60c11e2`.
- A4 — an `acp` seat gives `pm-flow=ACCEPT topology=ACCEPT agent-exec=ACCEPT`; an unknown cli, and a deleted `config.schema.json`, are rejected by all three. `427040b`.
- A5 — `boundary_schema_test.sh`, `pm_flow_test.sh`, `topology_compare_test.sh`, `agent_bindings_test.sh` and `template/.agentic/pm_flow/tests/verdict_parser.zsh` (35/0) exit 0 at `50ec3b2`.

## Decisions
- `schemas/*.json` is the single definition; consumers read it at call time and hard-fail (`cannot load … schema at …`) rather than falling back. A hand-kept duplicate is a regression.
- cli legality is a schema question (`config.schema.json:10`, `$defs.seat`); `FALLBACK_MODELS` and the store's `clis` table constrain models only, read as `registry.get(cli, [])`.
- Acceptance state is derived, never stored: an ID is `met` when its bare token appears in `state.md` outside `Blockers` and `Next eligible task`.
- The export reads the per-section files, not the generated `sections.md`.

## Interfaces
- `template/.agentic/pm_flow/schemas/{section_brief,handoff,verdict,config,project_export}.schema.json`.
- `pm-flow export --json` → `{project, sections[]}`; each section carries `key, name, status, priority, owned_paths, dependencies, acceptance[{id,state}], handoff{outcome,decisions,interfaces,risks,unproven,next_action}, summary, updated_at`.
- `export.py check --kind {brief|handoff|verdict|config|export} <path>` — 0 accept, nonzero naming the field.
- To export a copy, copy `.agentic/pm_flow` whole and set `PM_FLOW_FLOW_DIR`; the key comes from `<flow>/.project-key`.

## Risks
- Five sections export `acceptance: []` — `agents-md`, `green-suite`, `installer`, `packaging`, `worktree-isolation` — their legacy briefs carry no `A<n>` token. A consumer reading empty as "nothing met" misreads them; their owners must add IDs.
- Schema edits ripple: eleven suites build briefs inline. Re-run cycle 002's A/B over the 53 live artifacts before changing what a validator accepts.
- New engine files need registering in `install.sh` (`real-install` owns it); `export.py` and `schemas` are already listed.

## What is unproven
- The heading-independent acceptance rule is proven by the `freeform` fixture and a PM mutation, not by live data: no live section both uses free-form headings and carries `A<n>` IDs. Adding an ID to one such brief and re-exporting settles it.
- No external system has consumed the export; only `json.tool` and the checker have read it. The ticket-integration section parsing it settles fit.
- The developer's `sync: cannot find pm_flow.persona_card` never reproduced in four cycles, including under the full dispatch env; the exact command, cwd and output would settle it.

## Next action
- None; the section is closed. Ticket-integration can start against the interfaces above without waiting on anything here.
