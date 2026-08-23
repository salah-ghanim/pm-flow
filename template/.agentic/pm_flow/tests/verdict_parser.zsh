#!/bin/zsh -f
set -uo pipefail
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# Pull just the parser functions out of pm_flow.sh without running main.
eval "$(python3 - "$SCRIPT_DIR/pm_flow.sh" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
out = []
for name in ("markdown_verdict_parse", "extract_markdown_decision",
             "extract_markdown_decision_line", "extract_assignment_sections",
             "validate_scoped_assignment"):
    m = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}\n", text, re.S | re.M)
    out.append(m.group(0))
sys.stdout.write("\n".join(out))
PY
)"

pass=0; failn=0
check() {
  local label="$1" expect="$2" allowed="$3" heading="$4" body="$5"
  local got
  got="$(markdown_verdict_parse "$body" "$allowed" "$heading" 2>/dev/null | sed -n 1p)" || got="<REJECT>"
  [[ -n "$got" ]] || got="<REJECT>"
  if [[ "$got" == "$expect" ]]; then
    printf 'PASS  %-46s -> %s\n' "$label" "$got"; (( pass += 1 ))
  else
    printf 'FAIL  %-46s -> %s (expected %s)\n' "$label" "$got" "$expect"; (( failn += 1 ))
  fi
}

D="GO,GO_WITH_CHANGES,NO_GO"
S="ASSIGN,COMPLETE,BLOCKED_EXTERNAL"

check "plain atx heading"            GO "$D" Decision $'## Decision\n\nGO\n'
check "numbered atx heading"         GO "$D" Decision $'# 5. Decision\n\nGO\n'
check "numbered paren heading"       NO_GO "$D" Decision $'##### 5) Decision\n\nNO_GO because x\n'
check "bold heading"                 GO "$D" Decision $'**Decision**\n\nGO the tests pass\n'
check "bold heading with colon"      NO_GO "$D" Decision $'**Decision:**\n\nNO_GO\n'
check "same-line dash verdict"       GO "$D" Decision $'## Decision - GO\n'
check "same-line colon verdict"      GO_WITH_CHANGES "$D" Decision $'## Decision: GO_WITH_CHANGES, fix the log\n'
check "same-line em-ish double dash"  GO "$D" Decision $'## Decision -- GO\n'
check "blockquoted value"            NO_GO "$D" Decision $'## Decision\n\n> NO_GO the check never ran\n'
check "bulleted value"               GO "$D" Decision $'## Decision\n\n- GO\n'
check "numbered value"               GO "$D" Decision $'## Decision\n\n1. GO\n'
check "bold value"                   NO_GO "$D" Decision $'## Decision\n\n**NO_GO**\n'
check "backticked value"             GO "$D" Decision $'## Decision\n\n`GO`\n'
check "bare heading line no hashes"  GO "$D" Decision $'Decision\n\nGO\n'
check "duplicate sections, last wins" NO_GO "$D" Decision $'## Decision\n\nGO\n\n## Notes\n\nx\n\n## Decision\n\nNO_GO\n'
check "prose mention then real one"  GO "$D" Decision $'## Decision\n\nThe decision below is final.\n\n## Decision\n\nGO\n'
check "trailing justification"       GO "$D" Decision $'## Decision\n\nGO -- the acceptance output is pasted\n'
check "scope ASSIGN"                 ASSIGN "$S" Decision $'## Decision\n\nASSIGN write the probe\n'
check "scope BLOCKED_EXTERNAL"       BLOCKED_EXTERNAL "$S" Decision $'## Decision\n\nBLOCKED_EXTERNAL no paper gateway credentials exist\n'
check "developer Status heading"     PARTIAL "DELIVERED,PARTIAL,BLOCKED" Status $'## Status\n\nPARTIAL two of three tests pass\n'
check "reject unknown token"         "<REJECT>" "$D" Decision $'## Decision\n\nMAYBE\n'
check "reject missing section"       "<REJECT>" "$D" Decision $'## Assessment\n\nAll good.\n'
check "reject empty section"         "<REJECT>" "$D" Decision $'## Decision\n\n## Next\n\nx\n'
check "GO not GO_WITH_CHANGES prefix" GO_WITH_CHANGES "$D" Decision $'## Decision\n\nGO_WITH_CHANGES rename the fixture\n'

printf '\n--- decision line extraction ---\n'
line="$(extract_markdown_decision_line $'## Decision\n\nBLOCKED_EXTERNAL the IB paper gateway has no credentials on this host\n' "$S")"
printf 'line=%s\n' "$line"

printf '\n--- assignment extraction (F20) ---\n'
extract_assignment_sections $'## Where the section stands\n\nEditorial the developer must never see.\n\n## Assignment\n\nWrite the probe script.\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q tests/x.py` exits 0\n\n## Rejection conditions\n\n- The probe is mocked.\n\n## Decision\n\nASSIGN\n'


# The assignment-to-workplan binding. One task ID per assignment, spelled any
# way a manager would spell it; a scaffold workplan is refused with the reason.
WP="$(mktemp -t pm-flow-wp.XXXXXX)"
printf '# x workplan\n\n## Task T1 — Build it\n\n- Status: pending\n\n## Task T2 — Ship it\n' > "$WP"
SCAFFOLD="$(mktemp -t pm-flow-wp.XXXXXX)"
printf '# x workplan\n<!-- pm-flow-workplan-template: replace -->\n\n## Task T1 — Decompose\n' > "$SCAFFOLD"
bind() {
  local label="$1" expect="$2" line="$3" workplan="$4" got reason
  if reason="$(validate_scoped_assignment "## Workplan task

$line

## Assignment
x" "$workplan" 2>&1)"; then got=ACCEPT; else got=REJECT; fi
  if [[ "$got" == "$expect" ]]; then
    printf 'PASS  %-46s -> %s\n' "$label" "$got"; (( pass += 1 ))
  else
    printf 'FAIL  %-46s -> %s (expected %s) %s\n' "$label" "$got" "$expect" "$reason"; (( failn += 1 ))
  fi
}
bind "bare id"                       ACCEPT 'T1' "$WP"
bind "backticked id"                 ACCEPT '`T1`' "$WP"
bind "bulleted id"                   ACCEPT '- T1' "$WP"
bind "id with title"                 ACCEPT 'T1 — Build it' "$WP"
bind "Task prefix"                   ACCEPT 'Task T1' "$WP"
bind "bold id"                       ACCEPT '**T1**' "$WP"
bind "id with colon"                 ACCEPT 'T1: Build it' "$WP"
bind "undefined id"                  REJECT 'T9' "$WP"
bind "two ids"                       REJECT 'T1 and T2' "$WP"
bind "empty"                         REJECT '' "$WP"
bind "scaffold workplan"             REJECT 'T1' "$SCAFFOLD"
rm -f "$WP" "$SCAFFOLD"

printf '\ntotals: pass=%d fail=%d\n' "$pass" "$failn"
[[ "$failn" == 0 ]]
