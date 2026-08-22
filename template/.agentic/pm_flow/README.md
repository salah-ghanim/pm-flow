# PM Flow

PM Flow runs a software project with a team of agents and no human in the loop.
Work is cut into sections, each section is driven by its own manager, and every
piece of engineering goes to a fresh agent with no inherited conversation.

```text
product officer          cuts the product into sections, reviews the portfolio,
│                        cuts what the product does not need
└── section manager      scopes assignments, reviews results
    ├── developer        one bounded assignment, then discarded
    ├── consultants      an independent panel, when a section keeps failing
    └── rescue engineer  the last attempt, on the path the officer chose
```

The product officer's ground truth is the mission and the committed evidence,
never the reports from below it. It reads the plan, its own portfolio log, the
section registry and bounded handoffs, and it treats every handoff as a claim to
check rather than a fact to accept. It never reads transcripts, developer
results, reviews or assignments, and it never browses evidence in bulk: it
probes, asking bounded questions whose answers are one or two lines, one per
completion criterion.

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
./.agentic/pm_flow/pm_flow.sh config
```

## Access

Roles are dispatched in one of three tiers, set by `access` in `config.json`:

| Tier | Roles by default | May write |
|---|---|---|
| `write` | `developer`, `10x_developer` | the whole repository |
| `scoped` | `pm`, `cpo` | their own project workspace under `.agentic/pm_flow/<project>/`, plus git and the acceptance check |
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

## Isolation

Every section gets its own git worktree, and its dispatches run there rather
than in the repository you are sitting in. Sections owning disjoint paths is an
honour system: it holds only while every role obeys its brief, and it cannot
survive two sections editing the same file. A worktree makes the separation
structural.

It is also what makes it safe for the flow to work on its own machinery. A
developer rewriting `driver.zsh` while `driver.zsh` is executing the run is a
live hazard; inside a worktree that developer is editing a different copy, and
the change reaches the running engine only when the branch is merged.

- Worktrees live under `.git/pm-flow/worktrees/<project>/<section>`, so they are
  outside the working tree and need no `.gitignore` entry of their own.
- The branch is `pm-flow/<project>/<section>`.
- An accepted cycle is committed on that branch and merged back into whatever
  branch the main tree has checked out. The merge is tested with `merge-tree`
  first, so a conflict leaves the main working tree untouched and writes
  `merge_blocked.txt` next to the section instead.
- A rejected cycle merges nothing. Its work stays on the branch, and the next
  cycle continues from it.
- Parallel rescue gives each path its own worktree, because the paths are meant
  to be independent attempts at the same problem. When several deliver, they are
  *not* merged together — the branches are named in `rescue_branches.txt` and
  the choice is yours.
- Finishing or abandoning a section removes its worktree and keeps its branch.
- Orphaned worktrees from a killed run are pruned at the start of every run.

Orchestration state does not move: the cycle records, `state.md` and `handoff.md`
stay in the main tree, because that is where the next fresh process reads them.
The dispatch is given its cycle directory as an explicit grant alongside the
worktree.

Set `isolation.worktrees` to `false` to turn this off. It is off automatically
when the project is not a git repository, and the flow then behaves exactly as
it did before worktrees existed.

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
./.agentic/pm_flow/pm_flow.sh --project migration role-prompt consultant
./.agentic/pm_flow/pm_flow.sh --project migration config   # domain=... (project.json)
```

## Running a project

```bash
./.agentic/pm_flow/pm_flow.sh status      # what each section will do next
./.agentic/pm_flow/pm_flow.sh tick        # perform exactly one transition
./.agentic/pm_flow/pm_flow.sh run         # repeat until nothing is actionable
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
`budget.max_usd_per_section` stop a run before it spends past them. Both default
to `0`, which means unlimited rather than nothing. Costs are reported by the
`claude` backend; other backends record the dispatch with an unknown cost rather
than zero.

## The portfolio review

Project-level work preempts section work, because there is always a section
willing to scope one more cycle. Whichever of these fires first convenes the
product officer for a review of the whole product, whether or not anything has
failed:

| `governance` key | Default | Fires when |
|---|---|---|
| `portfolio_review_dispatches` | 12 | that many dispatches since the last review |
| `portfolio_review_usd` | 20 | that much project spend since the last review |
| `portfolio_review_idle_cycles` | 8 | that many cycles since the last review with no section reaching `done` |
| `portfolio_log_full_entries` | 4 | how many past reviews stay in the log in full |

Set a key to `0` to switch that trigger off.

The review asks what the product still *lacks*, never how the sections are
doing. It settles every completion criterion in the plan with its own probe, it
checks the plan's own structure for an unstarted dependency, an unreachable
section, must-have inflation and linear-chain risk, and it answers per section
with `CONTINUE`, `RESCOPE`, `CUT` or `BLOCK`, plus `ON_TRACK` or `OFF_TRACK` for
the product. `CUT` cancels the section through the normal handoff path, `BLOCK`
marks it blocked, and `RESCOPE` reaches that section's next scope call with the
officer's reason in context.

Each review appends to `project_state/portfolio_log.md`: the date, the spend,
every criterion's `MET` or `NOT MET`, every verdict, and the stated shortest path
to the next unmet criterion. The officer is a fresh process each time, so that
file is its only memory, and it is what makes a section that has been nearly done
for four reviews visible as the pattern it is. Older entries compact to one line
each so the log cannot grow without bound.

Sections carry a priority, set at decomposition and owned by the officer:
`must-have` or `nice-to-have` plus one line naming what the product loses without
it. A section created before priorities existed reads as `must-have`. A
`nice-to-have` consuming the project's spend while a `must-have` criterion sits
untouched is what `CUT` is for.

The officer may make the product smaller, visibly, and may never make the
evidence weaker, quietly. It edits `plan.md`, the log and any `priority.txt`
freely; it reduces a section's scope only as a dated `## Reduced scope,
authorized <date>` heading appended to that brief, leaving the original
Acceptance bullets in the diff; and it changes the dependency graph only through
the validated command:

```bash
./.agentic/pm_flow/pm_flow.sh section-dependencies <section> --file deps.md
```

which takes a `## Dependencies` block and refuses a missing section, a
self-dependency, a cycle, or an ownership overlap. On the `claude` backend the
officer is additionally denied write access to every cycle artifact, because a
role that can rewrite the record of what it decided cannot be checked against it.

