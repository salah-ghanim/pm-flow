<!-- pm-flow:begin -->
# {{PROJECT_NAME}} Agent Orchestration

This repository uses pm-flow. Agent work is split across three roles, and this
file is loaded by all of them. **Identify your role before acting.** If you were
launched with a role-specific prompt, that prompt governs; do not adopt a role
merely because it is described here.

## Role router

- **Product officer** — you cut the product into sections, or you adjudicate
  between consultant proposals when a section has failed. Read
  `project_state/plan.md` and the section registry, never section internals.
- **Section manager** — you were given one section's brief and its history.
  That section is your complete scope; do not coordinate the project or another
  section.
- **Developer** — you were given a single bounded assignment. Do only that
  assignment and report back to the section manager that launched you.
- **Consultant or rescue engineer** — you were brought in because a section
  failed repeatedly. Your task prompt governs and states exactly what is
  expected of you.

If none of the above applies, you are doing ordinary work in this repository.
Do not start the pm-flow orchestration unless asked; `pm_flow.sh run` spends
real model budget.

## Repo-wide invariants

`agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md` is the single source of truth
for the flow's rules. These are the few that hold for every role:

- Context crosses role boundaries only through files: `project_state/plan.md`,
  the generated `project_state/sections.md`, and each section's bounded
  `handoff.md`. Never through raw transcripts or inherited conversations.
- Every role runs as its own process with no inherited conversation. Developers
  are fresh per assignment and are never reused.
- A section handoff is capped at 500 words and 8192 bytes.
- Do not use automatic context compaction as the continuation mechanism.
  Checkpoint to `state.md` and `handoff.md`, then launch a fresh agent.
- Do not count workflow or documentation work as progress unless it directly
  unlocks the same task cycle.
- Commit whenever a section makes real progress. The section manager commits its
  own owned paths plus `state.md` and `handoff.md` after every accepted result;
  the product officer commits plan, registry and brief changes. Uncommitted work
  does not survive the next fresh process.

Command reference lives in `agentic/pm_flow/README.md`. Roles bind to a CLI,
a model, and a difficulty in `agentic/pm_flow/config.json`.
<!-- pm-flow:end -->