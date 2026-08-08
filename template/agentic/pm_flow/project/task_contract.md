# {{PROJECT_NAME}} Task Contract

Primary mission:

- {{PRIMARY_MISSION}}
- keep going until the product is assembled from validated section outcomes, or
  stop with evidence that it cannot be

## Roles and context boundaries

Every role runs as its own process with no inherited conversation. Continuity
lives in files, never in a chat history, and no role reads another role's raw
output except through the artifacts named below.

Product officer:

- owns the product objective, the section graph, the dependency order, section
  priority, and integration
- takes its ground truth from the mission and the committed evidence, never from
  the reports below it
- reads the project plan, its own portfolio log, the generated section registry,
  and bounded section handoffs, and treats every handoff as a claim to check
- probes rather than browses: one bounded question per completion criterion,
  answered MET or NOT MET
- reviews the whole portfolio on a cadence, and may CUT or BLOCK a section
- decides between consultant proposals when a section has failed repeatedly
- does not implement, and does not manage developers directly

Section manager:

- owns one complete, well-isolated section
- scopes each assignment: objective, owned paths, what to reuse, the acceptance
  check, and the rejection conditions
- reviews the returned evidence rather than the developer's summary
- keeps durable detail in that section's `state.md`
- reports upward only through a handoff of at most 500 words and 8192 bytes
- reads another section only through an explicitly required bounded handoff

Developer:

- is fresh for every assignment and is never reused
- receives only the objective, owned paths, constraints, acceptance checks, and
  the minimum relevant files
- reuses what already exists, and restructures rather than duplicating
- returns changes plus real validation output, not a description of it
- reports progress to its heartbeat file as it works

Consultant panel:

- convened when a section fails repeatedly, never as a routine review
- each seat answers the same brief independently and cannot see the others
- diagnoses the real obstacle, considers established practice before inventing,
  and proposes alternatives that could deliver the section's value differently

Rescue engineer:

- the project's last engineering attempt at a capability
- receives the original assignment, the failed work, why it failed, and the
  chosen path
- delivers that path fully, and stops only for a structural reason it can state

## Section definition

A section brief must contain these exact Markdown headings:

```markdown
## Objective
## Scope
## Priority
## Owned paths
## Dependencies
## Acceptance
## Rejection conditions
```

`Priority` is one bullet: `must-have` or `nice-to-have`, then one line naming
what the product loses without this section. It belongs to the product officer;
a section manager does not promote its own section. A section created before
priorities existed reads as `must-have`.

`Owned paths` must be repo-relative and cannot contain `..`. Sections may run
concurrently, so two sections must never be able to write the same file;
creation rejects any overlap with a section that is not terminal.

Each `Dependencies` bullet is an exact existing section key or the repo-relative
path to its `handoff.md`. Use `- None.` when there are none.

## What counts as progress

- a concrete change or decision that advances the section objective
- validation evidence that proves a candidate should be kept or rejected
- a negative result that kills a weak path quickly and with evidence
- a bounded handoff that unblocks a dependent section or integration

What does not count:

- documentation alone
- cleanup unrelated to the section objective
- observations without a decision or a validation outcome
- side quests outside the section brief

## Version control

Work that is not committed does not exist. Every role runs as its own process
with a fresh context, so an uncommitted tree is lost the moment a process is
killed, a worktree is cleaned, or the next agent starts.

- The section manager commits after every accepted result. An applied `GO` or
  `GO_WITH_CHANGES` is the commit point; a `NO_GO` is not.
- A commit covers that section's owned paths together with its `state.md` and
  `handoff.md`, so the work and the record of the work move as one.
- Commit only your own owned paths. Sections run concurrently, and a commit that
  reaches across boundaries picks up another section's half-finished work.
- The message names the section key and what the cycle established, negative
  results included.
- The product officer commits at the same cadence for product state: after
  decomposition, after any boundary or dependency change, and after every
  adjudication or abandonment decision.
- Follow the branch and push policy the repository already states. Do not invent
  a branching scheme for the flow.

## Decisions

Each role answers with one token on its decision line, optionally followed by a
short justification:

- section scoping: `ASSIGN`, `COMPLETE`, or `BLOCKED_EXTERNAL`
- developer: `DELIVERED`, `PARTIAL`, or `BLOCKED`
- review: `GO`, `GO_WITH_CHANGES`, or `NO_GO`
- convergence review: `CONTINUE`, `RESCOPE`, `BLOCKED_EXTERNAL`, or `ABANDON`
- portfolio review, per section: `CONTINUE`, `RESCOPE`, `CUT`, or `BLOCK`
- portfolio review, for the product: `ON_TRACK` or `OFF_TRACK`
- consultant: `ALTERNATIVE`, `RETRY_INFORMED`, or `ABANDON`
- adjudication: `ADOPT`, `ADOPT_PARALLEL`, `SYNTHESIZE`, or `ABANDON`
- rescue: `DELIVERED` or `BLOCKED`

A review must not soften a rejection to keep things moving. Repeated failure is
handled by escalation, not by lowering the bar.

