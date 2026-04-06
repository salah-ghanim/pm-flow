# pm-flow

`pm-flow` is a standalone scaffold for running a two-agent workflow:

- Codex does the implementation work.
- Claude acts as project manager, drift reviewer, and completion reviewer.

This repo packages the flow as a reusable installable template so it can be pushed once and installed into any project later.

## Core Rules

- Claude PM sessions must start from a real first call and then resume with the returned `session_id`.
- The first Claude PM call uses plain `claude -p --output-format json`.
- Later Claude PM calls use `claude -p --resume <session_id>`.
- `pm_flow.sh` prepares prompts, metadata, and transcripts, but does not invoke Claude itself.
- Generated Claude commands are meant to be run directly from the top shell.
- Every PM review must include drift review.
- Every completion review must compare expected versus observed outcome.
- Networked or environment-specific project commands should run through stable repo-local wrappers.

## Repo Layout

- `install.sh`
  - Installs the scaffold into a target repo.
- `template/.claude/pm_flow/pm_flow.sh`
  - Run manager, prompt preparer, response recorder, and transcript logger.
- `template/.claude/pm_flow/net_exec.sh`
  - Stable repo-root command wrapper for networked or env-specific commands.
- `template/.claude/pm_flow/task_contract.md`
  - Persistent mission, anti-drift, and validation contract.
- `template/.claude/pm_flow/README.md`
  - Installed repo-local usage guide.
- `template/CLAUDE.md`
  - Repo-local operating reminders for Codex.

## Local Install

Install into another checked-out repo:

```bash
./install.sh /path/to/project --name "Project Name"
```

If no target path is given, the installer uses the current directory.

## Future Curl Install

After this repo is pushed, the same installer can be used directly from GitHub raw:

```bash
curl -fsSL https://raw.githubusercontent.com/salah-ghanim/pm-flow/main/install.sh | \
  zsh -s -- . --repo-raw-base https://raw.githubusercontent.com/salah-ghanim/pm-flow/main
```

That works because `install.sh` supports both:

- local-copy mode from a checked-out `pm-flow` repo
- remote-download mode from a raw GitHub base URL

## Installed Workflow

Inside the target repo:

1. Validate prerequisites.
2. Initialize a run with a task brief.
3. Prepare a step review or completion review.
4. Run the generated `command.txt` from the top shell.
5. Record the response into the transcript.
6. Rotate the session if the stored `session_id` goes stale.

The installed usage details live in `template/.claude/pm_flow/README.md` and are copied into the target repo as `.claude/pm_flow/README.md`.
