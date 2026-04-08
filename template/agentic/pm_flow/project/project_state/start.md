# Project start prompt

Use this file as the prompt scaffold for a fresh session on {{PROJECT_NAME}}.

Purpose
- Start work without relying on remembered prompt text.
- Point the agent at the canonical repo-local state and contract files first.
- Keep the opening brief short while still grounding the agent in the installed pm-flow layout.

Read first
1. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/plan.md`
2. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/start.md`
3. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/resume.md`
4. `agentic/pm_flow/{{PROJECT_NAME}}/task_contract.md`
5. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/current_run.txt`

Suggested opening prompt
```text
Start work on {{PROJECT_NAME}} from the repo-local pm-flow state.

Read these first, in order:
1. agentic/pm_flow/{{PROJECT_NAME}}/project_state/plan.md
2. agentic/pm_flow/{{PROJECT_NAME}}/project_state/start.md
3. agentic/pm_flow/{{PROJECT_NAME}}/project_state/resume.md
4. agentic/pm_flow/{{PROJECT_NAME}}/task_contract.md
5. agentic/pm_flow/{{PROJECT_NAME}}/project_state/current_run.txt

Then continue autonomously from the current project state using pm-flow for each real cycle.
Use agentic/pm_flow/{{PROJECT_NAME}}/ as the canonical project workspace.
```

What this file should contain
- The project mission in one or two lines.
- The canonical files that a fresh session must read first.
- Any repo-specific execution rules worth seeing before the first cycle.
- The default expectation for using pm-flow in this repo.

Manual-use note
- This file is guidance for humans and agents to read first.
- It is not executed automatically by `pm_flow.sh`.
