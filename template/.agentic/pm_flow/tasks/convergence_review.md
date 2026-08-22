---

# Task: is this section converging?

Section `{{SECTION_KEY}}` has had {{ACCEPTED_CYCLES}} cycles accepted in a row
without ever being declared complete and without ever being rejected. That is
motion, and it may not be progress.

Read only these, and nothing else:

{{CONTEXT_FILES}}

You are the product officer, not the section's manager. Do not re-review the
engineering. Answer one question: given the section's own acceptance criteria,
is the remaining distance to `COMPLETE` shrinking?

Look for the failure modes that produce accepted cycles forever:

- an acceptance criterion no role dispatched into this section can ever close,
  because it needs credentials, a live external system, market hours, weeks of
  wall clock, or a human signature
- an acceptance criterion that has quietly been replaced by a weaker one the
  section can grade in-process
- cycles that each add something real while the criterion they are aimed at has
  not moved

## Respond with these sections only, each as a Markdown heading

1. What has actually closed
2. What still stands between here and complete
3. Whether the distance is shrinking
4. Decision

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens:

- `CONTINUE` - the section is converging; the cycles are buying real ground
- `RESCOPE` - the section can close, but not on its current acceptance criteria;
  say on the same line what has to change
- `BLOCKED_EXTERNAL` - an acceptance criterion cannot be reached from inside the
  flow; name the external dependency and what would unblock it
- `ABANDON` - the capability cannot be delivered and the product must be
  reconciled without it

A short justification may follow the token on the same line.
