# pm-flow

`pm-flow` installs a headless agent team into a repository. You describe the
product; it cuts the work into sections, drives each one, escalates what fails,
and stops when the product is assembled or it can show you why it cannot be.

```text
product officer          cuts the product into sections, adjudicates failures
└── section manager      scopes assignments, reviews results
    ├── developer        one bounded assignment, then discarded
    ├── consultants      an independent panel, when a section keeps failing
    └── rescue engineer  the last attempt, on the path the officer chose
```

## Install

```bash
./install.sh /path/to/repo --name "My Product" --domain saas
```

Domains — `generic`, `saas`, `prop-trading`, `crypto-trading`, `infrastructure`,
`migration` — specialise every role for the problem space. `generic` is the
default and is deliberately neutral: it tells agents not to assume a domain they
were not given.

One repository can run several projects, and they need not be the same kind of
work. Each project records its own domain, so a platform project and the
migration that replaces it can share a flow directory without sharing personas:

```bash
./install.sh /path/to/repo --project-key platform  --domain infrastructure
./install.sh /path/to/repo --project-key migration --domain migration --add-project
./agentic/pm_flow/pm_flow.sh --project migration run
```

Reinstalling refreshes the scripts, prompts, and contract while preserving
`config.json`, each project's recorded domain, the project plan, section
workspaces, and run history.

## Run it

```bash
cd /path/to/repo
$EDITOR agentic/pm_flow/<project>/project_state/plan.md   # what you want built
./agentic/pm_flow/pm_flow.sh run
```

`run` repeats `tick` until nothing is actionable. Each tick observes the files
on disk, derives the single next action, performs it, and exits — so an
interrupted run resumes by being run again, with nothing to clean up first.

```bash
./agentic/pm_flow/pm_flow.sh status   # what each section will do next
./agentic/pm_flow/pm_flow.sh tick     # one transition, then stop
```

## Roles are named, not vendors

`agentic/pm_flow/config.json` binds each role to a CLI, a model, and a
difficulty. Nothing in the flow's prompts or files names a vendor:

```json
"roles": {
  "pm":         { "cli": "claude", "model": "claude-opus-5",   "difficulty": "medium" },
  "developer":  { "cli": "claude", "model": "claude-sonnet-5", "difficulty": "medium" },
  "consultant": [{ "cli": "claude", "model": "claude-opus-5", "difficulty": "xhigh" },
                 { "cli": "codex",  "model": "gpt-5.6-sol",   "difficulty": "high" }]
}
```

`difficulty` is one vocabulary (`low` … `max`) mapped to whatever each CLI
exposes. A role bound to a list is a panel whose seats run in parallel and blind
to each other — worth doing across different model families, not within one.

Only the building roles can write to the repository; reviewing and planning
roles are dispatched read-only.

## What happens when work fails

After a configurable number of consecutive rejections a section goes to the
consultant panel with the full history of what was attempted and observed. Each
seat answers independently. The product officer then adopts one path, runs
several in parallel, synthesises them, or abandons the section with a statement
of what the product loses. Adopted paths go to a rescue engineer; when the
rescue rounds are spent the section is abandoned rather than escalating forever.

Giving up is meant to be rare, and it is a product decision rather than the
default way a hard section ends.

## Supervision

An unattended run cannot ask for help, so every dispatch is supervised: usage
limits pause and retry, network faults retry with backoff, real errors are not
retried at all, and an agent that stops reporting progress is terminated as a
whole process group and retried.

## Core invariants

- Every role runs as a fresh process. Continuity lives in files, never in a
  conversation.
- Sections own disjoint paths, so they can run concurrently without colliding.
- A section reports upward only through a handoff capped at 500 words and
  8192 bytes.
- Consecutive failures are counted from the section's own history, so a crash
  cannot desynchronise them.
- Consultant seats never see each other's proposals.
- A dispatch is claimed before a model is called, so a crash cannot silently pay
  for the same call twice.

## Repository contents

- `install.sh` installs or upgrades the scaffold.
- `template/agentic/pm_flow/pm_flow.sh` — commands.
- `template/agentic/pm_flow/driver.zsh` — the run loop.
- `template/agentic/pm_flow/agent_exec.sh` — dispatches one role, supervised.
- `template/agentic/pm_flow/roles/` — who each role is.
- `template/agentic/pm_flow/domains/` — how roles specialise per domain.
- `template/agentic/pm_flow/tasks/` — what a role is asked to do on a call.
- `tests/pm_flow_test.sh` — the suite, run with `zsh tests/pm_flow_test.sh`.
