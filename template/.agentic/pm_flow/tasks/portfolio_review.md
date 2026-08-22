---

# Task: review the portfolio against the mission

This is a recurring product review, not a section review. Since the last one the
project has spent {{SPEND_SINCE}} across {{DISPATCHES_SINCE}} dispatch(es) and
{{CYCLES_SINCE}} section cycle(s), and {{DONE_SECTIONS}} section(s) are done.

Read, in this order:

{{CONTEXT_FILES}}

The plan is the mission. `portfolio_log.md` is your own memory of every previous
review of this project, and you are a fresh process with none of it: read it
before you read a single word of section reporting. It is the only way to see
that a section has been nearly done for four reviews running, or that the
shortest path has not changed in three.

## Hold one question for the whole review

**What does the product still lack?** Never "how are the sections doing" - a
project can be busy in every section and lack everything.

## Evidence, not narrative

Your ground truth is the mission and the committed evidence in the repository.
It is not the reports from below. A product officer who forms its view from its
subordinates' summaries has been captured by them.

Narrative is a claim. An artifact is a fact.

- You must **not** read section transcripts, developer results, reviews, scope
  responses or assignments. That ban is absolute. It is narrative, reading it is
  how capture happens, and it does not fit in your context anyway.
- A section handoff is a claim to be checked, not a fact to be accepted. Read
  each section's `What is unproven` and address it explicitly. What a section
  admits it has not proven is the project's real remaining distance, whatever
  its outcome line says.

## You probe. You do not browse.

Check artifacts by asking the repository bounded questions whose answers are one
or two lines. Do not read through evidence files, logs, or code: your judgement
depends on holding the whole product at once, and that only survives in a
context that stays small.

One probe per completion criterion. Each answers MET or NOT MET on its own:

- does the file this criterion names exist - `ls <path>`
- does the named command exit 0 - run it and read the last line
- has this path ever been touched - `git log --oneline -1 -- <path>`
- does the artifact contain the observable the criterion names - one `grep`

A criterion is never met because a manager said so. If a criterion names no
observable you can probe, that is a finding about the plan; say so and fix the
plan.

## Unknown is a task, not a verdict

The probes above read the repository. Most of what blocks a product is not in
the repository: a setting inside an external system, a permission, an
entitlement, whether a remote endpoint answers. You will be told these are
unknowable. Usually they are only unreadable, and those are different claims.

Before you record anything as unknown or blocked, do this in order:

1. **Say what would be different if it were true, versus false.** If nothing
   observable differs, it does not block anything and you can stop worrying
   about it. If something does differ, that difference is your probe.
2. **Test the difference, not the setting.** You often cannot inspect a
   property. You can almost always exercise the behaviour it governs. A flag
   that forbids an action is proved by attempting the action; an entitlement is
   proved by requesting the data and reading the error; a service being reachable
   is proved by reaching it. Choose the smallest, safest, most reversible action
   that would come out differently under each answer.
3. **Ask why it is blocked before accepting that it is.** A stated blocker is
   often a proxy for the real one, or is stale, or was inherited from a report
   nobody retested. Check whether the thing said to be missing is actually
   missing right now.
4. **Look for the answer somewhere else in the evidence.** A question one
   section calls open is often already answered in an artifact another section
   committed. Search before you escalate.

"The setting is stored encrypted so no probe can read it" is a correct statement
about reading and a false conclusion about knowing. If the setting governs
whether an action succeeds, attempt the action.

You may not record `BLOCKED` or carry a dependency as unmet without naming the
probe you ran and pasting what it printed. A blocker without a probe is an
inference, and an inference recorded as a finding is the specific failure this
review exists to prevent. The same standard you apply to every section applies
to your own report.

Run each probe as one plain command. Your tier allows commands by prefix, so a
compound line - anything with `cd ... &&`, a `for` loop, or a leading `timeout` -
matches no rule and is refused. Use `git -C <dir>` instead of changing
directory, and run the loop's iterations as separate commands.

If a command is refused, that is a fact about that exact command and nothing
else. Do not generalize from one refusal to a capability you did not test, and
never record an untested inference as a finding. Your own report is held to the
standard you hold every section to: state what you ran and what it printed.

## Then check the plan itself

You are accountable both for everyone working on the plan and for the plan being
structured so it can actually be finished. Four failure modes have each cost a
project in this repository, and nothing checks for them after decomposition:

- **Unstarted dependency.** A section waiting on a dependency with zero cycles.
  Four sections once waited on one that was never dispatched at all. Either
  reprioritize the blocker or restructure so work can start.
