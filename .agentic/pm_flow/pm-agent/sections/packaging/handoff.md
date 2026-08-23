## Outcome

Complete on `main` at `c2438b4`. The engine is an installed package; a
repository holds project data only.

- The pm-flow wheel in a project `.venv` gives a working `.venv/bin/pm-flow`;
  nothing is copied into the repository.
- Two repositories pin `0.7.1` and `0.7.2` and run their own versions;
  upgrading one leaves its `.agentic/` byte-identical and the other untouched.
- `.agentic/pm_flow/<project>/roles/<role>.md` overlays the packaged persona;
  the run record names base, domain and local layers.
- A copied-engine install migrates through `install.sh`: state, store attempts
  and the open cycle survive; the installed command takes the next step.
- `MANIFEST`, `upgrade.py` and `tools/manifest.py` are deleted; the suite runs
  the README's install, status and tick lines through the wheel.
- `tests/pm_flow_test.sh` (10 PASS) and `tests/packaged_layout_test.sh`
  (13 PASS) exit 0, plain and under a hostile environment.

## Decisions

- `install.sh` stays in the checkout, not the wheel; `pm-flow` has no `init`.
  The README's install line names the checkout path.
- `*.pm-flow.template.md` is not project data; `install.sh` renders it in a
  temp cache only. agents-md's backup and marker contract is unchanged.

## Interfaces

- `pm-flow` resolves the engine from the venv and project data from the
  invoking repository; `src/pm_flow/paths.py` is the shared layout.
- The wheel force-includes `template/.agentic/pm_flow`; engine edits there
  need no packaging change.
- `tests/packaged_layout_test.sh`: offline hashed wheelhouse, separate build
  and runtime venvs, data-only fixtures. Sections touching install, layout or
  personas extend it; no copy-based fixtures.

## Risks

- A user with only `pip install pm-flow` cannot create project data. Revealed
  by following the README without a checkout.
- The scoped tier denies `zsh tests/*` (`DEFAULT_SCOPED_BASH` lists pytest
  only; no `access.scoped_bash` in `config.json`). No PM review here has run
  the suite; 008 and 009 rest on the recorded event stream.
- Developer heartbeats fail under worktree isolation: `heartbeat.sh` writes
  into the main checkout from a worktree-rooted sandbox; all four 009 calls
  exited 1. A dispatch past the silent-stall budget dies unheard.

## What is unproven

- `pip install pm-flow` from an index. Every proof installs a locally built
  wheel; `pypi.org` is unreachable from this role, so the name is unverified.
  Settled by `pip index versions pm-flow` naming this project, or a first
  publish; `uv tool install` never ran.
- Migration of a real install. The legacy fixture is today's template plus
  `MANIFEST` and `upgrade.py`. The one real install (golden-grid, surveyed
  2026-07-28: pre-sections `pm_flow.sh`, ten workspaces, no `.project-key`)
  is unmigrated. Settled by running `install.sh` against a copy of it and
  driving a tick.
- Upgrade across a behavioural change: the pinned wheels differ only by
  version stamp. Settled by upgrading across a driver-changing release.
- Install onto a pre-existing `AGENTS.md`; the root-listing assertion covers
  only a pre-existing `CLAUDE.md` (same merge path).
- A reviewer's own suite run. Settled by granting `zsh tests/*` to the scoped
  tier and re-running the acceptance commands.

## Next action

Re-cut the blocked sections against the packaged layout. Before their first
review, grant `zsh tests/*` to the scoped tier and fix the worktree heartbeat
path.
