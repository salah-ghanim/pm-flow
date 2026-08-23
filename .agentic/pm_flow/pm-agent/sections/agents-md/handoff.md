## Outcome

Section `agents-md` is complete on `main` at `4b53d0e`. Installed `AGENTS.md` is the sole full copy of the four-role router and repo-wide invariants; installed `CLAUDE.md` imports it with `@AGENTS.md` and does not duplicate those rules. README names `AGENTS.md` as the instructions file.

Independent validation installed this checkout into fresh Git repositories and repositories with pre-existing instruction files. It proved preservation, one-time backups, managed-block replacement, and same-version reinstall idempotence. Router-removal and rule-duplication mutations were both detected. `zsh tests/pm_flow_test.sh` completed all 10 PASS groups, and `python3 tools/manifest.py --check` reported 77 current files.

## Decisions

- `template/AGENTS.md` owns the complete instructions; `template/CLAUDE.md` is compatibility-only.
- Both files use one file-neutral installer path and `merge_managed_block`. Existing text outside `<!-- pm-flow:begin -->` / `<!-- pm-flow:end -->` survives; each original file is backed up once.
- Both instruction templates are manifest `seed` files so post-render engine synchronization cannot overwrite rendered values with raw placeholders.
- The two failed development cycles were caused by worktrees under `.git`, not product behavior. The worktree-placement and manifest path-exclusion defects are already fixed on `main`; no consultant work remains.

## Interfaces

- Other sections may depend on root `AGENTS.md` containing the rendered router, invariants, and project task-contract path.
- Vendor-specific tooling may depend on root `CLAUDE.md` containing `@AGENTS.md`.
- Installer/packaging must preserve the managed markers, backup names (`AGENTS.pre-pm-flow.md`, `CLAUDE.pre-pm-flow.md`), seed classification, and AGENTS-before-CLAUDE installation order.

## Risks

- `packaging` also changes `install.sh` and `MANIFEST`; conflict resolution could drop this contract. Re-running the manifest check, full suite, focused install probes, and both mutations after its merge would reveal regression.
- Installs retain `*.pm-flow.template.md` prefetch artifacts. This predates the section and is symmetric across both files; packaging should decide whether release cleanup is required.

## What is unproven

- No configured real agent CLI was launched to prove automatic `AGENTS.md` discovery or that a CLAUDE-only client follows `@AGENTS.md`. Launch each supported CLI in an installed repository without injecting either file and observe it follow a unique managed instruction.
- Migration from an actual previously released CLAUDE-only pm-flow install was not exercised. Install the prior release, add user content outside its managed block, upgrade with current `install.sh`, and observe preservation plus a single current block in each instruction file.

## Next action

Close `agents-md`; when packaging reconciles its shared paths, require the post-merge checks named under Risks before release.