- **Unreachable section.** A section whose acceptance names an artifact no
  section owns, or that depends on something outside every agent's reach. This
  is the defect that costs a project its whole spend without closing anything.
- **Must-have inflation.** A section marked `must-have` whose absence the
  product could actually survive. You own that judgement. A manager does not get
  to promote its own section's priority.
- **Linear-chain risk.** A dependency chain deep enough that nothing can proceed
  in parallel and one failure stalls everything behind it.

## Then judge each section

For every live section give exactly one verdict. Weigh its declared priority: a
`nice-to-have` consuming the project's spend while a `must-have` criterion sits
untouched is the clearest cut in the list.

- `CONTINUE` - it is buying real ground toward an unmet criterion
- `RESCOPE` - it can produce value but not on its current acceptance criteria;
  state what has to change, concretely enough for its manager to act on it
- `CUT` - the product reaches its completion criteria without this section, or
  it cannot pay for itself; say what the product loses
- `BLOCK` - it cannot proceed from inside the flow until an external dependency
  lands; name the dependency and what would unblock it

`CUT` and `BLOCK` take effect the moment you write them: `CUT` cancels the
section, `BLOCK` stops it being dispatched until it is deliberately reopened.
Killing a side quest early and explicitly is your job, and it is cheaper than
every cycle it would otherwise buy.

## What you may change, and how

You may make the product smaller, visibly. You may never make the evidence
weaker, quietly.

- `plan.md`, `portfolio_log.md` and any `priority.txt` are yours to edit
  directly.
- **The plan carries the current position. The log carries the history.** Write
  this review's narrative, findings and reasoning to `portfolio_log.md`. In
  `plan.md`, edit the state to what is true now: replace the previous position
  rather than prepending to it, and delete what a later probe has settled.
  Nothing in the plan should begin "at review 004" - if it still matters, it is
  current and says so without a date; if it does not, it belongs in the log.
- Write both to the standard in the task contract under "How to write". State
  the finding and its evidence; do not narrate the review. Never leave a
  superseded position in place "for the record" - git history and the log are
  the record.
- The same applies to a `brief.md` you amend. State the change, do not restate
  the section.
- Changing the dependency graph goes through
  `pm_flow.sh section-dependencies <key> --file <markdown>`, never a hand edit
  of `dependency_handoffs.txt`. The command validates that every named section
  exists, that no cycle is created, and that ownership still does not overlap.
- Reducing a section's scope is allowed as a dated, visible reduction. Append to
  its `brief.md` a heading `## Reduced scope, authorized <date>` naming exactly
  what was cut, what the product no longer guarantees as a result, and a
  matching rejection condition binding its reviewer, of the form: "A review that
  rejects delivered work solely for omitting one of the requirements named under
  Reduced scope." Do not edit or delete the original Acceptance bullets. The
  diff must show what was given up, and the same reduction goes in the log.
- Never write a section's owned source paths, and never write cycle artifacts.
  The cycle record is the audit trail, and an officer who can rewrite it cannot
  be checked against it.

## Respond with these sections only, each as a Markdown heading

1. What the product still lacks
2. Completion criteria
3. Evidence I probed
4. Plan structure
5. Verdicts
6. Shortest path
7. Decision

`Completion criteria` lists every criterion from the plan, one per line, each
ending in `MET` or `NOT MET` and the probe you ran.

`Evidence I probed` names the commands and what they returned, one line each.
Name what you looked for and did not find as well; a missing artifact under a
confident handoff is the most valuable line in this review.

`Plan structure` is exactly four lines, each `FOUND` with what you found, or
`CLEAR`:

```
- Unstarted dependency: CLEAR
- Unreachable section: FOUND <which section, and what it cannot reach>
- Must-have inflation: CLEAR
- Linear-chain risk: FOUND <the chain, and what it stalls>
```

`Verdicts` is one line per live section, in exactly this shape:

```
- <section-key>: <VERDICT> <reason>
```

The reason is required for `RESCOPE`, `CUT` and `BLOCK`, and it is recorded
against the section, so write it for whoever reads it next rather than for this
review. Use the exact section keys from the registry.

`Shortest path` answers two questions in plain words: what is the shortest path
to the next unmet completion criterion, and is the work currently in flight on
that path?

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens:

- `ON_TRACK` - the work in flight is on the shortest path you just described
- `OFF_TRACK` - it is not, and the verdicts above are what redirect it

A short justification may follow the token on the same line.
