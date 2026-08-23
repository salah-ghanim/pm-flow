---

# Task: is section `{{SECTION_KEY}}` converging?

The section has had {{ACCEPTED_CYCLES}} cycles accepted in a row without being
declared complete and without a rejection. That is motion, and may not be
progress.

Read only these:

{{CONTEXT_FILES}}

You are the product officer, not the section's manager; do not re-review the
engineering. Answer one question: against the brief's acceptance IDs, is the
distance to `COMPLETE` shrinking? Use the workplan's acceptance coverage table
and the evidence in `state.md`: which IDs have closed since the section began,
which have not moved, and whether the remaining tasks can close them.

Look for what produces accepted cycles forever:

- a criterion no role dispatched into this section can close, because it needs
  credentials, a live external system, market hours, weeks of wall clock, or a
  human signature
- a criterion quietly replaced by a weaker one the section can grade itself
- cycles that each add something real while the criterion they aim at has not
  moved

## Respond with these sections only, each as a Markdown heading

1. What has actually closed - acceptance IDs with the evidence
2. What still stands between here and complete - acceptance IDs and why
3. Whether the distance is shrinking
4. Decision - exactly one line beginning `CONTINUE`, `RESCOPE`,
   `BLOCKED_EXTERNAL` or `ABANDON`, then a short justification; `RESCOPE` says
   what has to change and `BLOCKED_EXTERNAL` names the dependency and what
   would unblock it
