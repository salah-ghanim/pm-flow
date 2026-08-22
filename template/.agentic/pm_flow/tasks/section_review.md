---

# Task: review a developer result

You own section `{{SECTION_KEY}}`. A developer has returned work for cycle
{{CYCLE}}. Judge it against the acceptance criteria you set, not against how
much effort it represents.

Read:

{{CONTEXT_FILES}}

Check the evidence, not the summary. A developer stating that tests pass is not
the same as test output showing it. If the acceptance check was not actually
run, that alone is a failure.

You share a model family with the developer you are reviewing, so reading the
code and agreeing with it is worth nothing. Two things substitute for that
missing independence, and both are required:

- **Run the acceptance check yourself and paste its real output into the
  review.** A claim about a library, an error code, or a behaviour enters the
  record only next to the command that produced it, in the same file.
- **Mutate the implementation and show the tests catch it.** Break one thing the
  change is supposed to guarantee, run the tests, and paste the failure. A test
  that cannot detect its own violation is not evidence, and reading it will not
  tell you which kind it is.

If either is impossible in this cycle, say which and why in the Evidence check
section rather than passing over it.

Do not soften a rejection to keep things moving. A wrong result that is accepted
becomes the next section's problem, and this project escalates repeated failure
to a consultant rather than expecting you to absorb it.

Do not commit. The driver commits an accepted cycle for you: it commits the
section's worktree, merges it back, and commits `state.md` and `handoff.md`
alongside. Your verdict is what triggers that, so the verdict is the whole of
your job here.

This used to be your obligation, and it was one some roles could not discharge:
a sandbox that denies writes to `.git` makes a commit impossible however the
permissions are written, and a reviewer then had to reject work whose every
criterion it had just confirmed, because it could not record the acceptance.
Never reject work for that reason. If something outside the work itself stops
you from finishing the review, say so under Evidence check and judge the work
on its merits.

## Respond with these sections only, each as a Markdown heading

1. Assessment
2. Drift review
3. Evidence check
4. Risks
5. Decision

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: GO, GO_WITH_CHANGES, NO_GO. A short
justification may follow the token on the same line.
