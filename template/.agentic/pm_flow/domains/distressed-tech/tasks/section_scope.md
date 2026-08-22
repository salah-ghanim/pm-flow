---

# Task: scope the next assignment

You own desk `{{SECTION_KEY}}`. Decide what happens next in it.

Read:

{{CONTEXT_FILES}}

Cycle {{CYCLE}} of this desk. The history above includes every previous
assignment, result, and review. Read the most recent review first: if it asked
for changes, the next assignment addresses them.

Decide one of three things.

**The desk still needs work.** Write the next assignment. It must be the
smallest unit that produces a verifiable record — one target, or one sweep of
one source over one window — and it must state: the objective in one sentence,
the paths the analyst may write, which existing records must be reused rather
than re-fetched, the acceptance check, and what would make you reject the
result. Do not restate the desk brief; scope one concrete piece of it.

Only the Assignment, Acceptance, and Rejection conditions sections reach the
analyst. Everything you write above them is for you and for the record.

An assignment that cannot fail is not an assignment. Name the facts to be
established and the standard of evidence for each, so that "no public source
names the administrator" is a legitimate way to satisfy it and a plausible
guess is not.

**The desk is finished.** Every acceptance criterion in the brief is met and the
evidence is in the reviews above. Do not claim this because progress has stalled
or because the remaining sources are tedious — that is what escalation is for.

**The desk cannot be closed from here.** An acceptance criterion in the brief
requires something no assignment you can write will ever produce: a document
behind an NDA or a signature, a register that does not publish this class of
record at all, a deadline that has not yet arrived, an outcome the estate has
not yet decided. Say so instead of assigning another cycle that also cannot
close. This is not an escape from difficulty — difficulty is what escalation is
for. Name the dependency and what would unblock it on the decision line itself;
a bare token is rejected.

Before you answer that a desk is externally blocked, test that the dependency is
unmet right now and say what you ran. Fetch the register, the notice, the
listing, and paste what came back. A blocker you inherited from an earlier
report is not a blocker you have observed, and in this domain the thing that
changes fastest is exactly what earlier reports called unavailable: a proceeding
that published nothing at the filing usually publishes everything at the
opening.

Before you respond, check that the last accepted cycle was committed. If your
desk's owned paths, `state.md` or `handoff.md` have uncommitted changes from
work already accepted, commit them now — the next analyst starts fresh and
cannot recover what an interrupted process leaves behind.

## Respond with these sections only, each as a Markdown heading

1. Where the desk stands
2. Assignment
3. Acceptance
4. Rejection conditions
5. Decision

If the desk is finished or externally blocked, write `Not applicable.` under
Assignment, Acceptance, and Rejection conditions.

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: ASSIGN, COMPLETE, BLOCKED_EXTERNAL. A short
justification may follow the token on the same line, and BLOCKED_EXTERNAL
requires one: name the external dependency and what would unblock it.
