---

# Task: scope the next assignment

Section: `{{SECTION_KEY}}`
Cycle: `{{CYCLE}}`
Recent-cycle window: at most `{{HISTORY_WINDOW}}` prior cycles

Read:

{{CONTEXT_FILES}}

The context is intentionally bounded. `brief.md` is the stable outcome
contract, `workplan.md` is the executable decomposition, and `state.md` is the
current evidence ledger. Older cycle detail is excluded and must already be
summarized in those durable files.

First reconcile those three artifacts. If the workplan is missing or still a
template, write a complete workplan before assigning. It must map every brief
acceptance ID to ordered tasks and include integration and end-to-end
validation. If current evidence changes task order or retires a task, update
`workplan.md` and `state.md`; do not preserve superseded prose.

Then choose one decision:

- `ASSIGN`: select exactly one next eligible workplan task. Copy its task ID,
  concrete outcome, writable paths, inputs to reuse, acceptance IDs, validation
  commands with expected observations, and rejection conditions. The task
  description must carry more implementation-specific detail than process
  advice.
- `COMPLETE`: every brief acceptance ID has current evidence in `state.md`,
  including the end-to-end scenario. Stalled or awkward work is not complete.
- `BLOCKED_EXTERNAL`: no executable task can satisfy a criterion without an
  external dependency. On the decision line, name the dependency and what
  would unblock it. In the standing section, include the probe run now and its
  output. Difficulty and failed attempts do not qualify.

The driver commits accepted implementation work. Do not commit and do not ask
another role to commit.

Return only these Markdown headings:

1. `## Where the section stands`
2. `## Workplan task`
3. `## Assignment`
4. `## Acceptance`
5. `## Rejection conditions`
6. `## Decision`

For `ASSIGN`, `Workplan task` contains exactly one task ID from `workplan.md`.
For the other decisions, headings 2–5 contain `Not applicable.` `Decision` is
exactly one line beginning `ASSIGN`, `COMPLETE`, or `BLOCKED_EXTERNAL`, with an
optional short reason except that `BLOCKED_EXTERNAL` requires one.
