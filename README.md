# pm-flow

`pm-flow` is a standalone scaffold for running a two-agent workflow:

- Codex does the implementation work.
- Claude acts as project manager, drift reviewer, and completion reviewer.
  When the Claude API is rate-limited or unavailable, `codex_pm_review.sh` provides
  a drop-in Codex fallback that writes the same `response.json` format.

This repo packages the flow as a reusable installable template.

Re-running the installer upgrades reusable flow/config files in place while
preserving existing per-project state under `project_state/` and run history
under `runs/`. The main per-project exception is `task_contract.md`, which is
treated as rules/config and refreshed on reinstall.

## Core rules

- Claude PM sessions must start from a real first call and then resume with the returned `session_id`.
- The first Claude PM call uses `claude -p --output-format json` inside `./agentic/pm_flow/net_exec.sh`.
- Later Claude PM calls use `claude -p --resume <session_id>` inside that wrapper.
- `pm_flow.sh` prepares prompts, metadata, and transcripts, but does not invoke Claude itself.
- Generated Claude commands are meant to be run from the top shell through the stable `net_exec.sh` wrapper.
- The PM system prompt is passed from `system_prompt.txt` via `--append-system-prompt-file`, not inlined on the command line.
- Every PM review must include drift review.
- Every completion review must compare expected versus observed outcome.
- Networked or environment-specific project commands should run through stable repo-local wrappers.

## Canonical installed layout

The canonical installed layout is now:

- `agentic/pm_flow/`
  - generic top-level scripts and shared files
- `agentic/pm_flow/projects.md`
  - repo-local registry of available project workspaces
- `agentic/pm_flow/<project>/`
  - project-specific task contract, continuation state, and runs

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
- `agentic/pm_flow/<project>/project_state/start.md`
- `agentic/pm_flow/<project>/project_state/resume.md`

## Template layout

- `install.sh`
  - Installs or updates the scaffold in a target repo.
- `template/agentic/pm_flow/pm_flow.sh`
  - Generic run manager, prompt preparer, response recorder, and transcript logger.
- `template/agentic/pm_flow/net_exec.sh`
  - Generic repo-root command wrapper for networked or env-specific commands.
- `template/agentic/pm_flow/codex_pm_review.sh`
  - Codex fallback for PM reviews when the Claude API is rate-limited or unavailable.
- `template/agentic/pm_flow/projects.md`
  - Project registry template.
- `template/agentic/pm_flow/project/`
  - Per-project template files such as `task_contract.md` and `project_state/`.
- `template/CLAUDE.md`
  - Repo-local operating reminders for Codex.

## Local install

Install into another checked-out repo:

```bash
./install.sh /path/to/project --name "Project Name"
```

If no target path is given, the installer uses the current directory.
Re-running the same install command updates reusable flow files and
`task_contract.md` without overwriting existing `project_state/*` files unless
you pass `--force`.

## Future curl install

After this repo is pushed, the same installer can be used directly from GitHub raw:

```bash
curl -fsSL https://raw.githubusercontent.com/salah-ghanim/pm-flow/main/install.sh | \
  zsh -s -- . --repo-raw-base https://raw.githubusercontent.com/salah-ghanim/pm-flow/main
```

That works because `install.sh` supports both:

- local-copy mode from a checked-out `pm-flow` repo
- remote-download mode from a raw GitHub base URL

## Installed workflow

Inside the target repo:

1. Validate prerequisites.
2. Initialize a run with a task brief.
3. Prepare a step review or completion review.
4. Run the generated `command.txt` from the top shell (Claude), or run
   `codex_pm_review.sh <pending-dir>` as a Codex fallback.
5. Record the response into the transcript.
6. Rotate the session if the stored `session_id` goes stale.

## Codex PM fallback

When the Claude API is rate-limited, use the included Codex fallback:

```bash
./agentic/pm_flow/codex_pm_review.sh "<pending-dir>" [--model o4-mini]
```

This inlines all referenced workspace files into a self-contained prompt, calls
`codex exec`, and writes a `response.json` compatible with `pm_flow.sh record-step`
and `record-complete`. The normal record commands work unchanged after the fallback runs.

See `agentic/pm_flow/README.md` in any installed repo for full details.

Installed repos get repo-local portable state under `agentic/pm_flow/<project>/project_state/`. Timestamped run directories remain the audit trail under `agentic/pm_flow/<project>/runs/`.

Recommended prompt scaffolding:

- Use `project_state/start.md` when beginning a fresh session for a project.
- Use `project_state/resume.md` when continuing an existing project session.
- These files are markdown guidance for the agent to read first. They are intentionally manual prompt scaffolding, not executable behavior in `pm_flow.sh`.
