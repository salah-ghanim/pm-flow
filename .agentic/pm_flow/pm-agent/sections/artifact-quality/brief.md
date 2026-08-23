## Objective

- A separate process ranks the project's durable artifacts (plan, briefs,
  workplans, state, handoffs) on length, echo, shape, boundaries and staleness,
  and writes that ranking only into project metadata. No score lives in a
  working document, a section worktree, or a tracked host-repo file.

## Current baseline

- `prompt_quality.py` audits composed *prompts* and writes a sibling
  `*_prompt.manifest.json` next to the prompt. Nothing scores `plan.md`,
  `brief.md`, `workplan.md`, `state.md` or `handoff.md`.
- Handoffs have a hard cap (500 words, 8192 bytes) enforced at complete-time.
  Briefs are checked for headings. There is no ranking, no echo check across
  sibling files, and no coverage check from brief IDs to the workplan table.
- `.agentic/pm_flow/<project>/` other than `project_state/` and `sections/` is
  gitignored. Section worktrees live outside the repository.

## Deliverables

- `src/pm_flow/quality.py`: a standalone ranker invoked as
  `python -m pm_flow.quality rank`.
- `template/.agentic/pm_flow/artifact_quality.md`: the rubric (per-file budgets
  and what each dimension means). Definitions, not scores.
- `tests/artifact_quality_test.sh`.

## User-visible scenarios

1. From a project root, `python -m pm_flow.quality rank` prints the worst live
   artifacts first. Each line names the file and the five dimension findings.
   There is no single quality number.
2. After that command, `git status` in the host repository is unchanged, and
   no file under `sections/` or a linked worktree was written.
3. `.agentic/pm_flow/<project>/quality/latest.md` and `latest.json` exist and
   match the printed ranking. A second run replaces `latest.*` and keeps a
   timestamped snapshot beside them.

## Interfaces produced

- `python -m pm_flow.quality rank [--project <key>]`
- `python -m pm_flow.quality show` — print `quality/latest.md` if present
- Record directory: `<flow_dir>/<project>/quality/` (gitignored metadata)

## Interfaces consumed

- `project_state/plan.md`
- each live section's `brief.md`, `workplan.md`, `state.md`, `handoff.md`
- paragraph-normalization rules already used by `prompt_quality.py` (reuse,
  do not fork)

## Scope

- In: the rubric, the ranker process, the metadata record, the test.
- Out: injecting the ranking into CPO or PM prompts; changing
  `prompt_quality.py`; routing `pm-flow quality` through `cli.py` or
  `pm_flow.sh` (those files are owned elsewhere); scoring prompts, cycle
  transcripts, or source code; a composite score; accuracy-as-a-rubric
  (accuracy stays a probe).

## Non-goals

- A fail-closed gate that blocks `tick` on a weak handoff.
- Model-graded clarity.
- Writing scores into `brief.md`, `state.md`, `handoff.md`, or `plan.md`.

## Priority

- nice-to-have: without this the officer can still read the artifacts; it
  cannot see which ones are sludge without opening all of them, so document
  rot stays invisible until a review.

## Owned paths

- `src/pm_flow/quality.py`
- `template/.agentic/pm_flow/artifact_quality.md`
- `tests/artifact_quality_test.sh`

## Dependencies

- None.

## Constraints and fixed decisions

- No composite score. Dimensions are reported separately. Ranking is by
  number of findings, then by length over budget.
- The ranker never writes inside a section directory, a worktree, or any
  tracked path. A test mutation that points `--out` at `sections/` is
  refused.
- Echo is a paragraph of 12+ words that appears in more than one durable
  file of the same section, or in `plan.md` and a section file.
- Shape is required headings plus brief `A<n>` IDs covered by the workplan
  table. Boundaries are paths or section keys this file does not own.
  Stale is `state.md` restating the workplan, or `plan.md` beginning a
  line with "at review".
- This section does not add a completion criterion to `plan.md`.

## Acceptance

- A1: `python -m pm_flow.quality rank` on the test fixture prints one line
  per scored file, worst first, each naming the file and any of
  `length`, `echo`, `shape`, `boundaries`, `stale`; the output contains no
  composite score and no `quality:` total.
- A2: After that command against this repository, `git status --porcelain`
  is unchanged from immediately before it, and `find` on every
  `sections/*/brief.md` sibling directory shows no new `quality*` or
  `*.score` file.
- A3: The same run writes
  `.agentic/pm_flow/<project>/quality/latest.md`, `latest.json`, and one
  `YYYYMMDDTHHMMSSZ.json` snapshot; `latest.json` lists the same files and
  findings as stdout.
- A4: A fixture handoff that repeats a 12-or-more-word paragraph from its
  brief is ranked with `echo`; removing the copy clears that finding.
- A5: A fixture brief whose workplan table omits `A2` is ranked with
  `shape`; adding the row clears it. A state file that pastes the workplan
  design summary is ranked with `stale`.
- A6: `zsh tests/artifact_quality_test.sh` exits 0. `zsh tests/pm_flow_test.sh`
  and `zsh template/.agentic/pm_flow/tests/run.zsh` still exit 0.

## Rejection conditions

- A score is written into a durable artifact or a section worktree.
- A composite quality number is printed or stored.
- `cli.py`, `pm_flow.sh`, `driver.zsh`, or `prompt_quality.py` is edited.
- The ranker is invoked from `tick` or `dispatch_role`.
- Accuracy is scored without a probe.

## Open questions

- None.
