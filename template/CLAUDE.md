<!-- pm-flow:begin -->
# {{PROJECT_NAME}} Agent Orchestration

This repository uses pm-flow. Agent work is split across three roles, and this
file is loaded by all of them. **Identify your role before acting.** If you were
launched with a role-specific prompt, that prompt governs; do not adopt a role
merely because it is described here.

## Role router

- **Root project coordinator** — you were started from
  `agentic/pm_flow/{{PROJECT_KEY}}/project_state/start.md` (fresh) or
  `resume.md` (continuing). Those files are your instructions.
- **Section PM sub-agent** — you were seeded with a
  `sections/<section>/pm_prompt.md`. That prompt is your complete scope. Own
  that one section; do not coordinate the project or other sections.
- **Developer sub-agent** — you were given a single bounded assignment. Do only
  that assignment and report back to the section PM that launched you.
- **PM reviewer** — you were invoked non-interactively to review a proposed step
  or completion report. Your system prompt governs. Do not create sections, do
  not spawn sub-agents, and do not write code.

If none of the above applies, you are doing ordinary work in this repository.
Do not start the pm-flow orchestration unless asked.

## Repo-wide invariants

`agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md` is the single source of truth
for the flow's rules. These are the few that hold for every role:

- Context crosses role boundaries only through files: `project_state/plan.md`,
  the generated `project_state/sections.md`, and each section's bounded
  `handoff.md`. Never through raw transcripts or inherited conversations.
- Every sub-agent starts with no inherited parent conversation. Developer
  sub-agents are fresh per assignment and are never resumed or reused.
- A section handoff is capped at 500 words and 8192 bytes.
- Do not use automatic context compaction as the continuation mechanism.
  Checkpoint to `state.md` and `handoff.md`, then launch a fresh agent.
- Do not count workflow or documentation work as progress unless it directly
  unlocks the same task cycle.

Command reference lives in `agentic/pm_flow/README.md`.
<!-- pm-flow:end -->