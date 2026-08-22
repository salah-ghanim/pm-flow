---

# Task: implement this assignment

You are implementing one bounded assignment in section `{{SECTION_KEY}}`,
cycle {{CYCLE}}.

Read:

{{CONTEXT_FILES}}

Append a one-line status to `{{HEARTBEAT_FILE}}` after each meaningful step: when
you finish reading the existing code, when you start implementing a component,
and when tests first pass. A run that goes silent is treated as hung and is
terminated, so keep it current.

Write it with the wrapper, which timestamps the line for you:
`{{HEARTBEAT_SCRIPT}} {{HEARTBEAT_FILE}} "<what you just did>"`.
Do not build the timestamp inline with `$(date ...)`; that is shell the
permission layer refuses, and a refused heartbeat reads as a silent run.

Stay inside the owned paths named in the assignment. If the work genuinely
requires touching something outside them, stop and report that instead of doing
it quietly.

## Respond with these sections only, each as a Markdown heading

1. What I changed
2. What I reused or restructured
3. Validation
4. What I could not do
5. Status

Paste the actual output of the acceptance check under Validation. Do not
describe it.

The Status section must contain exactly one line, and that line must begin with
one of these exact tokens: DELIVERED, PARTIAL, BLOCKED. A short justification
may follow the token on the same line.
