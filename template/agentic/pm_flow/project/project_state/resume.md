# Project coordinator resume prompt

Use this file when a fresh root coordinator resumes {{PROJECT_NAME}}. Resuming
means reconstructing the portfolio from durable handoffs, not restoring one
ever-growing PM conversation.

Read first:

1. `agentic/pm_flow/{{PROJECT_KEY}}/project_state/plan.md`
2. `agentic/pm_flow/{{PROJECT_KEY}}/project_state/sections.md`
3. The linked handoffs needed for active/blocked work and unresolved integration from done sections
4. `agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md`

Do not read:

- section transcripts
- pending PM review directories
- developer conversation history
- a completed section's detailed state unless its handoff exposes an unresolved interface

Suggested resume prompt:

```text
Resume as a fresh root coordinator for {{PROJECT_NAME}} from durable pm-flow
state. Do not reconstruct or continue a monolithic PM conversation.

Read the project plan, sections.md, the bounded handoffs for active or blocked
sections, and any done-section handoffs needed for unresolved dependencies or
integration. Do not eagerly load irrelevant completed handoffs. Reconcile
dependencies at the handoff level.
For each ready section, spawn a section PM sub-agent with no inherited root
conversation using only its pm_prompt.md. In Codex collaboration, use
fork_turns="none". Each section PM may be long-lived within that section, but
every developer assignment must use a fresh no-history developer sub-agent.
Treat done and cancelled sections as terminal. If new project-level evidence
requires more work, reopen the section explicitly with an active or planned
bounded handoff before its PM prepares another review.

Keep raw section transcripts and developer conversations out of the root
context.
```

If a section PM itself must be restarted, launch a fresh section PM from that
section's `pm_prompt.md` with no inherited conversation. That prompt points it
to `state.md` and `handoff.md`. This is an explicit checkpoint boundary; do not
rely on automatic context compaction.

Each section PM must keep only one pending review active. It should run the
generated one-time execution claim, cancel abandoned pending work explicitly,
and publish `done` only after recording a current `DONE` completion review.
