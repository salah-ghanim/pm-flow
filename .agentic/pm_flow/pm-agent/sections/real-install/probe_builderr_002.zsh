#!/bin/zsh
set -uo pipefail
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
COPY="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-build.XXXXXX")"
rsync -a --exclude '.git' --exclude '.venv' --exclude '.agentic' "$WT/" "$COPY/"
print "copy=$COPY"
ls "$COPY" | head -n 30
BV="$COPY/bv"
python3 -m venv "$BV" > /dev/null 2>&1
"$BV/bin/python" -m pip install --no-index --find-links "$COPY/tests/packaging-build-wheelhouse" \
  --quiet --require-hashes -r "$COPY/tests/packaging-build-wheelhouse/build-requirements.txt" > /dev/null 2>&1
print "build deps installed: $?"
"$BV/bin/python" -m pip wheel --no-index --no-build-isolation --no-deps \
  --wheel-dir "$COPY/dist" "$COPY" 2>&1 | tail -n 30
print "cleanup $COPY"
