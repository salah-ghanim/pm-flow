#!/bin/zsh -f
# The trap's status is a fixed `error`, so a successful on-demand command that
# did not close its own row would be recorded as a failure. The suite asserts
# only that no row is left open, never what status each row carries. Dump the
# whole runs table so the on-demand portfolio-review row can be read.
set -uo pipefail
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-statuses.XXXXXX")"
case "$SANDBOX" in
  */outcome-record-statuses.*) ;;
  *) print -r -- "unsafe sandbox: $SANDBOX" >&2; exit 1 ;;
esac
cp -R "$W/template" "$SANDBOX/template"
cp -R "$W/tests" "$SANDBOX/tests"
/bin/cat >> "$SANDBOX/tests/outcome_record_test.sh" <<'EOF'

ALL_RUNS_SQL="SELECT id || '|' || command || '|' || COALESCE(status,'NULL') || '|' || CASE WHEN ended_at IS NULL THEN 'open' ELSE 'closed' END FROM runs ORDER BY id;"
printf 'ALL RUNS:\n%s\n' "$(sqlite3 "$DB" "$ALL_RUNS_SQL")"
EOF
zsh "$SANDBOX/tests/outcome_record_test.sh" 2>&1 | /usr/bin/sed -n '/ALL RUNS:/,$p'
print -r -- "suite_exit=${pipestatus[1]}"
rm -rf -- "$SANDBOX"
