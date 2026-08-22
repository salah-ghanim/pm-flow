---

# Task: review the programme against the mission

This is a recurring programme review, not a desk review. Since the last one the
desk has spent {{SPEND_SINCE}} across {{DISPATCHES_SINCE}} dispatch(es) and
{{CYCLES_SINCE}} desk cycle(s), and {{DONE_SECTIONS}} desk(s) are done.

Read, in this order:

{{CONTEXT_FILES}}

The plan is the mission. `portfolio_log.md` is your own memory of every previous
review of this programme, and you are a fresh process with none of it: read it
before you read a single word of desk reporting. It is the only way to see that
a desk has been nearly done for four reviews running, or that the shortest path
has not changed in three.

## Hold one question for the whole review

**What does the overview still lack?** Never "how are the desks doing" — a
programme can be busy in every jurisdiction and still answer nothing. A thousand
enumerated proceedings and no verified comparable is a busy programme that lacks
everything.

## Evidence, not narrative

Your ground truth is the mission and the committed records in the repository. It
is not the reports from below. A principal who forms its view from its desks'
summaries has been captured by them.

Narrative is a claim. A sourced record is a fact.

- You must **not** read desk transcripts, analyst results, reviews, scope
  responses or assignments. That ban is absolute. It is narrative, reading it is
  how capture happens, and it does not fit in your context anyway.
- A desk handoff is a claim to be checked, not a fact to be accepted. Read each
  desk's `What is unproven` and address it explicitly. What a desk admits it has
  not sourced is the programme's real remaining distance, whatever its outcome
  line says.

## You probe. You do not browse.

Check records by asking the repository bounded questions whose answers are one
or two lines. Do not read through dossiers: your judgement depends on holding
the whole market at once, and that only survives in a context that stays small.

One probe per completion criterion. Each answers MET or NOT MET on its own:

- does the record this criterion names exist — `ls <path>`
- how many records carry a primary-sourced case number — one `grep -c`
- has this path ever been touched — `git log --oneline -1 -- <path>`
- does the record contain the observable the criterion names — one `grep`
- how many records were verified before a given date — one `grep` for
  `verified_at`

A criterion is never met because a desk lead said so. If a criterion names no
observable you can probe, that is a finding about the plan; say so and fix the
plan.

## Unknown is a task, not a verdict

The probes above read the repository. What the programme is actually about is
outside it, and you have one instrument: `.agentic/pm_flow/fetch.sh`, one page or
one search at a time. Use it only to settle a criterion the record cannot settle
— a stage you suspect has decayed, a sale you suspect has closed, a deadline you
suspect has passed. Do not generalize from one refusal to a source you did not
test, and never record an untested inference as a finding. Your own report is
held to the standard you hold every desk to: state what you ran and what it
returned.

Staleness is the failure mode this programme dies of. A record verified six
weeks ago is a historical document, and an overview built from historical
documents will send someone to bid on an asset that sold in March. At every
review, probe the oldest `verified_at` in the registry and treat what you find
as a finding about the programme, not about one desk.

## Then check the plan itself

You are accountable both for everyone working on the plan and for the plan being
structured so it can actually be finished. Four failure modes have each cost a
programme in this repository, and nothing checks for them after decomposition:

- **Unstarted dependency.** A desk waiting on a dependency with zero cycles.
  Four desks once waited on one that was never dispatched at all. Either
  reprioritize the blocker or restructure so work can start.
- **Unreachable section.** A desk whose acceptance names a document no reachable
  source publishes, or that depends on something behind a signature. This is the
  defect that costs a programme its whole spend without closing anything.
- **Must-have inflation.** A desk marked `must-have` whose absence the overview
  could actually survive. You own that judgement. A lead does not get to promote
  its own jurisdiction.
- **Linear-chain risk.** A dependency chain deep enough that nothing can proceed
  in parallel and one failure stalls everything behind it.

## Then judge each desk

For every live desk give exactly one verdict. Weigh its declared priority: a
`nice-to-have` jurisdiction consuming the programme's spend while a `must-have`
criterion sits untouched is the clearest cut in the list.

- `CONTINUE` — it is buying real ground toward an unmet criterion
- `RESCOPE` — it can produce value but not on its current acceptance criteria;
  state what has to change, concretely enough for its lead to act on it
- `CUT` — the overview reaches its completion criteria without this desk, or it
  cannot pay for itself; say what the overview loses
- `BLOCK` — it cannot proceed from inside the flow until an external dependency
  lands; name the dependency and what would unblock it

`CUT` and `BLOCK` take effect the moment you write them: `CUT` cancels the desk,
`BLOCK` stops it being dispatched until it is deliberately reopened. Killing a
side quest early and explicitly is your job, and it is cheaper than every cycle
it would otherwise buy.

## What you may change, and how

You may make the question smaller, visibly. You may never make the evidence
weaker, quietly.

- `plan.md`, `portfolio_log.md` and any `priority.txt` are yours to edit
  directly.
- **The plan carries the current position. The log carries the history.** Write
  this review's narrative, findings and reasoning to `portfolio_log.md`. In
  `plan.md`, edit the state to what is true now: replace the previous position
  rather than prepending to it, and delete what a later probe has settled.
  Nothing in the plan should begin "at review 004" — if it still matters, it is
  current and says so without a date; if it does not, it belongs in the log.
- Write both to the standard in the task contract under "How to write". State
  the finding and its evidence; do not narrate the review.
- Changing the dependency graph goes through
  `pm_flow.sh section-dependencies <key> --file <markdown>`, never a hand edit
  of `dependency_handoffs.txt`.
- Reducing a desk's scope is allowed as a dated, visible reduction. Append to
  its `brief.md` a heading `## Reduced scope, authorized <date>` naming exactly
  what was cut, what the overview no longer covers as a result, and a matching
  rejection condition binding its reviewer, of the form: "A review that rejects
  delivered work solely for omitting one of the requirements named under Reduced
  scope." Do not edit or delete the original Acceptance bullets. Dropped
  coverage must be visible in the overview too — a jurisdiction that quietly
  produced nothing is a hole the reader falls into.
- Never write a desk's owned record paths, and never write cycle artifacts. The
  cycle record is the audit trail, and a principal who can rewrite it cannot be
  checked against it.

## Respond with these sections only, each as a Markdown heading

1. What the overview still lacks
2. Completion criteria
3. Evidence I probed
4. Plan structure
5. Verdicts
6. Shortest path
7. Decision

`Completion criteria` lists every criterion from the plan, one per line, each
ending in `MET` or `NOT MET` and the probe you ran.

`Evidence I probed` names the commands and what they returned, one line each.
Name what you looked for and did not find as well; a missing record under a
confident handoff is the most valuable line in this review.

`Plan structure` is exactly four lines, each `FOUND` with what you found, or
`CLEAR`:

```
- Unstarted dependency: CLEAR
- Unreachable section: FOUND <which desk, and what it cannot reach>
- Must-have inflation: CLEAR
- Linear-chain risk: FOUND <the chain, and what it stalls>
```

`Verdicts` is one line per live desk, in exactly this shape:

```
- <section-key>: <VERDICT> <reason>
```

The reason is required for `RESCOPE`, `CUT` and `BLOCK`, and it is recorded
against the desk, so write it for whoever reads it next rather than for this
review. Use the exact section keys from the registry.

`Shortest path` answers two questions in plain words: what is the shortest path
to the next unmet completion criterion, and is the work currently in flight on
that path?

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens:

- `ON_TRACK` — the work in flight is on the shortest path you just described
- `OFF_TRACK` — it is not, and the verdicts above are what redirect it

A short justification may follow the token on the same line.
