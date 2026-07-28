<!-- pm-flow:begin -->
# {{PROJECT_NAME}} Agent Orchestration

- Use `agentic/pm_flow/{{PROJECT_KEY}}/project_state/start.md` for a fresh root coordinator and `resume.md` for a resumed coordinator.
- The root coordinator owns only project-wide goals, section boundaries, dependencies, and integration.
- The root coordinator reads `project_state/plan.md`, `project_state/sections.md`, and bounded section handoffs. It must not load raw section transcripts or developer conversations.
- Create independently owned sections with `agentic/pm_flow/pm_flow.sh init-section`.
- Spawn one PM sub-agent per ready section with no inherited root conversation, using only `sections/<section>/pm_prompt.md` (`fork_turns="none"` in Codex collaboration).
- A section PM is long-lived only within its section and keeps detail in `sections/<section>/state.md`.
- Every implementation assignment must use a fresh developer sub-agent with no inherited section-PM conversation (`fork_turns="none"` in Codex collaboration). Never resume or reuse a developer conversation.
- Section briefs require the exact Markdown headings `Objective`, `Scope`, `Owned paths`, `Dependencies`, `Acceptance`, and `Rejection conditions`. Dependency bullets are exact section keys or repo-relative section `handoff.md` paths.
- Do not create sections whose owned paths overlap a nonterminal section. Every pending review uses snapshots of the declared dependency handoffs.
- Section PMs report upward only through a `handoff.md` capped at 500 words and 8192 bytes.
- Use `--section <name>` with `prepare-step current`, `prepare-complete current`, `rotate-session current`, and `current-run`.
- Keep only one active pending review per section. Its generated command (and the Codex fallback) claims execution exactly once before calling the PM. If an attempt is abandoned, use `cancel-pending`; cancellation rotates the PM session when execution was already claimed. `rotate-session` refuses active pending work.
- Record a current `DONE` completion review before publishing a `done` handoff. Reopen a `done` or `cancelled` section with an `active` or `planned` handoff before preparing more PM work.
- Every cycle follows `agentic/pm_flow/{{PROJECT_KEY}}/task_contract.md`.
- Claude PM review commands are executed from the top shell through the generated `command.txt` and stable `net_exec.sh` wrapper.
- Do not count workflow or documentation work as success unless it directly unlocks the same task cycle.
<!-- pm-flow:end -->
