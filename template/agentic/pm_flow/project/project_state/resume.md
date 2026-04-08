# Project resume prompt

Use this file as the prompt scaffold when resuming {{PROJECT_NAME}} after prior work already exists.

Purpose
- Resume from the canonical repo-local state instead of machine-local session files.
- Point the agent at the current run, current plan, and project trackers.
- Reduce drift between sessions by keeping the resume prompt close to the project state itself.

Read first
1. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/plan.md`
2. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/current_run.txt`
3. `agentic/pm_flow/{{PROJECT_NAME}}/project_state/resume.md`
4. `agentic/pm_flow/{{PROJECT_NAME}}/task_contract.md`
5. The run directory referenced by `current_run.txt`

Suggested opening prompt
```text
Resume work on {{PROJECT_NAME}} from the current repo-local pm-flow state. This is a continuation, not a fresh start.

Read these first, in order:
1. agentic/pm_flow/{{PROJECT_NAME}}/project_state/plan.md
2. agentic/pm_flow/{{PROJECT_NAME}}/project_state/current_run.txt
3. agentic/pm_flow/{{PROJECT_NAME}}/project_state/resume.md
4. agentic/pm_flow/{{PROJECT_NAME}}/task_contract.md
5. the run directory referenced by current_run.txt

Then continue autonomously from the current state using pm-flow for each real cycle.
Use agentic/pm_flow/{{PROJECT_NAME}}/ as the canonical project workspace.
```

What this file should contain
- The canonical resume order for project state and run history.
- The default assumption that prior work should be continued, not restarted.
- Any current-path caveats, blockers, or warnings that matter across sessions.

Manual-use note
- This file is guidance for humans and agents to read first.
- It is not executed automatically by `pm_flow.sh`.
