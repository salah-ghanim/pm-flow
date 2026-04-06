# {{PROJECT_NAME}} Repo Notes

- This repo uses `.claude/pm_flow/pm_flow.sh` for Claude PM review preparation and transcript logging.
- Claude PM reviews are executed by running the generated `command.txt` from the top shell.
- In this environment, shell features around `claude -p` can cause false `Not logged in` failures by bypassing the approved runtime path.
- The generated command bootstraps with plain `claude -p --output-format json` and resumes with `--resume` after a real `session_id` has been captured.
- Use `.claude/pm_flow/net_exec.sh` or other stable wrappers before switching to ad hoc command shapes.
- If network access fails in a sandboxed command, treat that as a sandbox restriction first.
- Every cycle must use the task contract in `.claude/pm_flow/task_contract.md`.
- Do not count workflow or documentation work as success unless it directly unlocks the same task cycle.
