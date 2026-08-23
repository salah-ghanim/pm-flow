# Project state

This directory is what the product officer reads. Keep it small: everything
here is loaded into the officer's context on every decomposition or
adjudication.

- `plan.md` — the mission, constraints, and integration order. **You write
  this.** It is the input the product officer decomposes into sections.
- `sections.md` — a generated registry of every section, its status, and its
  one-line summary. Refresh it with `pm_flow.sh list-sections`; per-section
  files are authoritative.
- `start.md` / `resume.md` — how to start and how to resume a run.
- `decomposition/` — the officer's section blocks from the run that created
  them, kept for audit.

Per-section detail lives under `../sections/<key>/` and is deliberately not
read from here:

- `brief.md` — the boundary and acceptance criteria
- `workplan.md` — ordered, acceptance-mapped executable tasks
- `state.md` — current task, decisions, blockers, and validation evidence
- `handoff.md` — the bounded report upward, capped at 500 words and 8192 bytes
- `cycles/NNN/` — one attempt each: assignment, result, review, decision
- `escalation/` — the consultant panel, the adjudication, and any rescue

The section's cycle files *are* its state. Nothing records what the driver was
doing, so an interrupted run resumes by being run again.
