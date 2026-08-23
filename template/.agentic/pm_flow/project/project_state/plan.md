# Project portfolio plan

## Mission

- {{PRIMARY_MISSION}}

## Project-wide constraints

- Record only constraints that apply across multiple sections.

## Section graph

- Define independently owned sections and their dependencies at a high level.
- Keep executable implementation plans in each section's `workplan.md`; keep
  only current truth and evidence in `state.md`.

## Integration order

- Record which section interfaces must settle before dependent sections begin.

## Project-level decisions

- Record decisions that affect multiple sections.
- Keep section-local decisions out of this file.

## Completion criteria

- Define the project-level outcome assembled from validated section handoffs.

## Next coordination actions

- List only section creation, dependency reconciliation, integration, or release actions.

This file is intentionally bounded. The root coordinator reads it together with
`sections.md`; section PM and developer detail belongs under `sections/<name>/`.
