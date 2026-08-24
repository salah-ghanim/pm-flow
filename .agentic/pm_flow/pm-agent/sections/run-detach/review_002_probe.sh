#!/bin/zsh -f
# Instrument the stop group so the acceptance observations are printed, and time
# the whole suite against the rejection condition on suite length.
set -uo pipefail

SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
DEST=/tmp/rd-probe

rm -rf -- "$DEST"
mkdir -p -- "$DEST"
/bin/cp -R "$SRC/template" "$SRC/tests" "$SRC/src" "$SRC/install.sh" \
  "$SRC/pyproject.toml" "$DEST/"

T="$DEST/tests/run_detach_test.sh"

perl -0pi -e 's/(\[\[ -n "\$action_before_stop" \]\] \|\| fail "next did not name the stop section action"\n)/$1print -r -- "PROBE next-before-stop:"; print -r -- "\$next_before_stop"; print -r -- "PROBE action_before_stop=\$action_before_stop"\n/' "$T"

perl -0pi -e 's/(assert_contains "\$stop_last_line" "stopped by request after tick 1" "stopped log final line"\n)/$1print -r -- "PROBE stop_last_line=\$stop_last_line"; print -r -- "PROBE stopped log:"; \/usr\/bin\/tail -n 6 "\$stop_log_path"; print -r -- "PROBE ticks=\$(state_value "\$STATE_FILE" ticks)"\n/' "$T"

perl -0pi -e 's/(  fail "the stopped dispatch did not advance the section action"\n)/$1print -r -- "PROBE next-before-restart:"; print -r -- "\$next_before_restart"; print -r -- "PROBE action_before_restart=\$action_before_restart"\n/' "$T"

perl -0pi -e 's/(fixture_status="\$\(git -C "\$FIXTURE_REPO" status --porcelain\)"\nif \[\[ -n "\$fixture_status" \]\]; then\n)/fixture_status="\$(git -C "\$FIXTURE_REPO" status --porcelain)"\nprint -r -- "PROBE porcelain-after-restart:[\$fixture_status]"\nprint -r -- "PROBE restart log:"; \/usr\/bin\/tail -n 6 "\$restart_log_path"\nif [[ -n "\$fixture_status" ]]; then\n/' "$T"

print -r -- "--- probe patch ---"
diff "$SRC/tests/run_detach_test.sh" "$T"
print -r -- "--- timed instrumented suite ---"
start=$(date +%s)
zsh "$T"
code=$?
end=$(date +%s)
print -r -- "exit=$code elapsed_seconds=$(( end - start ))"
