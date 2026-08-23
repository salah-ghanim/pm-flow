---

# Task: implement this assignment

Section: `{{SECTION_KEY}}`
Cycle: `{{CYCLE}}`

Read only the task and supporting context listed here:

{{CONTEXT_FILES}}

`assignment.md` is authoritative for the task ID, writable paths, acceptance
IDs, and validation commands. `brief.md` and `workplan.md` explain the contract;
they do not authorize extra work. `state.md` may clarify current facts but
cannot broaden the assignment.

Append a heartbeat after reading, after the first material edit, and after
validation:

`{{HEARTBEAT_SCRIPT}} {{HEARTBEAT_FILE}} "<completed step>"`

Do not construct timestamps yourself.

Return only these Markdown headings:

1. `## What I changed`
2. `## What I reused or restructured`
3. `## Validation` — command and unedited output for each assigned check
4. `## What I could not do`
5. `## Status`

`Status` is exactly one line beginning `DELIVERED`, `PARTIAL`, or `BLOCKED`,
optionally followed by a short reason. Use `DELIVERED` only when every assigned
acceptance ID is evidenced.
