# artifact-quality section PM state

## Current task

- T1b — make shape and boundaries discriminate. Next to assign.

## Completed tasks and evidence

- T1 — rubric and scorer. Accepted cycle 001. Acceptance IDs A1, A4, A5.
  - `zsh tests/artifact_quality_test.sh` against the section worktree printed
    three PASS lines and exited 0.
  - A1: on the fixture, `rank` printed 9 lines for 9 files, worst first
    (`sections/alpha/brief.md` with 3 findings, then 2, then 1, then four
    `findings: none`). Each line names the file and its dimensions; all five
    of `length`, `echo`, `shape`, `boundaries`, `stale` appear; no composite
    and no `quality:` total. `beta/brief.md` holds the same paragraph as
    `alpha`'s and correctly shows no `echo`, so cross-section repetition is
    excluded.
  - A4/A5 mutation-proven, not just asserted: disabling echo detection,
    the coverage check, and the stale check each made the named assertion
    fail (`FAIL: fixture did not produce echo finding`, `… shape finding`,
    `FAIL: pasted design summary did not produce stale`). Recorded in
    `cycles/001/review_mutations.sh`.
  - Budgets are parsed, not hardcoded: raising the rubric's `brief.md` budget
    to 99999 produced `FAIL: fixture did not produce length finding`, and
    renaming the table header produced
    `rubric has no '| File | Word budget |' table`.
  - Read-only, and T2 was not pulled forward: a `find` of the fixture project
    before and after `rank` shows no created file, and no `quality*` or
    `*.score` path exists.
  - Suite is env-independent: it passes with hostile `PM_FLOW_PROJECT`,
    `PM_FLOW_ENGINE_ROOT`, `PM_FLOW_REPO_ROOT` and `PYTHONPATH` exported.
  - Reuse confirmed: `quality.py` calls `prompt_quality.py`'s
    `normalized_paragraphs` / `words` / `Finding` loaded by
    `spec_from_file_location`; it restates no 12-word rule. Working tree adds
    only the three owned paths and modifies nothing.

## Active decisions

- Ranking is a separate process. Scores live only under
  `.agentic/pm_flow/<project>/quality/`.
- No composite score. No `tick` hook. No edits to `cli.py` or `pm_flow.sh`.
- Echo reuse is by **path load, not import**. `prompt_quality.py` is an engine
  file (`template/.agentic/pm_flow/prompt_quality.py` in a checkout,
  force-included as `pm_flow/engine/` in the wheel per `pyproject.toml:51`).
  `pm_flow/engine/` has no `__init__.py`, and in a checkout it is outside
  `src/`, so `from pm_flow.engine.prompt_quality import ...` is not portable
  across the two layouts. `quality.py` loads it from `paths.engine_root()`
  via `importlib.util.spec_from_file_location`, the same way `cli.py` reaches
  `pm_flow.sh` by path.
- `normalized_paragraphs` already returns only paragraphs of 12+ words, which
  is exactly the brief's echo threshold. Do not restate the 12-word rule in
  `quality.py`; that constant stays owned by `prompt_quality.py`.
- A2/A3 are structurally safe: `.gitignore` ignores
  `.agentic/pm_flow/pm-agent/*` and re-includes only `project_state/` and
  `sections/`, so the `quality/` record dir is untracked by construction.
  Evidence still has to be observed, not assumed.

- Two dimensions do not discriminate yet, so a finding in them does not mean
  the file is wrong. Observed on the first real run against `pm-agent`:
  `shape` requires `^##` while the engine's brief validator
  (`pm_flow.sh:1156`) accepts `^#{1,6}`, so six live briefs that write all
  seven headings at depth 3 are reported as missing all seven; and
  `looks_like_path` accepts any dotted or slashed inline-code token, so
  `0.25`, `os.environ` and `2>/dev/null` are scored as unowned paths. The
  fixture uses `##` headings and real paths only, which is why the suite
  cannot see either defect. T1b carries both, with the negative cases named.
- The live `project_state/plan.md` reporting all seven plan headings missing
  is a true positive, not this defect: its headings genuinely differ from the
  engine template's.

## Blockers

- None observed.

## Next eligible task

- T1b — make shape and boundaries discriminate.
