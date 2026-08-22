---

# Task: scope the next assignment

You own section `{{SECTION_KEY}}`. Decide what happens next in it.

Read:

{{CONTEXT_FILES}}

Cycle {{CYCLE}} of this section. The history above includes every previous
assignment, result, and review. Read the most recent review first: if it asked
for changes, the next assignment addresses them.

Decide one of three things.

**The section still needs work.** Write the next assignment. It must be the
smallest change that produces evidence, and it must state: the objective in one
sentence, the paths the developer may write, what already exists that should be
reused rather than rebuilt, the acceptance check and how to run it, and what
would make you reject the result. Do not restate the section brief; scope one
concrete piece of it.

Only the Assignment, Acceptance, and Rejection conditions sections reach the
developer. Everything you write above them is for you and for the record.

**The section is finished.** Every acceptance criterion in the brief is met and
the evidence is in the reviews above. Do not claim this because progress has
stalled or because the remaining work is awkward — that is what escalation is
for.

**The section cannot be closed from here.** An acceptance criterion in the brief
requires something no assignment you can write will ever produce: credentials,
a live external system, market hours, weeks of elapsed wall clock, or a human
signature. Say so instead of assigning another cycle that also cannot close.
This is not an escape from difficulty — difficulty is what escalation is for.
It is for work that is not blocked on effort at all. Name the dependency and
what would unblock it on the decision line itself; a bare token is rejected.

Before you respond, check that the last accepted cycle was committed. If your
section's owned paths, `state.md` or `handoff.md` have uncommitted changes from
work already accepted, commit them now — the next developer starts fresh and
cannot recover what an interrupted process leaves behind.

## What an acceptance criterion has to be

State the outcome in the running system, not the mechanism that produces it. A
criterion is only worth writing if failing it would mean the product is worse
off, and passing it would mean a user of this project can do something they
could not do before.

This is not style. `codex-usage` was accepted, marked done, and delivered
nothing usable. Its acceptance read "a Codex dispatch writes a non-empty
`.events.jsonl` beside its response" - a mechanism. It was met by a *fake*
codex emitting a key real codex never sends, so every real dispatch recorded no
tokens at all; and the code that would have carried those tokens into the store
was never called, so even correct parsing would have reached nothing. Every
criterion passed. The feature did not exist.

So:

- Name the observable, not the artifact. Not "a file is written" but "`pm-flow
  cost` reports non-zero tokens for that dispatch". Not "the parser handles the
  schema" but "the recorded run shows the tokens the provider charged for".
- A section that integrates with an external tool is proven against that tool.
  A stub proves the stub. Where a real call cannot be made, say so in the
  criterion itself and name what would settle it, rather than letting a double
  stand in silently.
- End the chain where the project's own goal begins. `plan.md` says what this
  product is for; a criterion that stops short of it leaves the section
  disconnected, and a disconnected section can be complete and worthless at the
  same time.
- Prefer a criterion someone else could check without reading the diff.

## Respond with these sections only, each as a Markdown heading

1. Where the section stands
2. Assignment
3. Acceptance
4. Rejection conditions
5. Decision

If the section is finished or externally blocked, write `Not applicable.` under
Assignment, Acceptance, and Rejection conditions.

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: ASSIGN, COMPLETE, BLOCKED_EXTERNAL. A short
justification may follow the token on the same line, and BLOCKED_EXTERNAL
requires one: name the external dependency and what would unblock it.

Before you answer BLOCKED_EXTERNAL, test that the dependency is unmet right now
and say what you ran. If the thing cannot be read directly, exercise the
behaviour it governs instead - attempt the action a permission would forbid, on
the smallest reversible target, and read what comes back. Unreadable is not
unknowable, and a blocker you inherited from an earlier report is not a blocker
you have observed.
