# Claude PM Flow

This repo uses a two-agent process:

- Codex does the implementation work.
- Claude acts as the project manager and drift reviewer.

## Hard Rules

- Every task gets a fresh Claude PM conversation.
- Claude PM calls must be issued from the top shell, never from inside child scripts.
- `pm_flow.sh` prepares prompts and records responses, but it does not execute `claude -p`.
- The first PM call uses plain `claude -p --output-format json` and captures the real `session_id`.
- Later PM calls use `claude -p --resume <session_id>`.
- In this environment, shell features around `claude -p` can defeat approved command prefixes and produce false `Not logged in` failures.
- Every PM review must include a drift review.
- Every completion report must compare expected versus observed outcome.
- Stable wrappers should be used for networked or environment-specific project commands.
- If network access fails inside a sandbox, treat that as a sandbox restriction first.

## Files

- `pm_flow.sh`
  - Creates runs, prepares prompts, writes direct Claude commands, records responses, rotates session ids, and writes transcripts.
- `task_contract.md`
  - Persistent project contract used in every Claude PM review.
- `net_exec.sh`
  - Stable command wrapper rooted at the repo.
- `local_env.sh.example`
  - Optional per-project environment configuration.
- `runs/<timestamp>-<task-slug>/`
  - Task-local metadata, prompts, responses, and transcript history.

## Setup

Validate local prerequisites:

```bash
./.claude/pm_flow/pm_flow.sh validate
```

## Start A Task

```bash
./.claude/pm_flow/pm_flow.sh init "my-task" <<'EOF'
Task summary:
- What the task is

Constraints:
- What must not change

Success criteria:
- What counts as done
EOF
```

The command prints the run directory path.

## Prepare A Step Review

```bash
./.claude/pm_flow/pm_flow.sh prepare-step "<run-dir>" "candidate-review" --file engineer_update.md
```

This creates a pending review directory containing:

- `prompt.md`
- `prompt_one_line.txt`
- `system_prompt.txt`
- `command.txt`
- `response.json`

Print the generated command and run it from the top shell:

```bash
./.claude/pm_flow/pm_flow.sh print-command "<pending-dir>"
```

`command.txt` contains a direct `claude -p` command that writes `response.json`.

Then record the response:

```bash
./.claude/pm_flow/pm_flow.sh record-step "<pending-dir>"
```

## Prepare A Completion Review

```bash
./.claude/pm_flow/pm_flow.sh prepare-complete "<run-dir>" --file completion_report.md
```

Run the generated command from the top shell, then record it:

```bash
./.claude/pm_flow/pm_flow.sh record-complete "<pending-dir>"
```

## Session Recovery

If the Claude session id for a run is stale or poisoned:

```bash
./.claude/pm_flow/pm_flow.sh rotate-session "<run-dir>" "session died during review"
```

The next prepared command will start a fresh Claude PM conversation and capture its returned `session_id`.
