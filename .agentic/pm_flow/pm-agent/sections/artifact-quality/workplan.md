# artifact-quality workplan

## Design summary

- A packaged module, run as its own process, reads the durable artifacts and
  writes a ranking under the project's gitignored metadata directory. It
  reuses `prompt_quality.py`'s paragraph normalization for echo; it does not
  hook `tick`, edit `cli.py` / `pm_flow.sh`, or write into section files.

## Interfaces and data changes

- `python -m pm_flow.quality rank|show`
- Record dir: `.agentic/pm_flow/<project>/quality/{latest.md,latest.json,<utc>.json}`
- Rubric file: `template/.agentic/pm_flow/artifact_quality.md`
- No store schema change. No writes under `sections/` or a worktree.

## Task T1 — Rubric and scorer

- Status: accepted cycle 001 (A1, A4, A5 met; precision defects carried to T1b).
- Outcome: `artifact_quality.md` defines budgets and the five dimensions;
  `quality.py` loads it and scores a fixture tree for `length`, `echo`,
  `shape`, `boundaries`, `stale` with no composite total.
- Paths: `src/pm_flow/quality.py`,
  `template/.agentic/pm_flow/artifact_quality.md`,
  `tests/artifact_quality_test.sh`.
- Reuse: `prompt_quality.py` `normalized_paragraphs` / word counting; do not
  copy a second definition of a duplicate paragraph.
- Acceptance IDs: A1, A4, A5.
- Validation: `zsh tests/artifact_quality_test.sh` — fixture rank prints
  per-file dimension findings, no composite; echo/shape/stale mutations
  flip the named finding and nothing else.
- Depends on: None.

## Task T1b — Make shape and boundaries discriminate

- Status: pending.
- Outcome: a finding in either dimension means something is wrong with the
  file. Two defects observed in cycle 001's first real run:
  - `has_heading` matches only `^##`, but the engine's own brief validator
    (`pm_flow.sh:1156`) accepts `^#{1,6}`. Six live briefs write all seven
    required headings at depth 3 and are reported as missing all seven.
    Match the engine's depth range.
  - `looks_like_path` returns true for any inline-code token with a dot or a
    slash, so `0.25`, `os.environ`, `2>/dev/null` and `v1.36.0` are scored as
    out-of-ownership paths. `boundaries` then fires on nearly every artifact
    with dozens of non-path entries and carries no signal.
- Paths: `src/pm_flow/quality.py`, `tests/artifact_quality_test.sh`.
- Reuse: the rubric's existing dimension prose; no new dimension.
- Acceptance IDs: A1.
- Validation: `zsh tests/artifact_quality_test.sh` — a fixture brief whose
  headings are all `###` produces no heading `shape` finding, while one that
  genuinely omits a heading still does; a fixture file quoting `0.25` and
  `os.environ` produces no `boundaries` finding, while one quoting a real
  unowned path still does.
- Depends on: T1.

## Task T2 — Metadata-only record

- Status: pending.
- Outcome: `rank` writes `latest.md`, `latest.json` and one timestamped
  snapshot under `<flow_dir>/<project>/quality/`. An `--out` aimed at
  `sections/` or a worktree is refused. The host `git status` is unchanged.
- Paths: `src/pm_flow/quality.py`, `tests/artifact_quality_test.sh`.
- Reuse: `src/pm_flow/paths.py` for engine / flow / repo roots.
- Acceptance IDs: A2, A3.
- Validation: `zsh tests/artifact_quality_test.sh` — after `rank` on this
  repo, `git status --porcelain` equals the pre-run snapshot; no new file
  under any `sections/*`; `quality/latest.json` matches stdout; `--out`
  inside `sections/` exits non-zero and writes nothing.
- Depends on: T1.

## Task T3 — Show, and prove the suites still pass

- Status: pending.
- Outcome: `python -m pm_flow.quality show` prints `latest.md` or says none
  exists. The new test and the existing engine suites exit 0.
- Paths: `src/pm_flow/quality.py`, `tests/artifact_quality_test.sh`.
- Reuse: T2's record layout.
- Acceptance IDs: A1, A3, A6.
- Validation: `zsh tests/artifact_quality_test.sh` — `show` after `rank`
  reprints `latest.md`; `show` on an empty quality dir prints a one-line
  absence. `zsh tests/pm_flow_test.sh` and
  `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0.
- Depends on: T2.

## Integration and end-to-end validation

- T2 plus T3 are the user-visible scenarios: rank, metadata only, show.
  Run them against this repository as well as the fixture.

## Risks and rollback

- A future owner might route this through `tick` or `cli.py`. Rollback is
  delete the three owned paths; records under `quality/` are already
  untracked. Do not add a `pm-flow quality` arm in this section.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T1b, T3 | Per-file dimension lines; no composite; a finding names a real defect |
| A2 | T2 | `git status` unchanged; no write under `sections/` |
| A3 | T2, T3 | `quality/latest.md` + `latest.json` + snapshot |
| A4 | T1 | Echo finding flips with the copied paragraph |
| A5 | T1 | Shape and stale findings flip with the fixture edits |
| A6 | T3 | This test and both existing suites exit 0 |
