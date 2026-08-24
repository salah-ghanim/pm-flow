#!/bin/zsh -f
# Build a scratch copy of the developer tree, apply one mutation, run the suite.
# usage: zsh review_002_mutate.sh <m1|m2|m3|m4> <scratch dir>
set -uo pipefail

SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
MUT="$1"
DEST="$2"

rm -rf -- "$DEST"
mkdir -p -- "$DEST"
/bin/cp -R "$SRC/template" "$SRC/tests" "$SRC/src" "$SRC/install.sh" \
  "$SRC/pyproject.toml" "$DEST/"

RD="$DEST/template/.agentic/pm_flow/run_detach.zsh"

case "$MUT" in
  m1)
    # cmd_stop never writes the stop request.
    perl -0pi -e 's/\n  printf .%s\\n. "\$\(now_iso_utc\)" > "\$STOP_FILE"\n/\n  : "no stop file"\n/' "$RD"
    ;;
  m2)
    # the between-tick check after write_state is removed (lines 155-158).
    sed -i '' '155,158d' "$RD"
    ;;
  m3)
    # the loop leaves the honoured stop request behind (line 180).
    sed -i '' '180d' "$RD"
    ;;
  m4)
    # start no longer clears a stale stop file (line 221).
    sed -i '' '221s/ "\$STOP_FILE"//' "$RD"
    ;;
  m5)
    # the loop never honours the stop file: both between-tick checks removed.
    sed -i '' '155,158d;139,142d' "$RD"
    ;;
  *) print -r -- "unknown mutation: $MUT"; exit 2 ;;
esac

print -r -- "--- mutation $MUT diff ---"
diff "$SRC/template/.agentic/pm_flow/run_detach.zsh" "$RD"
print -r -- "--- suite under mutation $MUT ---"
zsh "$DEST/tests/run_detach_test.sh"
print -r -- "exit=$?"