The driver is level-triggered: it stores no record of what it was doing. Every
tick observes the files on disk, derives the single next action, performs it,
and exits. Resuming an interrupted run is therefore not a special case; it is
the same command run again. Nothing needs to be cleaned up first.

A section's state *is* its files:

```text
sections/<key>/
├── brief.md                 the boundary and acceptance criteria
├── state.md                 durable detail the manager keeps
├── priority.txt             must-have or nice-to-have, and what is lost
├── handoff.md               the bounded report upward, unproven claims included
├── quarantine.txt           written only if a dispatch failed fatally
├── analysis/                assessments asked for by hand, outside any cycle
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

A handoff carries `Outcome`, `Decisions`, `Interfaces`, `Risks`,
`What is unproven` and `Next action`, in 500 words and 8192 bytes.
`What is unproven` is the one that costs something to write: every capability
the section claims that has not been demonstrated against the real thing, and
the observation that would settle it. A section whose client had never contacted
its venue reported that clearly, in bold, from its third cycle onward, and
nothing was ever convened to read it. The portfolio review now is, and it is
required to answer that list section by section.

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
./.agentic/pm_flow/pm_flow.sh consult-panel <section> --file failure_notes.md
```

## On demand

Everything above happens on the flow's schedule: a review waits for a governance
threshold, a manager only speaks at a scope or a review, a panel only convenes
after repeated failure. These three commands ask for the same work now.

```bash
./.agentic/pm_flow/pm_flow.sh portfolio-review
./.agentic/pm_flow/pm_flow.sh section-analysis <section> [--file question.md]
./.agentic/pm_flow/pm_flow.sh proposals <name> --file question.md
```

`portfolio-review` is the review above with the thresholds bypassed. It is a
review in every other respect: the verdicts take effect, the entry is appended
to `portfolio_log.md`, and the governance baseline advances, so asking for one
does not leave the loop about to convene another.

`section-analysis` asks one section's manager where the section stands against
its own acceptance, criterion by criterion, what is blocking it, what it would
do next and why, and what it cannot settle itself. It opens no cycle, writes no
assignment and returns no verdict: the scope call is otherwise the only place a
manager speaks, and it can only answer by opening a cycle. The answer lands in
`sections/<key>/analysis/<timestamp>/analysis.md`, with `analysis/latest.md`
pointing at the most recent.

`proposals` convenes the consultant panel on a question rather than on a
failure, then has the product officer adjudicate the answers. The question is
free-form: "propose three ways to structure the data branch", "should this
project add a futures sleeve". The seats run in parallel and blind to each other
exactly as the failure panel does.
Everything lands under `panels/<name>/<timestamp>/`: one proposal per seat, the
adjudication, and `decision.txt` naming the path that was adopted.

All three refuse rather than queue while a driver holds the project, dispatch
immediately, and record what they cost in the ledger.

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

## Checking the flow itself

```bash
./.agentic/pm_flow/tests/run.zsh
```

Nothing in the suite calls a model. The dispatcher is stubbed with canned
responses and canned failures, so every transition, every recovery path, and the
verdict parser's whole near-miss table run for free against a synthetic project
in a temporary directory. Run it after changing the driver.

## Sections by hand

The product officer normally creates sections, but you can add one directly:

```bash
./.agentic/pm_flow/pm_flow.sh init-section "api-contract" --file brief.md
./.agentic/pm_flow/pm_flow.sh list-sections
```

A brief needs the exact headings `Objective`, `Scope`, `Priority`,
`Owned paths`, `Dependencies`, `Acceptance`, and `Rejection conditions`.
`Priority` is one bullet: `must-have` or `nice-to-have`, then one line naming
what the product loses without this section. Owned paths must be repo-relative
and cannot overlap a section that is still live, because sections may run
concurrently. Each dependency is an existing section key or a
repo-relative path to its `handoff.md`; the dependency section must be `done`
before the dependent section becomes actionable.

## Layout

```text
.agentic/pm_flow/
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
    ├── panels/          proposals asked for by hand, and their adjudication
    └── runs/
```

`.agentic/pm_flow/.project-key` is the durable identity of the *default* project
and survives the repository being renamed. Pass `--project <key>` to select
another. Everything above `<project>/` is shared by every project here; anything
that differs between them, the domain included, belongs inside the project.

Copy `local_env.sh.example` to `local_env.sh` to set environment for every
dispatched role.
