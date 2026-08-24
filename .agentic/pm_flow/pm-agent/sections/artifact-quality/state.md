# artifact-quality section PM state

## Current task

- None. T1–T4 are all accepted; the workplan has no unfinished task. Every
  brief acceptance ID (A1–A6) has recorded evidence below. (T2 was first
  written as `T1b`; workplan IDs are `T<number>` only, so it became T2 and the
  record/show tasks renumbered to T3 and T4.)
- T1–T3 are merged to `main`: `bbf704c`, `adba805`, `67d200c` on
  `src/pm_flow/quality.py` and `tests/artifact_quality_test.sh`. T4 is accepted
  cycle 004 and awaiting the driver's merge.

## Completed tasks and evidence

- T4 — `show`, and both unowned suites still green. Accepted cycle 004.
  Acceptance IDs A1, A3, A6. Worktree `git status --porcelain` shows exactly
  `src/pm_flow/quality.py` and `tests/artifact_quality_test.sh`
  (+61/−1 lines); no `show` arm was added to `tick`, `dispatch_role`,
  `cli.py` or `pm_flow.sh`.
  - A1/A3 fixture: `zsh <worktree>/tests/artifact_quality_test.sh` → exit 0
    with eleven PASS lines, the new one being `PASS: show reprints the record
    byte-for-byte, stays read-only, and distinguishes absence from refusal`.
    (The assignment said "nine existing"; there are ten. The assignment's
    count was stale, not a missing assertion.)
  - A3 on this repository, every `PM_FLOW_*` unset then
    `PM_FLOW_REPO_ROOT=/Users/salah/code/personal/pm-flow`,
    `PYTHONPATH=<worktree>/src`: `rank --project pm-agent` exit 0,
    `show --project pm-agent` exit 0, both stderr empty. `git status
    --porcelain` before vs after → `cmp` exit 0. `show` stdout vs `rank`
    stdout → `cmp` exit 0. `show` stdout vs
    `.agentic/pm_flow/pm-agent/quality/latest.md` → `cmp` exit 0. The record
    dir gained exactly one snapshot (`20260824T222340Z.json`) beside
    `latest.md` and `latest.json`. `grep -c 'quality:'` over `show` stdout → 0,
    and over `latest.json` → 0, so no composite leaked.
  - A6: `zsh <worktree>/tests/pm_flow_test.sh` → exit 0 (last line `PASS:
    independent consultant panel and CPO adjudication`);
    `zsh <worktree>/template/.agentic/pm_flow/tests/run.zsh` → exit 0
    (`totals: pass=74 fail=0`, `all suites passed`). Neither suite was edited.
  - Negative checks, each in a scratch copy of the worktree, each run to a
    failing assertion:
    - absence falls through to an empty string instead of raising → exit 1,
      `FAIL: show exited successfully without a quality record`.
    - `sys.stdout.write(text.strip())` → exit 1, `FAIL: show stdout differs
      from latest.md`, so byte identity is pinned and not merely asserted.
    - `--out` bypasses `resolve_record_dir` → exit 1, `FAIL: missing-record
      error did not name the resolved directory`. It trips the absence
      assertion first (that assertion greps the *realpath* of the temp dir,
      which only the shared resolver produces), so the suite catches the
      bypass but names the wrong symptom. Cosmetic; the refusal itself is
      still separately asserted.

- T3 — metadata-only record. Accepted cycle 003. Acceptance IDs A2, A3, plus
  the A1 terminator regression guard. Only `src/pm_flow/quality.py` and
  `tests/artifact_quality_test.sh` changed; the rubric, `paths.py`, `cli.py`,
  `pm_flow.sh` and `driver.zsh` are untouched.
  - Suite: `zsh tests/artifact_quality_test.sh` against the section worktree
    exited 0 with nine PASS lines, including refusals for `--out` inside
    `sections/`, a linked worktree, a git-visible path, and a zero-artifact
    project — each asserting the destination was *not* created.
  - A2 on this repository, cwd `/Users/salah/code/personal/pm-flow` (a real
    checkout, `.git` a directory), `PYTHONPATH` pointed at the worktree src:
    `git status --porcelain` before and after `rank --project pm-agent` are
    byte-identical (`cmp` → IDENTICAL, 24 lines each), and
    `find .agentic/pm_flow/pm-agent/sections \( -name 'quality*' -o -name
    '*.score' \)` prints nothing.
  - A3 on this repository: the run wrote `quality/latest.md`, `latest.json`
    and `20260824T220350Z.json` beside the earlier `20260824T220256Z.json`,
    so a second run replaces `latest.*` and keeps both snapshots.
    `git check-ignore -v .agentic/pm_flow/pm-agent/quality/latest.json` →
    `.gitignore:24:.agentic/pm_flow/pm-agent/*`.
  - `latest.md` is byte-identical to stdout (`cmp` → IDENTICAL) because both
    consume the same `rendered` list. `latest.json` was parsed and compared
    against stdout field by field over all 65 artifacts: order equal True,
    findings equal True, entry keys uniformly
    `{file, words, budget, over, findings}`, top-level keys
    `{project, generated_at, artifacts}`. No composite: a
    `composite|quality:[0-9]|score[=:][0-9]` grep over stdout, `latest.md` and
    `latest.json` returns 0 hits in each.
  - The guard runs before anything is created — `resolve_record_dir` is the
    first statement of `rank()`, ahead of `collect_artifacts` and `mkdir`.
  - A1 terminator now pinned. Reverting the depth-scoped terminator to
    `end = re.search(r"(?m)^#{1,2}\s+", tail)` in a scratch copy fails the
    suite (exit 1) at
    `FAIL: depth terminator fixture incorrectly produced stale:
    .agentic/pm_flow/fixture/sections/delta/state.md | echo: 1 normalized
    paragraph(s) repeat in another durable file | stale: state repeats the
    workplan design summary`. The unmutated scratch copy runs past that
    assertion, so the failure is the mutation, not the copy.
  - No collateral drift, proven differentially rather than by target numbers:
    the pre-change `quality.py` from the main checkout and the worktree build
    produce byte-identical stdout over the same 65 live artifacts. Live counts
    `shape` 5, `echo` 0, `stale` 0, `boundaries` 50 as expected. `length` is
    18, not the assignment's 17, in **both** builds — a durable artifact grew
    past budget since the assignment was written. Live counts are a moving
    baseline; compare builds, not remembered numbers.

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
  - Carried to T3: the depth-scoped terminator is correct in code but
    unpinned by the suite — restoring the old `^#{1,2}` terminator under the
    new matcher still passes every assertion, so T3 adds a fixture that fails
    under that mutation. The second follow-up, whether slash-bearing
    non-paths need another precision pass, is measured and settled below.

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
  What survives as noise is slash-bearing non-paths — JSON-RPC method names,
  a URL path and a token count. That is the assignment's deliberate rule: a
  slash-bearing token free of shell metacharacters counts as a path.
