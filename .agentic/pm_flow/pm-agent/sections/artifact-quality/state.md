# artifact-quality section PM state

## Current task

- T3 — metadata-only record. Next to assign. (T2 was first written as `T1b`;
  workplan IDs are `T<number>` only, so it became T2 and the record/show tasks
  renumbered to T3 and T4.)

## Completed tasks and evidence

- T2 — make shape and boundaries discriminate. Accepted cycle 002. Acceptance
  ID A1. All four defects fixed in one function each; only the three owned
  paths changed.
  - Suite: `zsh tests/artifact_quality_test.sh` against the section worktree
    exited 0 with four PASS lines. The depth-3 `gamma` section prints
    `findings: none` for all four of its artifacts, while its three negatives
    still fire: `shape: missing headings: Open questions`,
    `shape: acceptance IDs absent from workplan coverage table: A3`, and
    `boundaries: references outside section ownership: foreign/undeclared.py`.
  - The suite discriminates, it was not written to the old behaviour: running
    the new test against the cycle-001 `quality.py` fails with
    `FAIL: live-style gamma brief.md was not finding-free` — that build reports
    the depth-3 brief as missing all seven legacy headings, as uncovering
    A1/A2, and as violating on its declared `shared/gamma/input.json`.
  - Live `rank` on `pm-agent` with every `PM_FLOW_*` and `PYTHONPATH` unset,
    old scorer vs new over the same 65 files: `shape` 15 → 5, and the five are
    exactly the known true positives — `project_state/plan.md` (all seven plan
    headings) plus `agents-md`, `green-suite`, `installer` and
    `worktree-isolation` state files (all five state headings). No true
    positive was lost.
  - Depth now selects the contract: 12 of 17 live briefs resolve to the
    expanded 15-heading list, `run-detach` among them, and every live brief
    reports zero missing headings.
  - Declared references work: this section's own brief went from 17 flagged
    tokens — including `prompt_quality.py`, `cli.py` and `pm_flow.sh` — to
    `findings: none`.
  - Boundaries improved by token, not by file: 1104 → 683 flagged tokens, 247
    distinct tokens dropped. The per-file count only fell 59 → 50, because
    tighter recognition also newly resolves 78 real path forms the old regex
    missed — line *ranges* (`driver.zsh:610-624`; the old suffix rule accepted
    only `:<n>`) and long or hyphenated dotfiles (`.gitignore`,
    `.project-key`). Those additions are correct, so the assignment's
    "well below 57" per-file target was the wrong yardstick, not a shortfall
    in the work.
  - No collateral drift: `length` 16 → 16, `echo` 0 → 0, `stale` 0 → 0 across
    the same live run, so the widened `markdown_section` did not turn state
    files stale.
  - Carried to T3: (a) the depth-scoped terminator is correct in code but
    unpinned by the suite — restoring the old `^#{1,2}` terminator under the
    new matcher still passes every assertion, so add a fixture whose depth-3
    section is followed by a depth-2 heading; (b) decide whether surviving
    slash-bearing non-paths (`tools/call`, `session/prompt`, `13937in/5out`)
    warrant another precision pass or are accepted noise.

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

- `shape` now discriminates: on the live project every finding names a real
  defect, and the only five are `project_state/plan.md` plus the `agents-md`,
  `green-suite`, `installer` and `worktree-isolation` state files. Those five
  write depth-2 headings whose *names* genuinely differ from the contract, so
  no depth fix can clear them. Treat any new `shape` finding as true.
- `boundaries` discriminates for declared surfaces but not yet for every token
  shape. A path stated in inline code anywhere in the section's own brief is
  allowed; a path present only in a workplan or state is still a violation.
  What survives as noise is slash-bearing non-paths — JSON-RPC method names
  (`tools/call`, `session/prompt`, `resources/list`), and token counts like
  `13937in/5out`. That is the assignment's deliberate rule: a slash-bearing
  token free of shell metacharacters counts as a path. Revisit only with a
  measurement, not a hunch.
- Ranking two dimensions by *file* count hides precision work. Between cycle
  001 and 002 the flagged-token count fell 1104 → 683 while the per-file
  `boundaries` count moved only 59 → 50, because better recognition also finds
  real paths the old regex missed. Measure this dimension by token.

## Blockers

- None observed.

## Next eligible task

- T3 — metadata-only record. Fold in T2's two carried follow-ups: pin the
  depth-scoped section terminator with a fixture, and settle whether the
  surviving slash-bearing non-paths need another pass.
