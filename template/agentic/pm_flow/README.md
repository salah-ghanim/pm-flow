# PM Flow

PM Flow runs a software project with a team of agents and no human in the loop.
Work is cut into sections, each section is driven by its own manager, and every
piece of engineering goes to a fresh agent with no inherited conversation.

```text
product officer          cuts the product into sections, adjudicates failures
└── section manager      scopes assignments, reviews results
    ├── developer        one bounded assignment, then discarded
    ├── consultants      an independent panel, when a section keeps failing
    └── rescue engineer  the last attempt, on the path the officer chose
```

## Roles, not vendors

Roles are named. `config.json` binds each one to a CLI, a model, and a
difficulty, so nothing in the flow depends on which vendor is behind a role:

```json
{
  "roles": {
    "cpo":           { "cli": "claude",  "model": "claude-opus-5",  "difficulty": "high" },
    "pm":            { "cli": "claude",  "model": "claude-opus-5",  "difficulty": "medium" },
    "developer":     { "cli": "claude",  "model": "claude-sonnet-5","difficulty": "medium" },
    "consultant":    [{ "cli": "claude", "model": "claude-opus-5",  "difficulty": "xhigh" },
                      { "cli": "codex",  "model": "gpt-5.6-sol",    "difficulty": "high" }],
    "10x_developer": { "cli": "claude",  "model": "claude-opus-5",  "difficulty": "max" }
  }
}
```

`difficulty` is one vocabulary — `low`, `medium`, `high`, `xhigh`, `max` —
translated into whatever knob each CLI exposes. A role bound to a *list* is a
panel: its seats run in parallel and blind to each other, which is only worth
doing across different model families.

Check the bindings with:

```bash
./agentic/pm_flow/pm_flow.sh config
```

## Access

Roles are dispatched in one of three tiers, set by `access` in `config.json`:

| Tier | Roles by default | May write |
|---|---|---|
| `write` | `developer`, `10x_developer` | the whole repository |
| `scoped` | `pm`, `cpo` | their own project workspace under `agentic/pm_flow/<project>/`, plus git and the acceptance check |
| `read` | everything else | nothing |

The `scoped` tier exists because the managing roles are asked to keep `state.md`
current, write a handoff, and commit their own cycle — and a role dispatched
read-only cannot do any of it. It is still not allowed to write source, so a
review cannot quietly edit the code it is judging.

On the `claude` backend the tier is enforced: the dispatch is given a generated
settings file whose allow-list names the writable roots and the permitted shell
prefixes, under the default permission mode, so anything unnamed is denied
outright. `codex` and `copilot` cannot narrow write access below their working
root while keeping repo-relative paths meaningful, so on those backends `scoped`
is a prompt-level boundary only. Bind the managing roles to a backend that can
enforce the tier if that difference matters to you.

Add extra writable roots with `access.scoped_write_paths` and extra shell
prefixes with `access.scoped_bash`.

## Personas

Each role is specialised for the project's domain, set at install with
`--domain`: `generic`, `saas`, `prop-trading`, `crypto-trading`,
`infrastructure`, or `migration`. A consultant on a crypto project opens as a
*Quantitative Trading Consultant* who knows that a backtest is evidence rather
than proof; the same role on an infrastructure project is a *Principal Cloud
Architect* who plans before apply. `migration` is for moving an existing AI
automation toolchain onto a new one, where prompts, configuration, and
documentation have to land in the same change as the code. `generic` is
deliberately neutral and tells the agent not to assume a domain it was not
given.

The domain belongs to the project, not to this directory: it is recorded in
`<project>/project.json`, so sibling projects can be different kinds of work.
`config.json` carries the domain only as a fallback for projects installed
before that was true.

```bash
./agentic/pm_flow/pm_flow.sh --project migration role-prompt consultant
./agentic/pm_flow/pm_flow.sh --project migration config   # domain=... (project.json)
```

## Running a project

```bash
./agentic/pm_flow/pm_flow.sh status      # what each section will do next
./agentic/pm_flow/pm_flow.sh tick        # perform exactly one transition
./agentic/pm_flow/pm_flow.sh run         # repeat until nothing is actionable
```

Fill in `project_state/plan.md` first — it is what the product officer reads.
With no sections yet, the first tick decomposes the product into them.

Declared dependencies are scheduling gates. A section reports
`waiting-dependencies` and cannot be scoped or dispatched until every dependency
section is `done`; its manager then receives the accepted dependency handoffs in
the next scope context. A section whose lifecycle is `blocked` is also
non-actionable until it is deliberately reopened.

Among the sections that *are* actionable, the driver takes the one the most
other sections are waiting on, then the one dispatched longest ago, then the
first by key. Lexical order would let whichever section happens to sort first
take every dispatch.

A section whose dispatch fails fatally is quarantined rather than ending the
run: `quarantine.txt` records what failed, `status` shows it, and the remaining
sections carry on. `run` exits non-zero only when nothing can move — every live
section quarantined, or a dependent left waiting on a section that was
cancelled.

Every dispatch records what it cost to `runs/cost_ledger.tsv`. `status` and each
tick line show the running total, and `budget.max_usd` and
`budget.max_usd_per_section` stop a run before it spends past them. Costs are
reported by the `claude` backend; other backends record the dispatch with an
unknown cost rather than zero.

The driver is level-triggered: it stores no record of what it was doing. Every
tick observes the files on disk, derives the single next action, performs it,
and exits. Resuming an interrupted run is therefore not a special case; it is
the same command run again. Nothing needs to be cleaned up first.

A section's state *is* its files:

