---

# Task: assess section `{{SECTION_KEY}}` now

The owner asked where this section stands, outside the development loop. This
is an assessment, not an assignment, and nothing parses it.

Read:

{{CONTEXT_FILES}}

The section is at cycle {{CYCLE}}. If a focusing question is among the files
above, answer it first and explicitly; the rest still applies.

## What this call may and may not do

- Do not write an assignment, and do not name a next developer task as if
  dispatching it. Say what you would do next and why; the owner decides.
- Do not create, advance or edit a cycle. Do not answer `ASSIGN`, `COMPLETE` or
  `BLOCKED_EXTERNAL`: those are scope verdicts and this is not a scope call.
- You may correct `workplan.md` and `state.md` where what you found contradicts
  them. Change nothing else.

## What the answer has to settle

- Each acceptance ID in `brief.md`: `MET`, `NOT MET` or `UNKNOWN`, with the
  observation behind it. Run the validation command the workplan names for it
  and paste what it printed; a criterion is not met because a review said so,
  and untested is `UNKNOWN`.
- What blocks the section, and whether that is difficulty, an external
  dependency, or a decision nobody has taken.
- Which workplan task you would run next and why it comes first.
- What you cannot settle yourself: questions above your scope, for the owner
  or another section.

## Respond with these sections only, each as a Markdown heading

1. Where the section stands
2. What is blocking it
3. What I would do next and why
4. What I cannot settle myself

No Decision section. This call has no verdict.
