---

# Task: scope the next assignment

Section: `{{SECTION_KEY}}`
Cycle: `{{CYCLE}}`
Recent-cycle window: at most `{{HISTORY_WINDOW}}` prior cycle(s)

Read:

{{CONTEXT_FILES}}

`brief.md` is the outcome contract, `workplan.md` its executable decomposition,
`state.md` the current evidence ledger. Older cycle detail is excluded and must
already be summarised in those files.

## First, reconcile the three artifacts

If `workplan.md` is missing, still carries the scaffold marker, or no longer
matches the evidence: write it now. Every brief acceptance ID maps to ordered
`T<number>` tasks, each with a concrete outcome, exact writable paths, inputs
to reuse, acceptance IDs, and a validation command with its expected
observation; the last task proves the user-visible scenario end to end.
Cut every task a full cycle wide: a change too small to carry its own
scope-develop-review pass - a test extension, a doc line - belongs inside the
task that makes it necessary, never after it as a task of its own. Delete
the scaffold marker line and any superseded prose. If the previous cycle
changed what is true, update `state.md` the same way.

## Then choose one decision

- `ASSIGN` - select the next eligible workplan task, exactly one. Under
  `Assignment`, give the developer what the task needs: the task ID and
  outcome, writable paths, existing code to reuse, and the behaviour to
  implement, in more implementation-specific detail than process advice. Under
  `Acceptance`, the task's acceptance IDs with the validation command and
  expected observation for each. Under `Rejection conditions`, what would make
  the result unacceptable even if the commands pass.
- `COMPLETE` - every brief acceptance ID has current evidence in `state.md`,
  including the end-to-end scenario. Stalled or awkward is not complete.
- `BLOCKED_EXTERNAL` - no executable task can satisfy a criterion without an
  external dependency. Name the dependency and what would unblock it on the
  decision line, and put the probe you ran now, with its output, under `Where
  the section stands`. Difficulty and failed attempts do not qualify.

## Respond with these sections only, each as a Markdown heading

1. `## Where the section stands`
2. `## Workplan task` - for `ASSIGN`, one line naming exactly one task ID from
   `workplan.md`
3. `## Assignment`
4. `## Acceptance`
5. `## Rejection conditions`
6. `## Decision` - exactly one line beginning `ASSIGN`, `COMPLETE` or
   `BLOCKED_EXTERNAL`, then an optional short reason; `BLOCKED_EXTERNAL`
   requires one

For `COMPLETE` and `BLOCKED_EXTERNAL`, headings 2-5 contain `Not applicable.`
