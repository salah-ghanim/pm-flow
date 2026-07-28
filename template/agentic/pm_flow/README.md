# PM Flow

PM Flow keeps project-wide coordination small by making project sections the
explicit context boundary.

```text
root project coordinator
├── section PM: api
│   ├── fresh developer: endpoint
│   └── fresh developer: contract tests
└── section PM: web
    ├── fresh developer: page shell
    └── fresh developer: integration
```

The root coordinator knows the full project shape but reads only the portfolio
plan, section registry, and bounded handoffs. Each section has its own
long-lived PM session. Every PM/developer child starts without inherited parent
conversation history.

Claude is the default PM reviewer. `codex_pm_review.sh` is a stateless fallback
when Claude is unavailable.

## Hard rules

- One section owns one PM run, session, transcript, state file, and handoff.
- The root coordinator never loads raw section transcripts or developer conversations.
- A section PM owns only its section and reads dependencies through bounded handoffs.
- Every section PM starts with no inherited root conversation (`fork_turns="none"` in Codex collaboration).
- Every engineering assignment uses a fresh developer sub-agent with no inherited PM conversation; developer conversations are never resumed.
- A root-facing handoff is at most 500 words and 8192 bytes, and contains Outcome, Decisions, Interfaces, Risks, and Next action.
- Context transitions happen through explicit state and handoff files, not automatic compaction.
- Independent sections may proceed concurrently only when their write ownership does not overlap.
- One section may have only one active pending review, and one pending review may claim PM execution only once.
- Claude PM commands run from the top shell through the generated `command.txt` and `net_exec.sh`.
- Stale parallel responses for the same section session are rejected.

The shell scaffold enforces section/session bookkeeping, stale-response checks,
and handoff limits. It prepares prompts and records PM reviews, but it does not
call a native sub-agent API. The host agent runtime must spawn sub-agents with
no inherited conversation and use each section's generated `pm_prompt.md` as
the only initial section-PM seed.

## Layout

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
        └── <timestamp>-<section>/
```

`project_state/sections.md` is a generated portfolio view. Per-section files
are authoritative.

The installed `agentic/pm_flow/.project-key` is the durable project identity.
It remains authoritative if the repository directory is renamed. Pass
`--project <key>` to override selection explicitly.

## Start or resume the root coordinator

For a fresh root context, use:

```text
agentic/pm_flow/<project>/project_state/start.md
```

For a new root context continuing an existing project, use:

```text
agentic/pm_flow/<project>/project_state/resume.md
```

Both prompts instruct the root agent to read project-level state and bounded
handoffs only.

## Create a section

The section brief is validated. It must use all six exact Markdown headings
below. `Owned paths` needs at least one repo-relative bullet. `Dependencies`
needs at least one bullet: use an exact existing section key, a repo-relative
path to its `handoff.md`, or `None.` when there are no dependencies.
The example below assumes a `data-model` section already exists.

```bash
./agentic/pm_flow/pm_flow.sh init-section "api-contract" <<'EOF'
## Objective

- Add the public API contract.

## Scope

- In: request and response schemas.
- Out: persistence implementation.

## Owned paths

