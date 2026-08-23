---

# Task: review a developer result

Section: `{{SECTION_KEY}}`
Cycle: `{{CYCLE}}`

Read:

{{CONTEXT_FILES}}

Review only the assigned workplan task. Build an acceptance matrix with one row
per assigned acceptance ID: expected observation, evidence actually seen, and
`MET` or `NOT MET`. Run the assignment's validation commands yourself and paste
their output. Where safe, use the smallest reversible negative or mutation
check that shows the test would fail if the promised behaviour were absent; if
that is unsafe or inapplicable, say why.

Check for drift: changed paths outside ownership, behaviour not requested, an
acceptance demonstrated only by a stub, or a result that stops before the
user-visible outcome. Effort and file existence are not evidence.

Classify any obstruction:

- `NONE` - the work was judged on its merits
- `HARNESS` - the environment or validation plumbing prevented a fair check
- `TASK` - the implementation or the assignment contract is deficient

## Record the outcome

On `GO` or `GO_WITH_CHANGES`, before answering: set the task's status in
`workplan.md`, and add the task ID, its acceptance IDs, the command and the
observation to `Completed tasks and evidence` in `state.md`. On `NO_GO`, record
the observed blocker in `state.md` if it will outlive this cycle.

## Respond with these sections only, each as a Markdown heading

1. `## Assessment`
2. `## Acceptance matrix`
3. `## Obstruction` - exactly one line beginning `NONE`, `HARNESS` or `TASK`
4. `## Drift review`
5. `## Evidence check`
6. `## Risks`
7. `## Decision` - exactly one line beginning `GO`, `GO_WITH_CHANGES` or
   `NO_GO`, then an optional short reason
