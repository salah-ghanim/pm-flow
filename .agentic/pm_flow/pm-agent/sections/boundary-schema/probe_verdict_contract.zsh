#!/bin/zsh -f
# PM review probe, cycle 002. A/B the verdict parser contract between main's
# inline-python pm_flow.sh and the worktree's export.py-backed one: stdout
# shape, stderr text, exit status.
set -uo pipefail

extract_and_run() {
  local label="$1" engine="$2"
  local SCRIPT_DIR="$engine"
  eval "$(python3 - "$engine/pm_flow.sh" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
out = []
for name in ("fail", "markdown_verdict_parse", "extract_markdown_decision",
             "extract_markdown_decision_line"):
    m = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}\n", text, re.S | re.M)
    if not m:
        raise SystemExit(f"cannot extract {name}")
    out.append(m.group(0))
sys.stdout.write("\n".join(out))
PY
)"
  local good='## Decision

GO_WITH_CHANGES rewire the validator first'
  local bad='## Decision

MAYBE not sure yet'

  print "=== $label ==="
  local out rc
  out="$(markdown_verdict_parse "$good" "GO,GO_WITH_CHANGES,NO_GO" 2>&1)"; rc=$?
  print "accept_exit=$rc"
  print "accept_stdout<<<$out>>>"
  out="$(markdown_verdict_parse "$bad" "GO,GO_WITH_CHANGES,NO_GO" 2>&1)"; rc=$?
  print "reject_exit=$rc"
  print "reject_stderr<<<$out>>>"
  out="$(extract_markdown_decision_line "$good" "GO,GO_WITH_CHANGES,NO_GO" 2>/dev/null)"; rc=$?
  print "decision_line_exit=$rc"
  print "decision_line<<<$out>>>"
  out="$(extract_markdown_decision_line "$bad" "GO,GO_WITH_CHANGES,NO_GO" 2>/dev/null)"; rc=$?
  print "bad_decision_line_exit=$rc"
  print "bad_decision_line<<<$out>>>"
}

MAIN=/Users/salah/code/personal/pm-flow/template/.agentic/pm_flow
WORK=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema/template/.agentic/pm_flow

( extract_and_run "main (HEAD)" "$MAIN" )
( extract_and_run "worktree (cycle 002)" "$WORK" )
