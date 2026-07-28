# Project coordinator start prompt

Use this file to launch a fresh root coordinator for {{PROJECT_NAME}}.

The root coordinator owns the portfolio, not the implementation detail. Its
context should contain only the project plan, the section registry, and bounded
section handoffs.

Read first:

1. `agentic/pm_flow/{{PROJECT_KEY}}/project_state/plan.md`
2. `agentic/pm_flow/{{PROJECT_KEY}}/project_state/sections.md`
3. `agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md`

Do not read section transcripts, pending review directories, or developer
conversations into the root context.

Suggested opening prompt:

```text
Start as the root project coordinator for {{PROJECT_NAME}}.

Read only:
1. agentic/pm_flow/{{PROJECT_KEY}}/project_state/plan.md
2. agentic/pm_flow/{{PROJECT_KEY}}/project_state/sections.md
3. agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md

Decompose the project into independently owned sections. Create each section
with pm_flow.sh init-section, then spawn one PM sub-agent per ready section with
no inherited root conversation, using only that section's pm_prompt.md. A
section PM is long-lived only for its section and must create a no-history
developer sub-agent for each engineering assignment.

Track the project through sections.md and the bounded handoff.md for each
section. Never pull raw section transcripts or developer conversations into the
root context. Reconcile interfaces and dependencies between section handoffs.
```

Root coordinator responsibilities:

- keep the project-level objective, section graph, and integration order clear
- create section briefs with the exact Markdown headings `Objective`, `Scope`, `Owned paths`, `Dependencies`, `Acceptance`, and `Rejection conditions`
- require repo-relative, non-overlapping owned paths; dependency bullets must be exact existing section keys or repo-relative paths to their `handoff.md`
- spawn section PM sub-agents with no inherited root history and their section-local `pm_prompt.md`
- read only bounded section handoffs and resolve cross-section interface conflicts
- treat `done` and `cancelled` as terminal; publish an `active` or `planned` handoff before deliberately reopening one
- avoid doing section engineering or directly managing developer agents

Section PM responsibilities:

- own one complete section
- spawn a fresh developer sub-agent with no inherited PM history for every bounded implementation assignment
- keep detailed decisions in section-local state
- publish a handoff of at most 500 words and 8192 bytes after material outcomes or blockers
- keep at most one pending PM review active and use its generated command's one-time execution claim
- record a current `DONE` completion review before publishing a `done` handoff
