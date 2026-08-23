## Objective

- The repository enforces its own commit convention, and the pm-flow installs
  on this machine can be listed, compared with this checkout's version, and
  brought up to date by one command.

## Current baseline

- `AGENTS.md` requires Conventional Commits under 72 characters; nothing checks
  a commit. No `.githooks/`, no `core.hooksPath`, no `.releaserc.json`.
- The driver writes its own commits with `--no-verify`; its subjects are
  `chore(<section>): …` forms.
- `install.sh` migrates a copied-engine install to the packaged layout and
  `pip install -U pm-flow` upgrades the engine; nothing lists which
  repositories on this machine use pm-flow or which version each has.

## Deliverables

- `.githooks/commit-msg`: a dependency-free checker that refuses a
  non-conforming subject and names the rule it broke.
- `tools/hooks/install`: sets `core.hooksPath` for this clone and its
  worktrees; `tools/hooks/uninstall` clears it.
- `tools/hooks/projects`: lists the repositories in
  `~/.config/pm-flow/projects.txt`, each with its installed `pm-flow` version
  and whether it is behind this checkout's `VERSION`; `tools/hooks/projects
  update <repo>` upgrades one.
- `.releaserc.json` aligned with the checker's rules.
- `tests/repo_hooks_test.sh`.

## User-visible scenarios

1. In a fresh clone, after `tools/hooks/install`, `git commit -m "update
   stuff"` is refused with `subject needs a type: feat|fix|…`; `git commit -m
   "fix(hooks): name the rule"` succeeds in under 100 ms of added time.
2. `tools/hooks/projects` prints one line per registered repository:
   path, installed version, `current` or `behind <version>`.
3. `tools/hooks/projects update ~/code/golden-grid` upgrades that repository's
   venv package and runs `install.sh` there; its plan, sections, run history
   and recorded domain are unchanged, and `pm-flow status` runs afterwards.

## Interfaces produced

- `tools/hooks/install|uninstall|projects`.
- `~/.config/pm-flow/projects.txt`: one repository path per line, owned by the
  user, never written by a hook.

## Interfaces consumed

- `install.sh` and its migration guarantees; `pm-flow version`; `VERSION`.

## Scope

- In: the hook, its installer, the inventory/update command, release config,
  tests.
- Out: `driver.zsh`, `install.sh`, the packaged layout, any network call from
  a hook.

## Non-goals

- Re-implementing migration; the update command delegates to `install.sh`.
- A hook that inspects or mutates other repositories.

## Priority

- nice-to-have: nothing is blocked on it; without it the convention erodes and
  installs are updated by hand.

## Owned paths

- `.githooks/**`
- `tools/hooks/**`
- `.releaserc.json`
- `tests/repo_hooks_test.sh`

## Dependencies

- packaging

## Constraints and fixed decisions

- Hooks are opt-in per clone through `core.hooksPath`; nothing is copied into
  `.git/hooks`.
- The checker accepts the driver's `chore(<scope>): …` subjects, merge and
  revert subjects, and `--no-verify` remains the documented emergency bypass.
- The update command never runs during a commit and never touches a
  repository not named on its command line.

## Acceptance

- A1: In a fresh clone with the hook installed, a subject without a type or
  over 72 characters is refused and the refusal names the rule; a conforming
  subject is accepted.
- A2: The hook adds under 100 ms to a commit, measured in the test, and
  invokes no network client: the test greps the hook for `curl`, `wget`, `nc`
  and `urllib` and finds none.
- A3: Every subject `driver.zsh` generates, enumerated by the test from its
  `-m` arguments, passes the checker; the transitions stub suite runs to its
  accepted merge-back with the hook installed in the test repository.
- A4: `tools/hooks/projects` lists two disposable repositories registered in a
  temporary `projects.txt`, one on an older wheel, as `behind` and `current`.
- A5: `tools/hooks/projects update <repo>` on the `behind` one leaves its
  project data byte-identical except the engine, and `pm-flow status` exits 0
  there afterwards.
- A6: Committing still works offline, with `tools/hooks/uninstall` applied,
  and from a linked worktree.
- A7: `zsh tests/repo_hooks_test.sh` and `zsh tests/pm_flow_test.sh` exit 0.

## Rejection conditions

- The hook exists in the tree but a documented fresh-clone setup does not
  install it.
- The hook refuses a driver-generated subject.
- A commit triggers a network call, a package install, or a write to another
  repository.
- Migration logic is re-implemented instead of delegated to `install.sh`.

## Open questions

- None.
