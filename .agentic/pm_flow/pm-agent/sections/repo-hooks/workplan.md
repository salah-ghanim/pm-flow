# repo-hooks workplan

## Design summary

- Ship repository-local, opt-in Git hooks installed by one documented setup
  command. The commit-msg hook uses a fast dependency-free checker. A separate
  project inventory/update command reports installed pm-flow versions and
  delegates migration to the packaging contract.

## Interfaces and data changes

- `.githooks/commit-msg` validates the repository's Conventional Commit policy.
- `tools/hooks/install` configures `core.hooksPath` for this clone/worktrees.
- `tools/hooks/projects` lists project versions and upgrades one explicitly.

## Task T1 — Implement the commit-message checker

- Status: pending.
- Outcome: invalid messages fail with the violated rule; valid conventional,
  merge, revert, and generated messages complete quickly and offline.
- Paths: `.githooks/**`, `tools/hooks/**`, `.releaserc.json`,
  `tests/repo_hooks_test.sh`.
- Reuse: the convention documented in `AGENTS.md`; keep parser and release config
  aligned through shared fixtures.
- Acceptance IDs: A1, A2, A6.
- Validation: accepted/rejected message table, latency bound, no-network run,
  worktree run, and hook-uninstalled control.
- Depends on: packaging (complete).

## Task T2 — Make driver-generated commits conform

- Status: blocked until codex-usage releases `driver.zsh` ownership.
- Outcome: every driver commit subject passes the same checker without adding
  exemptions for legacy non-conventional forms.
- Paths: `driver.zsh` after ownership transfer, plus T1 fixtures.
- Reuse: current commit construction sites and section key as commit scope.
- Acceptance IDs: A3.
- Validation: enumerate every generated subject in tests; mutation restoring
  `<section>: accepted...` or `sync: ...` fails the checker.
- Depends on: T1 and ownership transfer.

## Task T3 — Install hooks safely in clones and worktrees

- Status: pending.
- Outcome: one documented local setup installs hooks; no install remains valid;
  committing works offline and from a linked worktree.
- Paths: `.githooks/**`, `tools/hooks/**`, `tests/repo_hooks_test.sh`.
- Reuse: Git `core.hooksPath`; do not copy into `.git/hooks`.
- Acceptance IDs: A1, A2, A6.
- Validation: fresh clone install, valid/invalid commits, worktree commit,
  uninstall/no-hook control, and no network calls.
- Depends on: T1.

## Task T4 — Inventory and update internal projects

- Status: pending.
- Outcome: one command lists projects, installed/running pm-flow version, target
  version, and behind/current state, then upgrades one without losing data.
- Paths: `tools/hooks/**`, `tests/repo_hooks_test.sh`.
- Reuse: `projects.md`, packaged `pm-flow version`, and packaging's migration
  harness; do not reimplement migration.
- Acceptance IDs: A4, A5.
- Validation: two disposable projects on different versions, one explicit
  upgrade, project-data hashes/history preserved, post-upgrade tick succeeds.
- Depends on: packaging (complete).

## Task T5 — Full hook-enabled section cycle

- Status: pending.
- Outcome: with the hook installed, a complete section cycle reaches accepted
  merge-back and all generated commits pass; the full suite remains green.
- Paths: all owned hook paths plus transferred driver path from T2.
- Reuse: installed-artifact and worktree-isolation harnesses.
- Acceptance IDs: A3, A7.
- Validation: real hook-enabled flow E2E, generated-subject assertions, full
  suite, and mutation restoring one invalid generated subject.
- Depends on: T2, T3, T4.

## Integration and end-to-end validation

- T1/T3 and T4 can proceed independently. T5 is the acceptance gate; unit
  testing the checker alone cannot satisfy A3.

## Risks and rollback

- Hooks are local and opt-in. Rollback clears `core.hooksPath`; project upgrades
  retain packaging's data-preservation guarantees.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T1, T3 | Fresh-clone invalid/valid commits |
| A3 | T2, T5 | Full accepted cycle with hook installed |
| A4, A5 | T4 | Version inventory and lossless upgrade |
| A6 | T1, T3 | Offline, uninstalled, and worktree controls |
| A7 | T5 | Full suite completes |
