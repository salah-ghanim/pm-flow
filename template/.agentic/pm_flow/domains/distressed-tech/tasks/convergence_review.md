---

# Task: is this desk converging?

Desk `{{SECTION_KEY}}` has had {{ACCEPTED_CYCLES}} cycles accepted in a row
without ever being declared complete and without ever being rejected. That is
motion, and it may not be progress.

Read only these, and nothing else:

{{CONTEXT_FILES}}

You are the research principal, not the desk's lead. Do not re-review the
records. Answer one question: given the desk's own acceptance criteria, is the
remaining distance to `COMPLETE` shrinking?

Look for the failure modes that produce accepted cycles forever:

- an acceptance criterion no assignment can ever close, because it needs a
  document behind a signature, an outcome the estate has not decided, or a
  deadline that has not arrived
- an acceptance criterion that has quietly been replaced by a weaker one the
  desk can grade in-process — records counted instead of records verified,
  leads gathered instead of facts settled
- cycles that each add real records while the criterion they are aimed at has
  not moved: a desk can enumerate proceedings indefinitely without ever
  establishing what any of them is selling
- a desk re-verifying what it already verified, because staleness gives an
  infinite supply of legitimate-looking work

## Respond with these sections only, each as a Markdown heading

1. What has actually closed
2. What still stands between here and complete
3. Whether the distance is shrinking
4. Decision

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens:

- `CONTINUE` - the desk is converging; the cycles are buying real ground
- `RESCOPE` - the desk can close, but not on its current acceptance criteria;
  say on the same line what has to change
- `BLOCKED_EXTERNAL` - an acceptance criterion cannot be reached from inside the
  flow; name the external dependency and what would unblock it
- `ABANDON` - the coverage cannot be delivered and the overview must be
  reconciled without it

A short justification may follow the token on the same line.
