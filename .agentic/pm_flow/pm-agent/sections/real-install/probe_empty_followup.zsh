#!/bin/zsh -f
set -uo pipefail

WORKTREE=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-follow.XXXXXX")"
REPO="$TMP/repo"
mkdir -p "$REPO/.agentic/pm_flow"
git -C "$REPO" init --quiet
printf '{"version": 1}\n' > "$REPO/.agentic/pm_flow/config.json"

print -r -- "=== first install (new install.sh) into an existing empty flow dir ==="
"$WORKTREE/install.sh" "$REPO" --name "Empty Repo" > "$TMP/first.out" 2>&1
print -r -- "exit=$?"
grep -E '^(project_key|installed_pm_flow)=' "$TMP/first.out" || true
print -r -- "flow root now holds:"
ls -a "$REPO/.agentic/pm_flow" | tr '\n' ' '
print -r -- ""
print -r -- "projects.md entries:"
grep -E '^- `' "$REPO/.agentic/pm_flow/projects.md" || true

print -r -- ""
print -r -- "=== second install into the same repository ==="
"$WORKTREE/install.sh" "$REPO" --name "Empty Repo" > "$TMP/second.out" 2>&1
print -r -- "exit=$?"
tail -n 5 "$TMP/second.out"

print -r -- ""
print -r -- "=== flow .gitignore shipped by the template ==="
cat "$WORKTREE/template/.agentic/pm_flow/.gitignore"
