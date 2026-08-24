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

- Status: accepted cycle 001 (A1, A4, A5 met; precision defects carried to T2).
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

## Task T2 — Make shape and boundaries discriminate

- Status: accepted cycle 002 (A1 met; two follow-ups carried, see state).
- Outcome: a `shape` or `boundaries` finding means something is actually wrong
  with that file. Four defects, all observed on the live `pm-agent` project,
  where 57 of 65 scored artifacts carry `boundaries` and 10 of 15 `shape`
  findings are false:
  - Heading depth. `has_heading` and `markdown_section` match only `^##`,
    while the engine's own brief validator accepts `^#{1,6}`. Five live briefs
    written at depth 3 are reported as missing all seven required headings,
    and every heading-scoped read fails with them, so
    `bullet_values(brief, "Owned paths")` returns nothing and the section is
    scored as owning no path at all. Depth also picks the contract: a depth-3
    `Deliverables` is invisible, so an expanded brief is judged against the
    legacy seven-heading list.
  - Coverage cell grouping. `table_coverage_ids` matches `^| A<n> |` only, so
    a row that groups IDs in one cell (`| A1, A5 | T2 | … |`) covers nothing.
    Five sections are reported as leaving IDs uncovered while their tables
    cover every one. These five plus the five depth-3 briefs are exactly the
    10 false `shape` findings; the other 5 are true and must survive.
  - Path recognition. `looks_like_path` returns true for any inline-code
    token with a dot or a slash, so numbers, dotted identifiers, version
    strings, shell fragments and RPC method names are scored as out-of-
    ownership paths.
  - Declared references. Only Owned paths and Dependencies are allowed, so a
    path the brief itself declares as an interface, a deliverable, a non-goal,
    an acceptance criterion or a rejection condition is still a violation.
    Every brief flags its own declared surface.
- Paths: `src/pm_flow/quality.py`,
  `template/.agentic/pm_flow/artifact_quality.md`,
  `tests/artifact_quality_test.sh`.
- Reuse: the engine's `#{1,6}` heading regex; the rubric's existing dimension
  prose and its runtime-parsed table idiom for any new data. No new dimension,
  no composite, no record files.
- Acceptance IDs: A1.
- Validation: `zsh tests/artifact_quality_test.sh` — fixture artifacts written
  at depth 3, with grouped coverage cells, quoting non-path tokens, and
  declaring a path outside Owned paths each produce no finding, while the
  matching negatives (a genuinely missing heading, a genuinely uncovered ID, a
  real undeclared path) still do. Plus a live `rank` showing the named false
  positives gone and the known true positives still flagged.
- Depends on: T1.

## Task T3 — Metadata-only record

- Status: accepted cycle 003 (A2, A3 and the A1 terminator guard met).
- Outcome: `rank` writes `latest.md`, `latest.json` and one timestamped
  snapshot under `<flow_dir>/<project>/quality/`, and refuses to write
  anywhere else. One guard covers the default destination and `--out` alike:
  a `sections/` directory, a linked git worktree, and a path git does not
  ignore are all refused before any file is created. A run that scores zero
  artifacts fails loudly instead of recording an empty ranking. The suite
  also pins T2's depth-scoped section terminator, which is currently correct
  in code but unpinned by any assertion.
- Paths: `src/pm_flow/quality.py`, `tests/artifact_quality_test.sh`.
- Reuse: `src/pm_flow/paths.py` (`Paths.project_dir`, `repo_root`,
  `relative`) for the layout — read it, do not add a property to it; it is
  not an owned path. Reuse `render()` so stdout and `latest.md` cannot
  diverge.
- Acceptance IDs: A2, A3 (plus the A1 terminator regression guard).
- Validation: `zsh tests/artifact_quality_test.sh` — after `rank` on this
  repo, `git status --porcelain` equals the pre-run snapshot; no new file
  under any `sections/*`; `quality/latest.json` matches stdout; `--out`
  inside `sections/` exits non-zero and writes nothing; reverting
  `markdown_section`'s terminator to `^#{1,2}` fails an assertion.
- Depends on: T2.

## Task T4 — Show, and prove the suites still pass

- Status: pending.
- Outcome: `python -m pm_flow.quality show` prints `latest.md` or says none
  exists. The new test and the existing engine suites exit 0.
- Paths: `src/pm_flow/quality.py`, `tests/artifact_quality_test.sh`.
- Reuse: T3's record layout.
- Acceptance IDs: A1, A3, A6.
- Validation: `zsh tests/artifact_quality_test.sh` — `show` after `rank`
  reprints `latest.md`; `show` on an empty quality dir prints a one-line
  absence. `zsh tests/pm_flow_test.sh` and
  `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0.
- Depends on: T3.

## Integration and end-to-end validation

- T3 plus T4 are the user-visible scenarios: rank, metadata only, show.
  Run them against this repository as well as the fixture.

## Risks and rollback

- A future owner might route this through `tick` or `cli.py`. Rollback is
  delete the three owned paths; records under `quality/` are already
  untracked. Do not add a `pm-flow quality` arm in this section.
- T3 writes findings into `latest.json`. T2 lands first so the first record
  is readable as truth rather than as noise.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T3, T4 | Per-file dimension lines; no composite; a finding names a real defect |
| A2 | T3 | `git status` unchanged; no write under `sections/` |
| A3 | T3, T4 | `quality/latest.md` + `latest.json` + snapshot |
| A4 | T1 | Echo finding flips with the copied paragraph |
| A5 | T1 | Shape and stale findings flip with the fixture edits |
| A6 | T4 | This test and both existing suites exit 0 |