`BLOCKED_EXTERNAL` is for an acceptance criterion that no assignment the role
can write will ever satisfy, because it needs credentials, a live external
system, market hours, weeks of elapsed wall clock, or a human signature. It must
name the dependency and what would unblock it. It is not for difficulty.

It also must name the probe that established the dependency is unmet **right
now**, and paste what that probe printed. A dependency is not blocking until
something observed says so. Where the property cannot be read directly, test the
behaviour it governs instead: a permission that forbids an action is settled by
attempting the action on the smallest reversible target, an entitlement by
requesting the data and reading the error, a service by reaching it. "It cannot
be read" is a statement about reading, not about knowing, and the two are not
interchangeable. A blocker asserted without a probe is an inference, and a role
that records an inference as a finding has failed its own standard.

A portfolio verdict takes effect immediately. `CUT` cancels the section and the
product is reconciled without it; `BLOCK` stops it being dispatched until it is
deliberately reopened; `RESCOPE` states what has to change and reaches the
section's next scope call. `RESCOPE`, `CUT` and `BLOCK` must each state a
reason, because the reason is what is recorded against the section.

A verdict the driver cannot read is recorded as `UNPARSED` and counts as a
failure, so a formatting miss is never cheaper than an honest rejection.

## Access

Roles are dispatched in one of three tiers:

- `write` - the building roles; the repository is theirs to change
- `scoped` - the managing roles; they may write their own project or section
  workspace, run git, and run the acceptance check, but not write source
- `read` - everyone else

Tiers are enforced by the backend where the backend can express them, and stated
in the role prompt in every case.

## Money

Every dispatch records what it cost. The run is governed on the sum through
`budget.max_usd` and `budget.max_usd_per_section`, not only on a tick count,
because a tick's cost varies by more than an order of magnitude and rises with
cycle depth.

## Governance

The product officer reviews the whole portfolio on a cadence, not only when
something fails. Whichever of these fires first convenes one: `governance`
`portfolio_review_dispatches` since the last review, `portfolio_review_usd` of
project spend since the last one, or `portfolio_review_idle_cycles` cycles
across the project with no section reaching `done`. Project-level work preempts
section work, because there is always a section willing to scope one more cycle.

Each review asks what the product still lacks, settles every completion
criterion by its own probe, checks the plan's own structure for an unstarted
dependency, an unreachable section, must-have inflation and linear-chain risk,
and answers per section and for the product. It appends to
`project_state/portfolio_log.md`, which is the officer's only memory across
dispatches.

## Failure and escalation

- consecutive rejections are counted from the section's own cycle history
- reaching the configured threshold sends the section to the consultant panel
  with everything that was attempted and observed
- the product officer may adopt one path, several in parallel, a synthesis, or
  abandon the section
- a rescue that fails review consumes a round; when the rounds are spent the
  section is abandoned rather than escalating forever
- abandoning is a product decision and must state what the product loses

## Evidence

Narrative is a claim; an artifact is a fact. A handoff, a result and a review are
all narrative, however confident they read. What settles a criterion is the
observable it names, probed by whoever needs the answer.

- The product officer never reads transcripts, developer results, reviews, scope
  responses or assignments, and never browses evidence in bulk. It asks bounded
  questions whose answers are one or two lines, one per completion criterion.
- A criterion is met when the officer's own probe says so, never because a
  manager reported it.
- The officer may make the product smaller, visibly, and may never make the
  evidence weaker, quietly. Reducing a section's scope is a dated
  `## Reduced scope, authorized <date>` heading appended to its brief, naming
  what was cut and what the product no longer guarantees. The original
  Acceptance bullets stay.
- The dependency graph changes only through `pm_flow.sh section-dependencies`,
  which validates existence, cycles and ownership overlap.
- Cycle artifacts are the audit trail. The officer never writes them.

## Handoffs

Every section handoff is at most 500 words and 8192 bytes and contains exactly:

- Outcome
- Decisions
- Interfaces
- Risks
- What is unproven
- Next action

`What is unproven` lists every capability the section claims that has not been
demonstrated against the real thing, and the observation that would settle each
one. `- None` is a legitimate answer that has to be defensible. It is what the
portfolio review reads first and is required to address section by section.

A `done` handoff requires a recorded completion decision for that section.
`done` and `cancelled` are terminal; publish an `active` or `planned` handoff to
reopen a section deliberately.

## Anti-drift rules

- do not expand a section without escalating the boundary change through its
  handoff
- do not silently replace a section objective with a different one
- do not let one section manager coordinate another section
- do not reuse a developer conversation, even for a closely related assignment
- do not feed raw section detail into the product officer's context
- do not rely on automatic context compaction; checkpoint to `state.md` and
  `handoff.md` and let the next process start fresh
- do not continue a failed path after a clean negative result without one
  explicit, evidence-based exception
- prefer stable repo-local wrappers over ad hoc command shapes

Current baseline or reference:

- {{CURRENT_BASELINE}}
