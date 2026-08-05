---

# Task: scope the next assignment

You own section `{{SECTION_KEY}}`. Decide what happens next in it.

Read:

{{CONTEXT_FILES}}

Cycle {{CYCLE}} of this section. The history above includes every previous
assignment, result, and review. Read the most recent review first: if it asked
for changes, the next assignment addresses them.

Decide one of two things.

**The section still needs work.** Write the next assignment. It must be the
smallest change that produces evidence, and it must state: the objective in one
sentence, the paths the developer may write, what already exists that should be
reused rather than rebuilt, the acceptance check and how to run it, and what
would make you reject the result. Do not restate the section brief; scope one
concrete piece of it.

**The section is finished.** Every acceptance criterion in the brief is met and
the evidence is in the reviews above. Do not claim this because progress has
stalled or because the remaining work is awkward — that is what escalation is
for.

Before you respond, check that the last accepted cycle was committed. If your
section's owned paths, `state.md` or `handoff.md` have uncommitted changes from
work already accepted, commit them now — the next developer starts fresh and
cannot recover what an interrupted process leaves behind.

## Respond with these sections only, each as a Markdown heading

1. Where the section stands
2. Assignment
3. Acceptance
4. Rejection conditions
5. Decision

If the section is finished, write `Not applicable.` under Assignment,
Acceptance, and Rejection conditions.

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: ASSIGN, COMPLETE. A short justification may
follow the token on the same line.
