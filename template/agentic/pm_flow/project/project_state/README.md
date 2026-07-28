# Project coordinator state

This directory is the stable, bounded continuation layer for the root
coordinator of {{PROJECT_NAME}}.

The root coordinator reads:

- `plan.md` for the project mission, section graph, and integration order
- `sections.md` for status and one-line summaries
- the linked section `handoff.md` files when their details are needed
- `start.md` or `resume.md` as launch scaffolding

The root coordinator does not read:

- `runs/*/transcript.md`
- pending PM review directories
- section-local `state.md` by default
- developer conversation history

Per-section state lives under `../sections/<section>/`:

- `brief.md` defines the boundary and acceptance criteria
- `pm_prompt.md` launches the section PM sub-agent
- `state.md` contains detailed section-local decisions and progress
- `handoff.md` is the 500-word and 8192-byte interface back to the root coordinator
- `run_path.txt` points to the section's isolated PM run and session

`sections.md` is a derived portfolio index. Run
`./agentic/pm_flow/pm_flow.sh list-sections` to refresh it from authoritative
per-section files.

Section briefs use the exact headings `Objective`, `Scope`, `Owned paths`,
`Dependencies`, `Acceptance`, and `Rejection conditions`. New sections cannot
overlap the owned paths of nonterminal sections. Declared dependencies are
exact section keys or repo-relative section `handoff.md` paths and are
snapshotted for each pending PM review.

`agentic/pm_flow/.project-key` identifies this project workspace even if the
repository directory is renamed.

The legacy `current_run.txt` remains for old non-section runs. New work should
select a section explicitly with `--section <name>` so independent sections do
not contend for a single project-global pointer.
