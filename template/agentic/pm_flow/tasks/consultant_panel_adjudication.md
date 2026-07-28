---

# Task: adjudicate a consultant panel

Section `{{SECTION_KEY}}` has failed repeatedly and was referred to a panel of
independent consultants. Each consultant saw the same brief and none of them saw
the others' work, so agreement between them is real evidence and disagreement is
information about uncertainty — not a tie to be broken arbitrarily.

Read the failure brief and every proposal:

{{PANEL_FILES}}

## How to weigh the proposals

- Judge each against the product, not against the original design. A path that
  delivers the section's value differently is a success, not a compromise.
- Where consultants agree on the diagnosis, treat it as probably correct.
- Where they disagree, ask which one engaged with the actual evidence from the
  failed attempts rather than reasoning from first principles.
- A proposal that names a standard, established solution should be preferred
  over an invented one, unless there is a specific reason the standard approach
  does not apply here.
- Discount confidence that is not backed by a stated way to prove the path works.

## Choosing more than one path

If no single proposal is clearly right, you may run several in parallel. Do that
when the paths are genuinely independent, when each is cheap enough to be worth
the parallel spend, and when a decisive result on either would settle the
question. Do not run parallel paths merely to avoid deciding — say what evidence
will pick the winner and when you expect it.

## Respond with these sections only, each as a Markdown heading

1. Panel assessment
2. Points of agreement
3. Points of disagreement
4. Selected paths
5. Rationale
6. Decision

`Selected paths` must list the proposal numbers you are adopting, one per line,
each with a one-line statement of what it is expected to produce. For
`SYNTHESIZE`, describe the combined path there instead. For `ABANDON`, state
what the product loses and why it can still reach its goal.

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: ADOPT, ADOPT_PARALLEL, SYNTHESIZE, ABANDON.
A short justification may follow the token on the same line.

`ABANDON` should be rare. Two independent consultants failing to find a path is
meaningful, but it is still your call whether the product survives without this
capability.