- Settled at scope 003, by measurement, not hunch: the surviving non-paths do
  not warrant another precision pass. Live `rank` on `pm-agent` over 65 files
  flags 673 boundary tokens, 398 distinct. Of the 21 distinct slash-bearing
  tokens carrying no dot, 11 are genuinely paths (`src/pm_flow`,
  `pm_flow/engine/topologies`, `cycles/003`, `driver-bin/claude`, `/tmp`, …).
  The noise set is 10 distinct tokens — `/`, `/v1/traces`, `13937in/5out`,
  and seven JSON-RPC method names (`tools/call`, `session/prompt`,
  `session/new`, `session/cancel`, `session/request_permission`,
  `resources/list`, `notifications/initialized`) — 20 of 673 occurrences
  (3.0%), spread over 6 of 65 files, and not one of those 6 is flagged
  *only* by noise. Any rule that rejects them (a method-name denylist, or
  requiring an extension on a slashed token) would also reject real
  extensionless directories, which are 11 of the same 21. Accept the noise.
  Reopen only if a future census puts it above roughly 10% of tokens.
- Writing the record has a hazard the ranker does not have today: run from a
  section worktree with `--project pm-agent`, `find_repo_root` resolves to the
  worktree, so the default record dir lands *inside* a worktree — which the
  brief forbids. The T3 guard must therefore cover the default destination,
  not just `--out`. With no `--project` and no `.project-key` the worktree
  scores zero files and exits 0 silently; T3 makes that a loud failure so an
  empty ranking is never recorded as truth.
- The ignore check is skipped whenever `git check-ignore` cannot judge the
  target: `--out` at any path outside the flow repository exits 128 with
  `is outside repository`, and `resolve_record_dir` treats that as permission.
  Observed: `--out /tmp/<other-git-repo>/quality` from this checkout exits 0
  and writes `latest.md` / `latest.json` into that other repository's tracked
  working tree. This is the T3 assignment's own escape hatch, needed so the
  fixture temp dir can be written, and it costs nothing for A2 — the *default*
  destination is always inside the flow repo, where the check does apply. Do
  not tighten it by failing closed on 128; that would break the fixture. If it
  ever needs closing, run `git check-ignore` with `cwd` at the *target's* own
  repository root instead of `layout.repo_root`.
- Live dimension counts are not a fixed baseline. Between cycles 002 and 003
  `length` moved 16 → 18 with no code change, because the sections keep
  writing. Assert drift by diffing two builds over the same tree in one
  sitting, never against a count recorded in an earlier assignment.
- Ranking two dimensions by *file* count hides precision work. Between cycle
  001 and 002 the flagged-token count fell 1104 → 683 while the per-file
  `boundaries` count moved only 59 → 50, because better recognition also finds
  real paths the old regex missed. Measure this dimension by token.

## Blockers

- None observed. `.gitignore:20-28` ignores `.agentic/pm_flow/pm-agent/*` and
  re-includes only `project_state/` and `sections/`, so the record dir is
  untracked by construction: `git check-ignore -v
  .agentic/pm_flow/pm-agent/quality/latest.md` returns
  `.gitignore:24 .agentic/pm_flow/pm-agent/quality/latest.md`.
- Six `review_002*.sh`, seven `scope_probe*.sh` and now four `review_003*`
  read-only probe scripts sit in this section directory from earlier cycles.
  Removing them needs an approval the roles have not had; they affect nothing.
- The developer's sandbox denies writes under
  `/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/quality`
  (`PermissionError: [Errno 1] Operation not permitted`). It hit cycle 003 and
  again cycle 004, both times on the host `rank` write, never on the fixture.
  The review re-ran the identical command in both cycles with no denial, so it
  is a developer-workspace permission limit, not a code defect. Any future
  host-write acceptance should be assigned expecting the developer to reach
  only the read-only fallback, with the review supplying the write branch.

## Next eligible task

- None — the workplan is complete. The section's remaining obligation is the
  driver's merge of cycle 004.
