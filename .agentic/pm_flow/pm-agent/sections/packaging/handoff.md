## Outcome

Cycles 004, 006, 007 and 008 are accepted and merged. `MANIFEST`, `upgrade.py`
and `tools/manifest.py` are gone from `main`; a repository holds project data
only and the engine comes from an installed wheel. Cycle 009 is the closeout:
three documentation and test corrections owed by 008, plus one `install.sh`
leftover.

All seven of the brief's acceptance criteria have evidence in the running
system: the installed `pm-flow` command runs the packaged engine with no file
copying; a repository holds only config, overrides, state and store; a
repository-local persona overlays the packaged one and the record names the
layers; the full suite runs to completion through the wheel entry point; an
existing copied-engine install migrates losslessly and keeps running; two
repositories pin different versions and upgrading one leaves its `.agentic/`
byte-identical; and the checkout no longer ships or documents manifest
machinery. Cycle 009 is the last assignment before a completion decision.

## Decisions

- `*.pm-flow.template.md` is not project data. `install.sh` renders it only to
  merge a managed block into a pre-existing `AGENTS.md`/`CLAUDE.md`, and nothing
  reads it afterwards. Cycle 009 stops it being left behind; the one-time
  `*.pre-pm-flow.md` backups and the managed markers are unchanged.
- `install.sh` stays in the checkout, not the wheel, and `pm-flow` gains no
  `init`. The brief's acceptance does not require project-data creation from
  the wheel alone, so the README says where `install.sh` comes from instead.
- Ownership was widened to `tools/manifest.py` and the manifest passages of
  `README.md` after cycle 005: the tool that regenerated `MANIFEST` sat outside
  the allowlist while a rejection condition required its deletion.

## Interfaces

- `tests/packaged_layout_test.sh` is the installed-artifact harness: offline
  hashed wheelhouse, separate build and runtime venvs, data-only fixtures,
  thirteen PASS groups, the last of which executes the README's documented
  commands through the installed wheel.
- The installed `pm-flow` command resolves its engine from the venv and mutable
  project state from the repository it is invoked in.
- A repository-local persona overlay lives at
  `.agentic/pm_flow/<project>/roles/<role>.md`.

## Risks

- A user with only `pip install pm-flow` cannot create project data; they need
  a checkout for `install.sh`. Worth a `pm-flow init` in a later section.
- The build wheelhouse must track Hatchling's Python 3.11+ closure; the harness
  needs a Python with `venv`/`ensurepip`.
- The scoped tier denies `zsh tests/*`, so PM reviews cannot run the suite;
  008's verdict rests on the harness access log and pasted output.

## What is unproven

- `pip install pm-flow` from an index. Every proof installs a locally built
  wheel; whether `pm-flow` is this project's name on PyPI is unknown, and
  `pypi.org` is unreachable from this role. Settled by `pip index versions
  pm-flow` showing this project's release, or by a first publish.
- Behavioural compatibility across versions: the two pinned wheels differ only
  by version stamp. Settled by upgrading across a release that changes engine
  behaviour.
- Cycle 009 itself, until reviewed.

## Next action

Review cycle 009. If it stands, answer `COMPLETE` at the next scope call; the
dependent sections are then re-cut against the packaged layout.
