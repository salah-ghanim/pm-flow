# repo-hooks section handoff

## Outcome

Rebaselined into checker, generated-message repair, hook installation, project
inventory/update, and a real hook-enabled flow E2E. No hooks exist yet.

## Decisions

- Use local `core.hooksPath`; installation is opt-in and offline-safe.
- Repair invalid generated subjects instead of exempting them.
- Reuse packaging migration for project updates.

## Interfaces

- Planned: `.githooks/commit-msg`, `tools/hooks/install`, and
  `tools/hooks/projects`.

## Risks

- T2/T5 need driver ownership after codex-usage. A green parser unit test cannot
  substitute for the hook-enabled accepted-cycle scenario.

## What is unproven

- All A1–A7 outcomes; nothing has been implemented.

## Next action

Scope workplan T1.
