#!/bin/zsh -f
set -uo pipefail

WORKTREE=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
MAIN=/Users/salah/code/personal/pm-flow
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm-review.XXXXXX")"
print -r -- "tmp=$TMP"

print -r -- ""
print -r -- "=== negative control: pre-change install.sh (main) on the new fixture ==="
OLD_REPO="$TMP/old fixture"
mkdir -p "$OLD_REPO"
"$WORKTREE/tests/fixtures/real_install/build_fixture.sh" "$MAIN" "$OLD_REPO"
"$MAIN/install.sh" "$OLD_REPO" --project-key beta --name "Golden Grid Fixture" \
  > "$TMP/old.out" 2>&1
print -r -- "old_install_exit=$?"
grep -E 'removed_copied_engine|project_key=|WARNING' "$TMP/old.out" || true
for k in alpha beta gamma project; do
  if [[ -d "$OLD_REPO/.agentic/pm_flow/$k" ]]; then
    print -r -- "old: workspace $k SURVIVED"
  else
    print -r -- "old: workspace $k LOST"
  fi
done
print -r -- "old projects.md entries:"
grep -E '^- `' "$OLD_REPO/.agentic/pm_flow/projects.md" || true

print -r -- ""
print -r -- "=== flow dir that exists with no workspace: old vs new resolve ==="
for variant in old new; do
  if [[ "$variant" == old ]]; then SCRIPT="$MAIN/install.sh"; else SCRIPT="$WORKTREE/install.sh"; fi
  REPO="$TMP/$variant-empty"
  mkdir -p "$REPO/.agentic/pm_flow"
  git -C "$REPO" init --quiet
  printf '{"version": 1}\n' > "$REPO/.agentic/pm_flow/config.json"
  "$SCRIPT" "$REPO" --name "Empty Repo" > "$TMP/$variant-empty.out" 2>&1
  print -r -- "$variant: install exit=$?"
  grep -E '^project_key=' "$TMP/$variant-empty.out" || print -r -- "$variant: no project_key line"
  print -r -- "$variant: flow dir contents:"
  ls -a "$REPO/.agentic/pm_flow" | tr '\n' ' '
  print -r -- ""
  print -r -- "$variant: .project-key bytes:"
  od -c "$REPO/.agentic/pm_flow/.project-key" 2>/dev/null | head -n 2 || print -r -- "$variant: no .project-key"
done
