---

# Task: review a developer result

Section: `{{SECTION_KEY}}`
Cycle: `{{CYCLE}}`

Read:

{{CONTEXT_FILES}}

Review only the assigned workplan task. Build an acceptance matrix with one row
per assigned acceptance ID: expected observation, evidence actually seen, and
`MET` or `NOT MET`. Run the assignment's validation commands yourself and paste
their output. Use the smallest reversible negative or mutation check that shows
the test would fail if the promised behaviour were absent; if that is unsafe or
inapplicable, state why.

Check for drift: changed paths outside ownership, new behaviour not requested,
an acceptance demonstrated only by a stub, or a result that stops before the
user-visible outcome. Do not accept effort or file existence as evidence.

Classify any obstruction:

- `NONE`: the work was judged on its merits.
- `HARNESS`: the environment or validation plumbing prevented a fair check.
- `TASK`: the implementation or assignment contract is deficient.

The driver commits and merges an accepted result. Do not commit and never
reject solely because `.git` was not writable.

Return only these Markdown headings:

1. `## Assessment`
2. `## Acceptance matrix`
3. `## Obstruction`
4. `## Drift review`
5. `## Evidence check`
6. `## Risks`
7. `## Decision`

`Obstruction` is exactly one line beginning `NONE`, `HARNESS`, or `TASK`.
`Decision` is exactly one line beginning `GO`, `GO_WITH_CHANGES`, or `NO_GO`.
A short reason may follow either token.
