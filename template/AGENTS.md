<!-- pm-flow:begin -->
# {{PROJECT_NAME}} Agent Orchestration

This repository uses pm-flow. `AGENTS.md` is the instructions file every agent
reads, whatever tool it runs under; nothing here is named after a vendor,
because the roles below are named and the vendors are not. Agent work is split
across those roles and this file is loaded by all of them. **Identify your role
before acting.** If you were launched with a role-specific prompt, that prompt
governs; do not adopt a role merely because it is described here.

## Role router

- **Product officer** — you cut the product into sections, or you adjudicate
  between consultant proposals when a section has failed. Read
  `project_state/plan.md` and the section registry, never section internals.
- **Section manager** — you were given one section's brief, workplan, state, and
  bounded recent evidence.
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

`.agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md` is the single source of truth
for the flow's rules. These are the few that hold for every role:

- Context crosses role boundaries only through files: `project_state/plan.md`,
  the generated `project_state/sections.md`, and each section's bounded
  `handoff.md`. Never through raw transcripts or inherited conversations.
- Inside a section, `brief.md` is the outcome contract, `workplan.md` maps that
  contract to ordered task IDs, and `state.md` records current evidence. One
  cycle assignment selects one workplan task.
- Every role runs as its own process with no inherited conversation. Developers
  are fresh per assignment and are never reused.
- A section handoff is capped at 500 words and 8192 bytes.
- Do not use automatic context compaction as the continuation mechanism.
  Checkpoint to `state.md` and `handoff.md`, then launch a fresh agent.
- Do not count workflow or documentation work as progress unless it directly
  unlocks the same task cycle.
- The driver commits an accepted result, not the role. A `GO` or
  `GO_WITH_CHANGES` commits the section's worktree, merges it back, and commits
  `state.md` and `handoff.md` with it; a `NO_GO` commits nothing and leaves the
  work on the section's branch for the next cycle. No role is asked to commit as
  a condition of acceptance, and no role may reject work because it could not
  record one: a linked worktree keeps its object store in the parent repository,
  outside the directory a dispatch is scoped to, so committing from inside one
  means writing where the sandbox refuses however the permissions are written.
  The product officer still commits plan, registry and brief changes, which it
  makes in the main tree. Uncommitted work does not survive the next fresh
  process, which is why the driver does it rather than asking you to.

## Commit messages

Conventional Commits, so a release can be cut from the log:
`type(scope): subject`, types `feat` `fix` `docs` `refactor` `perf` `test`
`build` `ci` `chore`.
Only `feat` and `fix` are user-visible. A breaking change takes `!` before the
colon and a `BREAKING CHANGE:` footer.

Keep them short: a subject under 72 characters, then at most a few bullets
saying what changed and why. Reasoning belongs in the code, the section record
or the handoff, not in a commit body nobody reads twice.

Command reference lives in `.agentic/pm_flow/README.md`. Roles bind to a CLI,
a model, and a difficulty in `.agentic/pm_flow/config.json`.
<!-- pm-flow:end -->
