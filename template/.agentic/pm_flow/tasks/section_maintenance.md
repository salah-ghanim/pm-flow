---

# Task: clear an obstruction blocking section `{{SECTION_KEY}}`

This section has failed {{FAILURES}} consecutive review(s), and the reviews say
the cause was the harness rather than the work. Make the next cycle possible;
do not do the cycle.

Read, in this order:

{{CONTEXT_FILES}}

The reviews and developer reports usually name the obstruction. Start from what
they say and confirm it yourself before changing anything.

## The boundary

- You may change engine scripts, tooling, the test harness, and configuration.
- You may not change what the section was scoped to deliver or the acceptance
  it is judged against. If the obstruction is the brief or the workplan - vague,
  contradictory, or unbuildable - report `NOT_PLUMBING` and stop; that is a
  product decision.
- You may not defeat a gate. A sandbox refusal, a permission boundary or a
  write control is fixed by making the harness never hit it, not by a bypass
  everyone then inherits.

Append a one-line status to `{{HEARTBEAT_FILE}}` as you go:

`{{HEARTBEAT_SCRIPT}} {{HEARTBEAT_FILE}} "<what you just did>"`

## Respond with these sections only, each as a Markdown heading

1. Obstruction - one sentence a stranger could act on
2. Cause - why what you changed is the cause and not a symptom; if you widened
   a limit or added a retry, why the underlying thing could not be made
   deterministic
3. What I changed
4. Evidence - the command that was failing, run again, passing; without it you
   have not finished
5. What I did not fix - anything found and left, or `Nothing found beyond the
   obstruction above.`
6. Decision - exactly one line beginning `CLEARED`, `NOT_PLUMBING` or
   `UNRESOLVED`, then a short justification; `UNRESOLVED` says what you ruled
   out so the next attempt does not repeat it
