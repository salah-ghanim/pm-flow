# pm-flow

`pm-flow` is an installable scaffold for bounded multi-agent project work.

```text
root coordinator (whole-project awareness, small context)
└── one long-lived PM sub-agent per isolated section
    └── one fresh developer sub-agent per engineering assignment
```

The root coordinator tracks the full project through a portfolio plan, a
generated section registry, and handoffs capped at 500 words and 8192 bytes. It
never needs to absorb section transcripts or developer conversations. Each
section PM keeps the detail for one complete section, while developer agents
always start with a fresh, non-inherited context.

Claude is the default PM reviewer. When Claude is unavailable,
`codex_pm_review.sh` provides a stateless fallback using the same
`response.json` contract.

## Core invariants

- Each section owns an independent PM session and audit run.
- Every PM and developer sub-agent launch requires no inherited parent conversation.
- The root context receives section handoffs capped at 500 words and 8192 bytes.
- Section transitions and PM restarts use explicit file checkpoints instead of automatic compaction.
- Independent sections can proceed concurrently only when their owned paths do not overlap.
- Each section permits one active pending review, and each pending review permits one execution claim.
- Stale out-of-order PM responses within one section are rejected.
- A section cannot become `done` until its current completion review records `DONE`.
- Existing non-section task runs remain usable for compatibility.
- Reinstalling refreshes scripts and rules while preserving project state, sections, and run history.

The scaffold enforces section/session bookkeeping, ownership-overlap checks,
stale-response checks, and handoff limits. It prepares prompts, state, commands, and transcripts, but does
not itself call a native sub-agent API. The host agent runtime is responsible
for launching sub-agents without inherited history using the generated project
and section prompts.

## Canonical installed layout

```text
agentic/pm_flow/
├── pm_flow.sh
├── net_exec.sh
├── codex_pm_review.sh
├── projects.md
└── <project>/
    ├── task_contract.md
    ├── project_state/
    │   ├── plan.md
    │   ├── sections.md
    │   ├── start.md
    │   └── resume.md
    ├── sections/
    │   └── <section>/
    │       ├── brief.md
    │       ├── pm_prompt.md
    │       ├── state.md
    │       ├── handoff.md
    │       └── run_path.txt
    └── runs/
```

## Install

Install into another checked-out repository:

```bash
./install.sh /path/to/project --name "Project Name"
```

If no target path is given, the installer uses the current directory.

Re-running the installer refreshes generic flow files, `task_contract.md`, and
the managed root-coordinator `start.md`/`resume.md` prompts. A pre-section
version of either prompt is backed up once with a `.pre-sections.md` suffix.
The project plan, section workspaces, generated registry, and run history are
preserved. Refreshed files are staged and atomically replaced.

If the target already has a `CLAUDE.md`, its original content is backed up once
as `CLAUDE.pre-pm-flow.md`. Reinstalls replace only the marked pm-flow managed
block and preserve the repository's other instructions. The installed
`agentic/pm_flow/.project-key` preserves project identity if the repository
directory is later renamed; use `--project-key` to select an identity
explicitly. Use `--force` only for an intentional full replacement.

The installer can also run from a raw GitHub base:

```bash
curl -fsSL https://raw.githubusercontent.com/salah-ghanim/pm-flow/main/install.sh | \
  zsh -s -- . --repo-raw-base https://raw.githubusercontent.com/salah-ghanim/pm-flow/main
```

## Start the multi-agent flow

In an installed repository, launch the root coordinator from:

```text
agentic/pm_flow/<project>/project_state/start.md
```

That prompt tells the root agent to:

1. read only the portfolio plan, section registry, and task contract
2. split the project into isolated sections
3. create each section with `init-section`
4. spawn a PM sub-agent with no inherited root history using only the generated section `pm_prompt.md`
5. reconcile sections through bounded handoffs

Create a section:

```bash
./agentic/pm_flow/pm_flow.sh init-section "api-contract" --file section_brief.md
```

`section_brief.md` must use these exact Markdown headings:

```markdown
## Objective

## Scope

## Owned paths
- src/api/**

## Dependencies
- data-model

## Acceptance

## Rejection conditions
```

Owned paths must be repo-relative and cannot overlap another nonterminal
section. Each dependency bullet is either an exact existing section key, a
repo-relative path to that section's `handoff.md`, or `None.` when empty.

Inspect the generated section PM launch prompt:

```bash
./agentic/pm_flow/pm_flow.sh section-prompt api-contract
```

Refresh the bounded root view:

```bash
./agentic/pm_flow/pm_flow.sh list-sections
```

See the installed `agentic/pm_flow/README.md` for step reviews, completion
reviews, handoff format, session recovery, and the Codex fallback.

## Template contents

- `install.sh` installs or upgrades the scaffold.
- `template/agentic/pm_flow/pm_flow.sh` manages sections, PM sessions, prompts, responses, and transcripts.
- `template/agentic/pm_flow/codex_pm_review.sh` runs stateless Codex PM fallback reviews.
- `template/agentic/pm_flow/net_exec.sh` provides a stable repo-root command wrapper.
- `template/agentic/pm_flow/project/project_state/` contains root coordinator prompt and portfolio templates.
- `template/agentic/pm_flow/project/task_contract.md` defines the root→section PM→fresh developer contract.
- `template/CLAUDE.md` installs repo-local orchestration rules.
