#!/bin/zsh -f
# Confirm the developer's diagnosis: adding run_detach.zsh to install.sh's
# COPIED_ENGINE_FILES is sufficient to make packaged_layout_test.sh pass.
# Done in a scratch copy; the developer's worktree is not touched.
set -e
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
S=/tmp/pm-flow-fixcheck.$$
mkdir -p "$S"
/usr/bin/rsync -a --exclude '.git' "$W/" "$S/"
/usr/bin/sed -i '' 's|^  driver\.zsh$|  driver.zsh\n  run_detach.zsh|' "$S/install.sh"
print -r -- "--- COPIED_ENGINE_FILES after patch ---"
/usr/bin/sed -n '47,70p' "$S/install.sh"
print -r -- "--- packaged_layout_test.sh with the patch ---"
set +e
zsh "$S/tests/packaged_layout_test.sh"
print -r -- "PATCHED_PACKAGED_EXIT=$?"
rm -rf -- "$S"
