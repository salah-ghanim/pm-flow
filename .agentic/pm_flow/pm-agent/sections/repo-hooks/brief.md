## Objective

- Make the repository enforce its own commit convention, and keep the pm-flow
  installs we actually run from drifting behind the version this repository is
  at.

## Scope

Two hooks, one section, because both are the same missing thing: this repository
states rules it does not check.

**The commit convention is documentation, not a gate.** `AGENTS.md` and the task
contracts require Conventional Commits under 72 characters. Nothing verifies it,
there is no `commitlint`, no `.releaserc`, and no `core.hooksPath`. A convention
nobody can fail is a convention that decays, and the log is what a release would
be cut from.

Read the log before designing the check, because the first thing it will reject
is us. The driver writes its own commit messages and only one of them parses:

- `fix(harness): repair for <section> (attempt N, VERDICT)` — valid.
- `<section>: accepted cycle N (state and handoff)` — no type.
- `sync: bring the section up to <base>` — `sync` is not a type.
- `merge(<section>): accepted work from <branch>` — `merge` is not a type.

Three of the four are emitted on every accepted cycle and every merge-back, from
`driver.zsh`, which belongs to `codex-usage`. A hook that refuses them stops the
flow dead. Either the driver's messages are corrected first through a bounded
change handed to that section, or the hook is written to exempt exactly those
generated messages and says so out loud. Deciding that is part of this work;
discovering it at the first rejected merge-back is not.

**The installs drift.** pm-flow is used by real projects on this machine —
`golden-grid` carries about ten workspaces — and today an update reaches them by
being copied. `packaging` replaces that: the engine becomes an installed wheel
and a repository holds project data only. Once it lands, keeping a project
current is `pip install -U` into its venv plus the one-time legacy migration
`packaging` already built and proved, not a file-copying protocol.

So this section is about the *rollout*, not the mechanism: something that knows
which internal projects exist, what version each is pinned to, and whether that
matches this repository. `packaging` owns migration; do not rebuild it here.

Be careful what "on each commit" means. A hook that reaches into other
repositories and mutates them, or that needs the network, turns every local
commit into a slow and occasionally destructive operation, and it will be
disabled within a week. The safe shape is a hook that *observes and reports*
drift cheaply and offline, with the update itself an explicit command a person
or a scheduled job runs. If a cheap in-hook check is genuinely impossible, say
so and move the work to the explicit command entirely.

## Priority

- nice-to-have. Nothing is blocked on it. Without it the convention erodes and
  every internal project is updated by hand, which is how they got out of step.

## Owned paths

- `.githooks/**`
- `tools/hooks/**`
- `.releaserc.json`
- `tests/repo_hooks_test.sh`

New paths only. `driver.zsh` belongs to `codex-usage` and `install.sh`,
`README.md` and the packaged layout belong to `packaging`; hand either a bounded
change rather than editing from here.

## Dependencies

- packaging

Real, not sequencing. The migration half is defined against the packaged layout:
until a repository holds project data only and the engine comes from a wheel,
"is this project up to date" has no version to compare and the answer is a
file-tree diff, which is the thing being deleted.

The commit hook does not depend on `packaging` and can land first.

## Acceptance

Stated as outcomes, because a hook that exists and is not installed is the
default failure here.

- In a fresh clone, after running the documented setup step and nothing else, a
  commit whose message does not follow the convention is refused, and the
  refusal names which rule it broke.
- A conforming commit is not refused, and the check adds no perceptible delay to
  an ordinary commit.
- Every commit message the driver generates today either passes the hook, or is
  changed to pass it — and a full section cycle runs end to end with the hook
  installed, reaching an accepted merge-back without the hook stopping it. A
  green suite is not evidence for this; the flow itself has to run.
- Someone who has not read this repository can list the internal projects, see
  which pm-flow version each is on and which are behind, and bring one up to
  date, from one documented command.
- Bringing a project up to date preserves its project data — plan, sections, run
  history, recorded domain, local overrides — and the project runs afterwards.
  Reuse `packaging`'s migration proof rather than writing a second one.
- Committing still works with no network, with the hooks uninstalled, and in a
  worktree.
- The suite still passes.

## Rejection conditions

- The hook exists in the tree but a fresh clone does not have it installed, so
  the convention is still unenforced.
- The hook refuses the driver's own commits, or the flow is left unable to
  complete a cycle.
- A commit triggers a network call, a package install, or a write to any
  repository other than the one being committed to.
- Migration logic is reimplemented here instead of reusing `packaging`'s.
- An internal project is updated in a way that loses project state or its
  recorded domain.
- The hook cannot be bypassed for a genuine emergency, or bypassing it is
  undocumented.
- The suite is weakened, or made to exit zero without running to completion.
