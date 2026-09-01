#!/bin/zsh -f
# PM review probe, cycle 002. A/B validate_section_brief, validate_handoff and
# handoff_budget_report between main and the worktree over every real brief and
# handoff in this flow, plus the suite fixtures. Any row where the two engines
# differ is a behaviour change the task forbids.
#
# NB: never name a loop variable `path` here - zsh ties it to PATH.
set -uo pipefail

run_engine() {
  local engine="$1"
  local SCRIPT_DIR="$engine"
  eval "$(python3 - "$engine/pm_flow.sh" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
out = []
for name in ("fail", "assert_matches", "validate_section_brief",
             "extract_section_priority", "validate_handoff",
             "handoff_budget_report"):
    m = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}\n", text, re.S | re.M)
    if not m:
        raise SystemExit(f"cannot extract {name}")
    out.append(m.group(0))
sys.stdout.write("\n".join(out))
PY
)"
  local kind artifact body label v p r
  while IFS=$'\t' read -r kind artifact; do
    body="$(/bin/cat "$artifact")"
    label="${artifact:h:t}/${artifact:t}"
    case "$kind" in
      brief)
        if ( validate_section_brief "$body" ) >/dev/null 2>&1; then v=ACCEPT; else v=REJECT; fi
        if ( extract_section_priority "$body" ) >/dev/null 2>&1; then p=ACCEPT; else p=REJECT; fi
        print -r -- "brief $label validate=$v priority=$p"
        ;;
      handoff)
        if ( validate_handoff "$body" ) >/dev/null 2>&1; then v=ACCEPT; else v=REJECT; fi
        r="$( ( handoff_budget_report "$body" ) 2>&1 )"
        print -r -- "handoff $label validate=$v report=${r//$'\n'/ | }"
        ;;
    esac
  done < "$LIST"
}

LIST="$(mktemp "${TMPDIR:-/tmp}/pm-review-002-list.XXXXXX")"
FLOWROOT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections
FIX=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema/tests/fixtures/boundary_schema
{
  for f in $FLOWROOT/*/brief.md; do printf 'brief\t%s\n' "$f"; done
  for f in $FIX/brief_*.md; do printf 'brief\t%s\n' "$f"; done
  for f in $FLOWROOT/*/handoff.md; do printf 'handoff\t%s\n' "$f"; done
  for f in $FIX/handoff_*.md; do printf 'handoff\t%s\n' "$f"; done
} > "$LIST"

MAIN=/Users/salah/code/personal/pm-flow/template/.agentic/pm_flow
WORK=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema/template/.agentic/pm_flow
( run_engine "$MAIN" ) > "$LIST.main" 2>&1
( run_engine "$WORK" ) > "$LIST.work" 2>&1
print -r -- "artifacts=$(wc -l < $LIST.work)"
print -r -- "--- diff main vs worktree (empty means identical behaviour) ---"
diff "$LIST.main" "$LIST.work"
print -r -- "diff_exit=$?"
print -r -- "--- worktree results ---"
/bin/cat "$LIST.work"
