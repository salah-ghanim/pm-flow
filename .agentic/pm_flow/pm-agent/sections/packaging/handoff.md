# packaging section handoff

## Outcome

- Cycle 003 is accepted. The packaged-layout proof now builds and installs the current wheel entirely from repository-local, pinned, hashed build inputs, while preserving the installed-engine/project-data boundary and full-suite selector isolation.

## Decisions

- Replace the rejected `uv` build path with a build venv installed from `tests/packaging-build-wheelhouse` using `--no-index`, `--find-links`, and `--require-hashes`; build with `pip wheel --no-build-isolation --no-deps`.
- Install the produced pm-flow wheel into a separate clean runtime venv. The runtime proof rejects Hatchling leakage and checkout-backed installation metadata.
- Keep the Cycle 001 engine/data split and Cycle 002 `PM_FLOW_*` selector cleanup unchanged.
- The full suite currently emits nine PASS groups, not the stale seven named by the assignment. Both exact runs emitted the identical nine groups.

## Interfaces

- `tests/packaged_layout_test.sh` is the reusable installed-artifact harness: offline build venv, built wheel, clean runtime venv, fixture repository containing project data only.
- `tests/packaging-build-wheelhouse/build-requirements.txt` is the hash-locked build-backend closure; every stored wheel is `py3-none-any`.
- The installed `pm-flow` command resolves its engine from the runtime venv and mutable project state from the invoked repository.

## Risks

- The checked-in build wheelhouse must be kept in step with Hatchling's complete Python 3.11+ dependency closure and hashes.
- The harness requires a Python installation that provides `venv`/`ensurepip`, consistent with pm-flow's declared Python requirement but not universal across split-package Linux distributions.

## What is unproven

- Dispatch has not yet been exercised end to end through the installed artifact.
- Repository-local persona overlay order and provenance over packaged defaults are not yet established.
- Independent version pinning, package-upgrade immutability, legacy migration equivalence, and removal of MANIFEST/upgrade/copy lifecycle machinery remain later work.

## Next action

- Scope Cycle 004 as the smallest installed-artifact dispatch and persona-overlay proof. Reuse the accepted wheel harness and path model, and keep installer/migration/deletion work out of that cycle.
