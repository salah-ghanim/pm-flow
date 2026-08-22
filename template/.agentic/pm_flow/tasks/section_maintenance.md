---

# Task: clear an obstruction blocking section `{{SECTION_KEY}}`

This section has failed {{FAILURES}} consecutive review(s), and the reviews say
the cause was the harness rather than the work. You are here to make the next
cycle possible. You are not here to do the cycle.

Read, in this order:

{{CONTEXT_FILES}}

The reviews and developer reports usually name the obstruction already. Start
from what they say, then confirm it yourself before changing anything.

## The boundary

You may change engine scripts, tooling, test harness, and configuration.

You may not change what this section was scoped to deliver, and you may not
change the acceptance it is judged against. If the obstruction turns out to be
the brief - too vague, internally contradictory, or asking for something that
cannot be built - that is not plumbing. Report it and stop; the product officer
decides those, and a consultant panel exists for them.

You may not defeat a gate. A sandbox refusal, a permission boundary, a write
control: work out what the harness should do differently so the boundary is
never hit, rather than finding a way past it. A bypass shipped here becomes a
bypass everyone inherits.

Append a one-line status to `{{HEARTBEAT_FILE}}` as you go:

`{{HEARTBEAT_SCRIPT}} {{HEARTBEAT_FILE}} "<what you just did>"`.

## Respond with these sections only, each as a Markdown heading

1. Obstruction
2. Cause
3. What I changed
4. Evidence
5. What I did not fix
6. Decision

**Obstruction** is one sentence a stranger could act on.

**Cause** says why what you changed is the cause and not a symptom. If you
widened a limit or retried something, say why the underlying thing could not be
made deterministic instead.

**Evidence** quotes the command that was failing, run again, passing. Its
absence means you have not finished.

**What I did not fix** is required and may not be empty prose. Name anything
you found and left, or write `Nothing found beyond the obstruction above.` A
harness that half-works while reporting success is paid for by the next section
without it knowing why.

The Decision section must contain exactly one line beginning with one of these
exact tokens:

- `CLEARED` - the obstruction is gone and the failing command now passes.
- `NOT_PLUMBING` - the cause is the brief or the design, not the harness. The
  section needs a product decision, not a repair.
- `UNRESOLVED` - it is a harness problem and you could not fix it. Say what you
  ruled out, so the next attempt does not repeat it.

A short justification follows the token on the same line.
