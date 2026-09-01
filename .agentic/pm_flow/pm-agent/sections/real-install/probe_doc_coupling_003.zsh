#!/bin/zsh -f
# Cycle 003 review probe: is the suite really executing the text published in
# docs/real-install.md, or a copy kept elsewhere? Mutate a copy of the worktree's
# document and show the suite fails. The worktree itself is never modified.
set -uo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-doc-coupling.XXXXXX")"
COPY="$TMP/checkout"
print -r -- "probe_root=$TMP"

/usr/bin/rsync -a --exclude '.venv' "$WT/" "$COPY/"

# MUTATION: change one string the runbook prints, inside the extracted fence.
/usr/bin/sed -i '' "s/^  print 'verify=ok'\$/  print 'verify=PROBE_MUTATION'/" \
  "$COPY/docs/real-install.md"
/usr/bin/grep -n "verify=PROBE_MUTATION" "$COPY/docs/real-install.md"

zsh "$COPY/tests/real_install_test.sh" > "$TMP/mutated.log" 2>&1
print -r -- "mutated_suite_exit=$?"
/usr/bin/tail -n 6 "$TMP/mutated.log"
print -r -- "probe_root=$TMP"
