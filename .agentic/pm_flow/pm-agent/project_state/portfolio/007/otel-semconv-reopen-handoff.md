## Outcome

- Reopened by portfolio review 007: `zsh tests/otel_semconv_test.sh` exits 1
  on `main`, twice, deterministically. After the test pins the secondary
  tree to v1.36.0 (`tests/otel_semconv_test.sh:553-557`, and its own grep
  confirms the edit), the secondary dispatch's exported span still reports
  revision `v1.37.0`.

## Decisions

- Review 007: acceptance is unchanged. The work is to make the section's own
  suite exit 0 from this host; no criterion is reduced.

## Interfaces

- None new. The primary arm still passes: parent/child GenAI split and token
  counts print as expected before the secondary assertion fails.

## Risks

- Suspected cause, unverified: the secondary dispatch resolves
  `pm_flow.semconv` through the host's editable venv install
  (`src/pm_flow/semconv.py`, `REVISION = "v1.37.0"`, line 16) rather than
  the secondary tree's sed-edited copy. `resolved_semconv_path` prints the
  sed-edited file, so the resolution check and the dispatch disagree.

## What is unproven

- `zsh tests/otel_semconv_test.sh` exit 0 on this host.

## Next action

- Scope one cycle: establish which module the secondary dispatch actually
  imports, fix the isolation (test or telemetry resolution, both owned), and
  settle with `zsh tests/otel_semconv_test.sh` exit 0.
