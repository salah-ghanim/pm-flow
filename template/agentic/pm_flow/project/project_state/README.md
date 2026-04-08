# Project state

This directory is the stable repo-local continuation layer for {{PROJECT_NAME}}.

Use it for non-timestamped files that future sessions should read first, such as:

- `plan.md`
- `current_run.txt`
- any repo-specific trackers that should survive across machines

Rules:

- `project_state/` is the canonical home for continuation state.
- `runs/<timestamp>-<task-slug>/` remains the audit trail for task briefs, transcripts, responses, and pending reviews.
- `current_run.txt` stores a repo-relative run path so the pointer stays portable across environments.
