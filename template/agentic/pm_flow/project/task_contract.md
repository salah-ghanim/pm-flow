# {{PROJECT_NAME}} Task Contract

Primary mission:

- {{PRIMARY_MISSION}}
- keep going until the project is assembled from validated section outcomes or explicitly stopped with evidence

## Agent hierarchy and context boundaries

Root project coordinator:

- owns the project objective, section boundaries, dependency graph, integration order, and final reconciliation
- reads the project plan, generated section registry, and bounded section handoffs
- does not absorb raw section transcripts, pending reviews, or developer conversations
- does not directly manage implementation assignments when a section PM owns them

Section PM sub-agent:

- owns one complete, well-isolated section
- starts without inherited root conversation history; in Codex collaboration use `fork_turns="none"`
- is seeded only with its generated `pm_prompt.md`
- may remain long-lived only for that section
- keeps detailed plans, evidence, and decisions in that section's `state.md`
- reads another section only through an explicitly required bounded handoff
- publishes a handoff of at most 500 words and 8192 bytes after material outcomes or blockers

Developer sub-agent:

- is fresh for every bounded engineering assignment
- starts without inherited section-PM conversation history; in Codex collaboration use `fork_turns="none"`
- receives only the objective, owned paths, constraints, acceptance checks, and minimum relevant files
- is never resumed or reused for another assignment
- returns changes and validation evidence to its section PM, not to the root coordinator

## Section definition

Before launching a section PM, the section brief must contain these exact
Markdown headings:

```markdown
## Objective
## Scope
## Owned paths
## Dependencies
## Acceptance
## Rejection conditions
```

`Owned paths` must contain repo-relative bullets and cannot contain `..`.
Section creation rejects path prefixes or globs that overlap any nonterminal
section.

Each `Dependencies` bullet must be an exact existing section key or the
repo-relative path to that section's `handoff.md`. Use `- None.` when there are
no dependencies. Every pending review receives a snapshot copy of each declared
dependency handoff; it must not substitute another section's live state or
transcript.

Sections may run independently only when their write ownership does not overlap.
Shared interfaces must be reconciled by the root coordinator before conflicting
work proceeds.

## What counts as progress

- a concrete change or decision that directly advances the active section objective
- validation evidence that proves a candidate should be kept or rejected
- a negative result that kills a weak path quickly and with evidence
- a bounded handoff that enables a dependent section or root-level integration
- a process fix only when it is strictly required to unblock the same task cycle

What does not count as progress by itself:

- documentation only
- generic cleanup unrelated to the section objective
- workflow polish not used in the same cycle
- observations without a decision or validation outcome
- context accumulation or transcript summarization with no handoff decision
- side quests outside the section brief

## Acceptance rule for a candidate

1. identify the exact source of the idea or requirement
2. state the one-sentence hypothesis or expected gain
3. delegate the smallest implementation needed to test it to a fresh developer sub-agent
4. validate against the current baseline or explicit success criteria
5. keep it only when observed results support the hypothesis

## Anti-drift and isolation rules

- do not expand a section without escalating the boundary change through its handoff
- do not silently replace a section objective with a different one
- do not let a section PM coordinate unrelated sections
- do not reuse a developer conversation, even for a closely related next assignment
- do not feed section transcripts or developer conversations into the root context
- do not use automatic context compaction as the project continuation mechanism
- checkpoint explicitly in `state.md` and `handoff.md`, then launch a fresh agent when a boundary changes
- do not continue a failed path after a clean negative result without one explicit, evidence-based exception
- do not assume network or DNS problems before considering sandbox or wrapper issues
- prefer stable approved wrappers over ad hoc command shapes

## Review and handoff rules

Every proposed engineering step must state:

- alignment with the section objective
- the direct expected outcome
- owned paths and interface impact
- validation to run
- rejection criteria

Every section PM review must include:

- whether drift is happening
- the main risk
- whether the next step is `GO`, `GO_WITH_CHANGES`, or `NO_GO`
- the next bounded assignment for a fresh developer sub-agent

Every completion review must include:

- expected versus observed outcome
- whether drift happened
- interface changes exposed to other sections
- whether the result is `DONE`, `FOLLOW_UP`, or `REWORK`

Every root-facing section handoff must be at most 500 words and 8192 bytes and
contain exactly these information categories:

- Outcome
- Decisions
- Interfaces
- Risks
- Next action

## Pending review lifecycle

- only one pending review may be active for a section
- preparing another review fails until the active review is recorded or cancelled
- the generated Claude command and Codex fallback atomically claim execution before calling the PM
- an execution claim is one-time; duplicate PM execution for that pending review is refused
- `cancel-pending` releases abandoned work; after execution was claimed it also clears and advances the PM session because remote state may have changed
- `rotate-session` refuses to rotate while pending work is active
- `adopt-pending` upgrades one still-current legacy prepared review without repeating an already completed PM call

## Completion and reopening

- a `done` handoff requires the latest recorded completion decision to be exactly `DONE`
- no PM activity may have occurred after that `DONE` review, and no pending review may be active
- `DONE` still requires a bounded `done` handoff before the root treats the section as complete
- `done` and `cancelled` are terminal for PM review preparation
- publish an `active` or `planned` handoff before deliberately reopening a terminal section
- after new PM activity, a later `done` transition requires a new current `DONE` completion review

## Permissions and execution

- prefer repo-local wrappers before ad hoc commands
- stabilize repeated permission-sensitive command families with a wrapper
- when sandboxed execution fails on networked work, retry through the approved outside-sandbox wrapper before diagnosing infrastructure
- Claude PM commands run from the top shell through `./agentic/pm_flow/net_exec.sh`
- the prepared `command.txt` remains the source of truth for Claude invocation shape

Current baseline or reference:

- {{CURRENT_BASELINE}}
