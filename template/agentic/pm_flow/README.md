# Claude PM Flow

This repo uses a two-agent process:

- Codex does the implementation work.
- Claude acts as the project manager and drift reviewer.

## Hard rules

- Every task gets a fresh Claude PM conversation.
- Claude PM calls must be issued from the top shell, never from inside child scripts.
- `pm_flow.sh` prepares prompts and records responses, but it does not execute `claude -p`.
- The first PM call uses plain `claude -p --output-format json` and captures the real `session_id`.
- Later PM calls use `claude -p --resume <session_id>`.
- In this environment, shell features around `claude -p` can defeat approved command prefixes and produce false `Not logged in` failures.
- Every PM review must include a drift review.
- Every completion review must compare expected versus observed outcome.
- Stable wrappers should be used for networked or environment-specific project commands.
- If network access fails inside a sandbox, treat that as a sandbox restriction first.

## Layout

Top-level generic files:

- `agentic/pm_flow/pm_flow.sh`
- `agentic/pm_flow/net_exec.sh`
- `agentic/pm_flow/local_env.sh.example`
- `agentic/pm_flow/README.md`
- `agentic/pm_flow/projects.md`

Per-project files:

- `agentic/pm_flow/<project>/task_contract.md`
- `agentic/pm_flow/<project>/project_state/`
- `agentic/pm_flow/<project>/runs/`

The script defaults to the repo basename as the active project when that directory exists. You can override it with `--project <name>` or `PM_FLOW_PROJECT=<name>`.

## Setup

Validate local prerequisites:

```bash
./agentic/pm_flow/pm_flow.sh validate
```

## Portable continuation state

- Keep stable, non-timestamped continuation files in `agentic/pm_flow/<project>/project_state/`.
- `project_state/plan.md` is the default place for the current project plan.
- `project_state/current_run.txt` stores the repo-relative path to the current run.
- Timestamped run directories remain the audit trail for transcripts and pending reviews.

## Start a task

```bash
./agentic/pm_flow/pm_flow.sh init "my-task" <<'EOF'
Task summary:
- What the task is

Constraints:
- What must not change

Success criteria:
- What counts as done
EOF
```

The command prints the run directory path and updates the selected project's `project_state/current_run.txt`.

You can inspect the current run pointer at any time:

```bash
./agentic/pm_flow/pm_flow.sh current-run
```

If you need a non-default project:

```bash
./agentic/pm_flow/pm_flow.sh --project other-project current-run
```

## Prepare a step review

```bash
./agentic/pm_flow/pm_flow.sh prepare-step "<run-dir>" "candidate-review" --file engineer_update.md
```

You can use `current` instead of a timestamped run path:

```bash
./agentic/pm_flow/pm_flow.sh prepare-step current "candidate-review" --file engineer_update.md
```

This creates a pending review directory containing:

- `prompt.md`
- `prompt_one_line.txt`
- `system_prompt.txt`
- `command.txt`
- `response.json`

Print the generated command and run it from the top shell:

```bash
./agentic/pm_flow/pm_flow.sh print-command "<pending-dir>"
```

`command.txt` contains a direct `claude -p` command that writes `response.json`.

Then record the response:

```bash
./agentic/pm_flow/pm_flow.sh record-step "<pending-dir>"
```

## Prepare a completion review

```bash
./agentic/pm_flow/pm_flow.sh prepare-complete "<run-dir>" --file completion_report.md
```

Run the generated command from the top shell, then record it:

```bash
./agentic/pm_flow/pm_flow.sh record-complete "<pending-dir>"
```

## Session recovery

If the Claude session id for a run is stale or poisoned:

```bash
./agentic/pm_flow/pm_flow.sh rotate-session "<run-dir>" "session died during review"
```

The next prepared command will start a fresh Claude PM conversation and capture its returned `session_id`.
