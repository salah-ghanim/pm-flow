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

Do not soften a rejection to keep things moving. A wrong result that is accepted
becomes the next section's problem, and this project escalates repeated failure
to a consultant rather than expecting you to absorb it.

## Respond with these sections only, each as a Markdown heading

1. Assessment
2. Drift review
3. Evidence check
4. Risks
5. Decision

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: GO, GO_WITH_CHANGES, NO_GO. A short
justification may follow the token on the same line.
