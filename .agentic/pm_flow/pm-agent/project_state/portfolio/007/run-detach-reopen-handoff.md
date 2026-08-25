## Outcome

- Reopened by portfolio review 007: the blocking dependency is resolved.
  `install.sh` joined Owned paths on 2026-08-25, limited to three registry
  entries (see the brief's boundary extension). T1a is assignable.
- Everything else is on `main`: the supervisor, the routed `pm-flow
  run-detach` arm, the doc, and `zsh tests/run_detach_test.sh` exits 0.

## Decisions

- Review 007 decided this section registers all three migration names, not
  only its own: `run_detach.zsh` and `artifact_quality.md` in
  `COPIED_ENGINE_FILES`, `cards` in `COPIED_ENGINE_DIRS`. Their shipping
  sections are terminal and `zsh tests/packaged_layout_test.sh` — this
  section's own A7/A8 gate — is red on `main` naming exactly those three.

## Interfaces

- `pm-flow run-detach start|stop|status` and its `pid=`/`log=` lines,
  unchanged.

## Risks

- `zsh tests/packaged_layout_test.sh` stays red until the three entries
  land; every section gating on it inherits the failure.

## What is unproven

- A7's packaged-layout half and A8: `zsh tests/packaged_layout_test.sh`
  exit 0 with the three names registered.

## Next action

- Scope T1a: add the three registry entries to `install.sh`; settle with
  `zsh tests/packaged_layout_test.sh` exit 0 and `zsh
  tests/run_detach_test.sh` exit 0.