- src/api/**
- tests/api/**

## Dependencies

- data-model

## Acceptance

- Contract tests pass.

## Rejection conditions

- The public schema requires an unapproved persistence change.
EOF
```

Or use `--file section_brief.md`.

A dependency section must already exist. A dependency may instead be written as
the repo-relative path
`agentic/pm_flow/<project>/sections/data-model/handoff.md`. Prose such as
“read the data model handoff” is rejected because it is not a stable identity.
Each declared handoff is copied into every pending review, so that review sees
an immutable dependency snapshot rather than silently changing input.

Section creation rejects absolute paths, paths containing `..`, and path
prefixes or globs that overlap any `planned`, `active`, or `blocked` section.
Completed and cancelled ownership can be reassigned deliberately.

The command creates:

- one isolated PM audit run and resumable session
- section-local `brief.md`, `state.md`, and `handoff.md`
- a ready-to-use `pm_prompt.md`
- a `run_path.txt` pointer
- a refreshed project section registry

Launch a PM sub-agent with the generated prompt:

```bash
./agentic/pm_flow/pm_flow.sh section-prompt api-contract
```

The host agent should pass that output to its native sub-agent creation
mechanism without inherited root history (`fork_turns="none"` in Codex
collaboration). The section PM then delegates each implementation assignment to
a new developer sub-agent with `fork_turns="none"` as well.

## Track the project without loading section detail

```bash
./agentic/pm_flow/pm_flow.sh list-sections
```

This atomically refreshes and prints
`agentic/pm_flow/<project>/project_state/sections.md`.

To resolve a section's audit run:

```bash
./agentic/pm_flow/pm_flow.sh section-run api-contract
./agentic/pm_flow/pm_flow.sh --section api-contract current-run
```

## Publish a bounded handoff

```bash
./agentic/pm_flow/pm_flow.sh \
  section-handoff api-contract active "Contract implemented; integration pending" \
  --file handoff.md
```

The handoff must have these Markdown headings and stay within 500 words and 8192 bytes:

```markdown
## Outcome
## Decisions
## Interfaces
## Risks
## Next action
```

Allowed statuses are `planned`, `active`, `blocked`, `done`, and `cancelled`.
Updating a handoff also refreshes the root registry.

## Prepare a section PM review

Use `--section` with `current`; this avoids the legacy project-global current
run pointer.

```bash
./agentic/pm_flow/pm_flow.sh \
  --section api-contract \
  prepare-step current "contract-tests" \
  --file developer_report.md
```

The pending directory contains:

- `prompt.md`
- `prompt_one_line.txt`
- `system_prompt.txt`
- `command.txt`
- `response.json`
- copies of the section's declared dependency handoffs
- session preconditions used to reject stale responses

Only one pending review can be active for a section. Preparing a second review
fails until the active one is recorded or cancelled.

Print and execute the generated command from the top shell:

```bash
./agentic/pm_flow/pm_flow.sh print-command "<pending-dir>"
```

`command.txt` first runs `claim-execution`, then invokes Claude through
`net_exec.sh`. The atomic claim is allowed exactly once, so rerunning the same
command cannot make a duplicate PM call. Do not call `claim-execution`
separately during the normal generated-command flow.

Then record it:

```bash
./agentic/pm_flow/pm_flow.sh record-step "<pending-dir>"
```

The first review starts a Claude session. Later reviews for the same section
resume that session. Sessions from other sections are independent.

If execution is aborted or its result cannot be recorded, release the active
slot explicitly:

```bash
./agentic/pm_flow/pm_flow.sh \
  cancel-pending "<pending-dir>" "PM call failed before a usable response"
```

Cancellation without an execution claim simply releases the slot. Once
execution was claimed, cancellation conservatively clears the session ID and
increments its revision because the remote PM may have advanced; the next
review starts a fresh session from durable section state.

## Completion review

```bash
./agentic/pm_flow/pm_flow.sh \
  --section api-contract \
  prepare-complete current \
  --file completion_report.md

./agentic/pm_flow/pm_flow.sh record-complete "<pending-dir>"
```

A section may publish a `done` handoff only when the latest recorded completion
review decided exactly `DONE`, no PM activity has occurred since that review,
and no pending review is active. The completion report is not exposed to the
root automatically; the section PM must still publish the bounded handoff:

```bash
./agentic/pm_flow/pm_flow.sh \
  section-handoff api-contract done "Contract validated and ready" \
  --file handoff.md
```

Statuses `done` and `cancelled` are terminal for review preparation. To resume
work deliberately, first publish an `active` or `planned` handoff. Any recorded
PM activity after reopening invalidates the old `DONE` gate, so a later `done`
transition needs a new current `DONE` completion review.

## Codex PM fallback

When Claude is unavailable:

```bash
./agentic/pm_flow/codex_pm_review.sh "<pending-dir>" [--model <model>]
./agentic/pm_flow/pm_flow.sh record-step "<pending-dir>"
```

The fallback claims execution before invoking Codex and refuses duplicate use
of the same pending review. Codex fallback reviews are stateless and write
`session_resumable: false`. Recording one clears the resumable Claude session,
so the next Claude review starts fresh from section state rather than resuming a
conversation that missed the fallback exchange.

## Session recovery

Before rotating a section PM session, checkpoint the section's durable
`state.md` and `handoff.md`. Then run:

```bash
./agentic/pm_flow/pm_flow.sh \
  --section api-contract \
  rotate-session current \
  "section PM restarted from explicit checkpoint"
```

The next prepared review starts a fresh PM session. This is an explicit context
boundary, not automatic compaction. Rotation refuses to run while a pending
review is active; record it or recover with `cancel-pending` first.

## Upgrade an already prepared review

An upgrade may leave a pending review created by the older lifecycle, before
active-slot and execution-claim metadata existed. Migrate that review once:

```bash
./agentic/pm_flow/pm_flow.sh adopt-pending "<legacy-pending-dir>"
```

`adopt-pending` first proves that the legacy review still matches the current
PM session. It then makes it the section's active pending review and upgrades
its generated command. If a valid response already exists, adoption records
the execution claim without calling the PM again. Current-schema pending
reviews cannot be adopted.

## Legacy task runs

`init`, the project-global `current_run.txt`, and explicit run paths remain
available for existing installations. New project work should use
`init-section` and `--section`.