```text
sections/<key>/
├── brief.md                 the boundary and acceptance criteria
├── state.md                 durable detail the manager keeps
├── handoff.md               the bounded report upward
├── quarantine.txt           written only if a dispatch failed fatally
└── cycles/001/
    ├── scope.md             the manager's whole scope response
    ├── assignment.md        the part of it the developer is given
    ├── result.md            produced by the developer
    ├── dev_status.txt       DELIVERED, PARTIAL, or BLOCKED
    ├── review.md            judged by the manager
    ├── decision.txt         GO, GO_WITH_CHANGES, NO_GO, or UNPARSED
    └── heartbeat.txt        progress the developer reports as it works
```

A verdict the driver cannot read is recorded as `UNPARSED`, counts as a failure,
and is re-asked with the parser's own complaint fed back. It used to leave no
`decision.txt` at all, so the next tick read the cycle as though it had passed
and a formatting miss was cheaper than an honest rejection.

`result.md` belongs to the harness: each dispatch publishes the role's response
over it. An assignment must therefore never grant a role write access to it,
because the dispatch would overwrite whatever the role put there and the review
would then reject the work as missing. The driver refuses such an assignment
before spending a dispatch on it. Durable evidence a role is asked to retain
belongs in a separate artifact beside `result.md`, named by the assignment.

## When a section cannot close

Three different things get confused with each other, and each has its own exit.

**It is hard.** Repeated rejection escalates to the consultant panel; see below.

**It is unreachable.** An acceptance criterion needs credentials, a live
external system, market hours, weeks of elapsed wall clock, or a human
signature. No assignment the manager can write will ever satisfy it, and
scoping another cycle at it only spends more. The manager answers
`BLOCKED_EXTERNAL`, naming the dependency and what would unblock it; the section
goes `blocked` and reopens deliberately once the dependency lands.

**It is going nowhere.** `GO_WITH_CHANGES` resets no counter and costs nothing,
so a section can accept cycle after cycle while converging on nothing and never
arm the escalation ladder. After `escalation.cycles_before_convergence_review`
accepted cycles with no `COMPLETE` and no `NO_GO`, the product officer is asked
one question — is the remaining distance shrinking — reading only the brief and
the last two reviews. It answers `CONTINUE`, `RESCOPE`, `BLOCKED_EXTERNAL`, or
`ABANDON`.

## When a section keeps failing

Repeated failure is treated as a signal about the approach, not about effort.
After `escalation.failures_before_consultant` consecutive rejections the section
goes to the consultant panel with the recent history of what was attempted and
what was observed. Each seat answers independently, and the product officer then
decides:

- `ADOPT` — take one path
- `ADOPT_PARALLEL` — run several at once, each in its own attempt, with a stated
  rule for what picks the winner
- `SYNTHESIZE` — combine them
- `ABANDON` — the capability cannot be delivered and the product can survive
  without it

Adopted paths go to the rescue engineer. A rescue that fails review consumes a
round; when `escalation.max_rescue_attempts` rounds are spent the section is
abandoned rather than escalating forever.

You can convene a panel by hand:

```bash
./agentic/pm_flow/pm_flow.sh consult-panel <section> --file failure_notes.md
```

## Supervision

Every dispatch is supervised, because an unattended run cannot ask for help:

- a usage limit pauses and retries
- a network fault retries with backoff, as does a model overload, which is
  transient rather than a usage limit and is classified from whichever stream
  the CLI reported it on
- a *named* permanent condition — a failed login, an unknown model, a bad
  argument, a policy refusal — is not retried at all, since retrying spends
  quota to get the same answer
- anything unrecognised is retried exactly once. Permanence is an allow-list,
  not the fall-through: one unenumerated way of spelling a transport error used
  to end an unattended run outright
- an agent that stops reporting progress is terminated as its whole process
  group and retried. Every dispatch is watched, not only the ones carrying a
  heartbeat file: a dispatch that reports progress is judged against
  `supervision.heartbeat_stall_seconds`, one that does not against the far
  longer `supervision.silent_stall_seconds`, and both against a hard
  `supervision.max_attempt_seconds` ceiling on a single attempt

Tune these under `supervision` in `config.json`.

## Sections by hand

The product officer normally creates sections, but you can add one directly:

```bash
./agentic/pm_flow/pm_flow.sh init-section "api-contract" --file brief.md
./agentic/pm_flow/pm_flow.sh list-sections
```

A brief needs the exact headings `Objective`, `Scope`, `Owned paths`,
`Dependencies`, `Acceptance`, and `Rejection conditions`. Owned paths must be
repo-relative and cannot overlap a section that is still live, because sections
may run concurrently. Each dependency is an existing section key or a
repo-relative path to its `handoff.md`; the dependency section must be `done`
before the dependent section becomes actionable.

## Layout

```text
agentic/pm_flow/
├── config.json          role bindings, escalation, supervision
├── pm_flow.sh           commands
├── driver.zsh           the run loop
├── agent_exec.sh        dispatches one role as a supervised process
├── roles/               who each role is
├── domains/             how each role is specialised per domain
├── tasks/               what a role is being asked to do on a given call
└── <project>/
    ├── project.json      this project's domain
    ├── task_contract.md
    ├── project_state/   plan.md, sections.md, start.md, resume.md
    ├── sections/
    └── runs/
```

`agentic/pm_flow/.project-key` is the durable identity of the *default* project
and survives the repository being renamed. Pass `--project <key>` to select
another. Everything above `<project>/` is shared by every project here; anything
that differs between them, the domain included, belongs inside the project.

Copy `local_env.sh.example` to `local_env.sh` to set environment for every
dispatched role.
