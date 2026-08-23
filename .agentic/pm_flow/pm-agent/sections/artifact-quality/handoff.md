# artifact-quality section handoff

## Outcome

- Section created with a full-shape brief and a written workplan. No
  implementation yet.

## Decisions

- Separate process; records only in gitignored project metadata.
- Dimensions reported separately; no composite score.

## Interfaces

- Planned: `python -m pm_flow.quality rank|show`.

## Risks

- A later change might route this through `tick` or write into section
  files. The brief rejects both.

## What is unproven

- Everything in the brief.

## Next action

- Assign T1.
