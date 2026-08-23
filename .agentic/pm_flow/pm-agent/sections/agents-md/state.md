# agents-md section PM state

## Objective

- Make installed `AGENTS.md` the sole full copy of pm-flow's role router and
  repo-wide invariants, with `CLAUDE.md` limited to a compatibility pointer and
  existing repository content preserved.

## Owned paths

- `template/AGENTS.md`
- `template/CLAUDE.md`
- `README.md`
- `install.sh`, limited to instruction-template prefetching, managed-block
  merging, and the `AGENTS.md`/`CLAUDE.md` rendering block.
- `MANIFEST`, generated only by `python3 tools/manifest.py --write`.

## Where this section actually stands

**The implementation is on `main` as `4b53d0e` and every acceptance criterion in
the brief is met.** Read this section before reading the cycle history below,
because that history describes a state the repository has since left.

Cycles 001 and 002 failed for the harness, not the work. The rescue that
followed them succeeded, committed a complete implementation to
`pm-flow/pm-agent/agents-md-rescue-1` (`a9790f2`), and was then killed before it
wrote its result file, so the driver never reviewed or merged it and the section
record never learned that the work existed. The deliverable was salvaged onto
`main` deliberately, its escalation directory was archived rather than resumed
(`escalation-archived-20260823T082009Z/why_archived.md`), and the section was
reconciled in `f16a0ae`. Nothing here is waiting on a consultant.

## Evidence, re-verified against the current `main`

Two fresh `git init` repositories and one with pre-existing content, installed
from this checkout with
`env -u PM_FLOW_PROJECT -u PM_FLOW_ROOT -u PM_FLOW_REPO_ROOT ./install.sh <repo> --name <name>`:

- **Fresh install writes the router and invariants.** A 58-line `AGENTS.md`
  appears at the repository root carrying the role router (all four roles) and
  the repo-wide invariants in full, including the driver-commits rule.
- **A pre-existing `CLAUDE.md` is preserved.** Its own content stays at the top
  of the file, untouched, with the managed block merged in below it between
  `<!-- pm-flow:begin -->` and `<!-- pm-flow:end -->`, and backed up once as
  `CLAUDE.pre-pm-flow.md`. The rendered `CLAUDE.md` is a 17-line pointer that
  imports `@AGENTS.md` and keeps no copy of the rules.
- **A pre-existing `AGENTS.md` is preserved the same way.** This was recorded as
  unproven in the previous handoff and has now been exercised: content kept,
  one managed block merged, `AGENTS.pre-pm-flow.md` written, `CLAUDE.md` pointer
  created. `merge_managed_block` is file-neutral, which is why both paths behave
  identically.
- **Reinstalling is idempotent.** A second install of the same repository leaves
  exactly one managed block in each file and the pre-existing content intact.
- **README names it.** `README.md` describes `AGENTS.md` as the instructions
  file at lines 41, 44, 120 and 161.
- **The suite passes.** `zsh tests/pm_flow_test.sh` exits 0 with 10 PASS groups,
  and `python3 tools/manifest.py --check` reports the manifest current at 77
  files.

Observed and deliberately not treated as a defect: an install leaves
`CLAUDE.pm-flow.template.md` (and `AGENTS.pm-flow.template.md` where that file
pre-existed) in the target repository. That is the prefetch artifact, it predates
this section, it is symmetric across both instruction files, and no acceptance
criterion speaks to it. Raise it with `packaging` if it should be cleaned up;
do not reopen this section for it.

## History, retained for the record

- Cycles 001 and 002 were both `NO_GO`, and neither returned an implementation.
  The cause was harness, not product: this section's worktrees were placed under
  `.git/`, where agent write controls refuse the paths as sensitive and
  `tools/manifest.py` enumerated 0 of 74 template files. Those worktrees have
  been removed and the branches survive.
- `main` has since fixed both independently — worktree placement in
  `driver.zsh`, path exclusion in `tools/manifest.py` — so neither obstruction
  can recur here.
- Not salvaged from the rescue branch: its own copies of those two fixes. `main`
  reached both with the same reasoning while the branch sat unmerged.

## Current assignment

- None. Do not re-issue the implementation and do not escalate: both would
  re-solve a solved problem. The only thing this section still owes is a
  completion review. Re-run the acceptance checks above yourself, and if they
  hold, answer `COMPLETE`.

## Dependencies

- `installer`: complete. Its bounded handoff was read at scope time.
- `packaging` also claims `install.sh` and `MANIFEST` and is mid-flight on both.
  This section's work is committed, so the exposure is a merge conflict on
  packaging's branch, not a race.
