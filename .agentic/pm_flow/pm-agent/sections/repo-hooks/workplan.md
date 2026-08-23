# repo-hooks workplan

## Design summary

- A POSIX-shell `commit-msg` hook with the rule table in one place shared with
  `.releaserc.json`; an installer that only sets `core.hooksPath`; an
  inventory command that reads a user-owned list and delegates upgrades to
  `pip` and `install.sh`.

## Interfaces and data changes

- `tools/hooks/install|uninstall|projects`; `~/.config/pm-flow/projects.txt`.

## Task T1 — Commit-message checker

- Status: pending.
- Outcome: `.githooks/commit-msg` refuses a subject without a Conventional
  Commits type, with an unknown type, or over 72 characters, naming the rule;
  accepts conforming, merge and revert subjects and every subject enumerated
  from `driver.zsh`.
- Paths: `.githooks/**`, `.releaserc.json`, `tests/repo_hooks_test.sh`.
- Reuse: the type list in `AGENTS.md`.
- Acceptance IDs: A1, A2, A3.
- Validation: `zsh tests/repo_hooks_test.sh` — a table of accepted and
  rejected subjects with the expected rule text; the driver-subject
  enumeration passes; timing under 100 ms; no network client in the hook; a
  mutation allowing a 73-character subject fails.
- Depends on: None.

## Task T2 — Install into clones and worktrees

- Status: pending.
- Outcome: `tools/hooks/install` sets `core.hooksPath`; `uninstall` clears it;
  committing works offline, uninstalled, and from a linked worktree; the
  transitions stub suite reaches its merge-back with the hook installed.
- Paths: `tools/hooks/**`, `tests/repo_hooks_test.sh`.
- Reuse: `git config core.hooksPath`; the transitions suite.
- Acceptance IDs: A3, A6.
- Validation: `zsh tests/repo_hooks_test.sh` — fresh clone, install, refused
  and accepted commits, worktree commit, uninstall; the stub suite exits 0
  under the hook.
- Depends on: T1.

## Task T3 — Inventory and update

- Status: pending.
- Outcome: `tools/hooks/projects` lists registered repositories with installed
  version and `current`/`behind`; `update <repo>` runs `pip install -U` in
  that repository's venv and `install.sh` there, preserving project data.
- Paths: `tools/hooks/**`, `tests/repo_hooks_test.sh`.
- Reuse: `install.sh`, `pm-flow version`, the packaged-layout harness for
  building two wheel versions.
- Acceptance IDs: A4, A5.
- Validation: `zsh tests/repo_hooks_test.sh` — two disposable repositories
  on different wheels list correctly; after `update`, project-data hashes are
  unchanged and `pm-flow status` exits 0; `update` with no argument refuses.
- Depends on: None.

## Task T4 — Closeout

- Status: pending.
- Outcome: the full section test and the engine suite pass together.
- Paths: `tests/repo_hooks_test.sh`.
- Reuse: T1–T3.
- Acceptance IDs: A7.
- Validation: `zsh tests/repo_hooks_test.sh` and `zsh tests/pm_flow_test.sh`
  exit 0.
- Depends on: T2, T3.

## Integration and end-to-end validation

- T2's hook-enabled stub suite run is the flow-level proof; T3's update of a
  disposable repository is the install-level proof.

## Risks and rollback

- A hook that refuses a driver subject stops the flow; A3's enumeration is the
  guard. Rollback is `tools/hooks/uninstall`.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T1 | Refusal names the rule; timing; no network |
| A3 | T1, T2 | Driver subjects pass; stub suite merges back under the hook |
| A4, A5 | T3 | Inventory lists; update preserves data |
| A6 | T2 | Offline, uninstalled, worktree commits |
| A7 | T4 | Both suites exit 0 |
