<!-- pm-flow:begin -->
# {{PROJECT_NAME}} Agent Orchestration

@AGENTS.md

`AGENTS.md` is this repository's instructions file. It holds the role router and
the repo-wide invariants in full, and the import above pulls them in here, so a
tool that only knows to read `CLAUDE.md` still gets all of them. This file keeps
no copy of its own: two copies of the same rules drift, and the one an agent
happens to load is then a coin toss.

**Identify your role before acting.** If you were launched with a role-specific
prompt, that prompt governs; the router in `AGENTS.md` says what each role is.

The flow's own rules live in
`.agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md`.
<!-- pm-flow:end -->
