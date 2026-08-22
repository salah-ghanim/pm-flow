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

## Plan

- One cohesive implementation cycle: move the full managed instructions to the
  AGENTS template, render it on install, reduce the CLAUDE template to a
  managed pointer, preserve pre-existing CLAUDE content, update README, and
  regenerate MANIFEST.
- Review with fresh-install and existing-CLAUDE probes plus the full suite, then
  mutation-test the probes before accepting.

## Decisions and evidence

- The installer dependency is complete; its handoff reports a real fresh install
  and a MANIFEST-driven engine while preserving project state on reinstall.
- `install.sh` still explicitly prefetches `template/CLAUDE.md`, provides
  `merge_claude_rules`, and renders or merges CLAUDE at the end of `main`; these
  are the existing mechanisms to generalize rather than duplicate.
- Existing tests are outside this section's ownership and still inspect the
  compatibility CLAUDE file for managed markers, the rendered task-contract
  path, and the instruction to identify the role. The pointer may retain those
  references but must not duplicate the router or invariants.
- A direct `zsh tests/pm_flow_test.sh` inherited `PM_FLOW_PROJECT=pm-agent` from
  this dispatch and exited 1 while looking for the temporary fixture's contract
  under the wrong key. The isolated baseline command
  `env -u PM_FLOW_PROJECT -u PM_FLOW_ROOT -u PM_FLOW_REPO_ROOT zsh tests/pm_flow_test.sh`
  exited 0 and ended with the four suite PASS lines.
- No earlier implementation cycle exists. At scope time, owned source paths,
  `state.md`, and `handoff.md` had no uncommitted accepted work; only driver
  bookkeeping was dirty.
- Cycle 001 review is `NO_GO`; no implementation was accepted or committed.
  The section branch remains exactly at its base commit with no changed files.
  Independent fresh and existing-repository installs from that worktree create
  no `AGENTS.md`; both leave the complete role router and repo-wide invariants
  in `CLAUDE.md`, while preserving the pre-existing CLAUDE content. `README.md`
  does not identify `AGENTS.md` as the installed instructions source.
- The exact isolated suite exits 0 and reaches all nine PASS groups despite the
  missing target behavior. `python3 tools/manifest.py --check` exits 1 because
  `iter_template_files()` excludes every resolved template path when the
  section worktree itself is nested below a `.git` directory. There is no
  returned implementation to mutate; mutation evidence is therefore impossible
  in this cycle, and the green suite is not evidence for the AGENTS contract.
- The developer's access record names and distinguishes the write mechanism:
  literal writes anywhere in the nested section worktree are refused as
  sensitive, while writes in `/tmp` and the main section record directory are
  allowed. This is an internal dispatch/worktree-placement defect outside this
  section's owned paths, not an external credential, entitlement, or service
  dependency.

## Current assignment

- Do not re-issue the implementation unchanged into the same nested worktree.
  Escalate the observed worktree/sandbox collision so the next developer gets a
  writable section worktree whose path also permits manifest generation; then
  repeat the same bounded implementation and require focused probes capable of
  failing when `AGENTS.md` is absent or `CLAUDE.md` duplicates the full body.

## Dependencies

- `installer`: complete. Its bounded handoff was read for this scope.
- Section execution is currently impeded by the internal worktree location
  `.git/pm-flow/worktrees/...`: the developer could not write owned paths there,
  and `tools/manifest.py` excludes the entire template for the same path shape.
