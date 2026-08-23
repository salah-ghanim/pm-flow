---

# Task: review the portfolio against the mission

A recurring product review, not a section review. Since the last one the
project spent {{SPEND_SINCE}} across {{DISPATCHES_SINCE}} dispatch(es) and
{{CYCLES_SINCE}} section cycle(s); {{DONE_SECTIONS}} section(s) are done.

Read, in this order:

{{CONTEXT_FILES}}

`portfolio_log.md` is your memory of every previous review; read it before any
section report. Hold one question throughout: **what does the product still
lack?** A project can be busy in every section and lack everything.

## Evidence

The mission and the committed artifacts are your ground truth; reports from
below are claims. Do not read section transcripts, developer results, reviews,
scope responses or assignments. Read each handoff's `What is unproven` and
address it explicitly.

Probe rather than browse: one bounded question per completion criterion, each
answering `MET` or `NOT MET` on its own - `ls <path>`, a command's exit status,
`git log --oneline -1 -- <path>`, one `grep`. Run each probe as one plain
command: a compound line (`cd … &&`, a loop, a leading `timeout`) is refused,
so use `git -C <dir>` and separate commands. A refusal is a fact about that
exact command and nothing else.

Before recording anything as unknown or blocked: say what would differ if it
were true versus false; test that difference by the smallest safe action
rather than inspecting the setting; check whether the stated blocker is still
real; search the evidence other sections committed. You may not record `BLOCK`
or an unmet dependency without naming the probe you ran and what it printed.

## The plan itself

Report each of these as `FOUND <detail>` or `CLEAR`:

- **Unstarted dependency** - a section waiting on one with zero cycles.
- **Unreachable section** - acceptance names an artifact no section owns, or
  something outside every agent's reach.
- **Must-have inflation** - a `must-have` the product could survive without.
- **Linear-chain risk** - a chain deep enough that one failure stalls
  everything behind it.

## Verdicts

One per live section, weighing its declared priority:

- `CONTINUE` - buying real ground toward an unmet criterion
- `RESCOPE` - can produce value, not on its current acceptance; say what changes
- `CUT` - the product completes without it, or it cannot pay for itself
- `BLOCK` - cannot proceed until an external dependency lands; name it

`CUT` and `BLOCK` take effect as written.

## What you may change

- `plan.md`, `portfolio_log.md` and any `priority.txt`, directly. The plan
  holds the current position, replaced rather than prepended; the log holds
  this review's findings and reasoning. Nothing in the plan begins "at review
  NNN".
- The dependency graph, only through `pm_flow.sh section-dependencies <key>
  --file <markdown>`.
- A section's scope, only as a visible reduction: append to its `brief.md` a
  heading `## Reduced scope, authorized <date>` naming what was cut, what the
  product no longer guarantees, and a rejection condition that binds its
  reviewer not to reject work for omitting it. The original Acceptance bullets
  and their IDs stay in place, and the same reduction goes in the log.
- Never a section's owned source paths or its cycle artifacts.

## Respond with these sections only, each as a Markdown heading

1. What the product still lacks
2. Completion criteria - every plan criterion, one per line, ending `MET` or
   `NOT MET` with the probe
3. Evidence I probed - one line per command and what it returned, including
   what you looked for and did not find
4. Plan structure - exactly four lines: `- <defect>: CLEAR` or
   `- <defect>: FOUND <detail>`
5. Verdicts - one line per live section, `- <section-key>: <VERDICT> <reason>`,
   the reason required for `RESCOPE`, `CUT` and `BLOCK`
6. Shortest path - to the next unmet completion criterion, and whether the work
   in flight is on it
7. Decision - one line beginning `ON_TRACK` or `OFF_TRACK`, optionally
   followed by a short reason
