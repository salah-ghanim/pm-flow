#!/usr/bin/env zsh
# Scoping probe for T4: can the live pm-agent project actually be exported?
# Every section is fed to export.py's existing brief and handoff checkers, and
# the state.md completed-evidence heading is inspected, because A1 requires
# `pm-flow export --json` to exit 0 on this very project.
set -u

ROOT=/Users/salah/code/personal/pm-flow
ENGINE=$ROOT/template/.agentic/pm_flow
SECTIONS=$ROOT/.agentic/pm_flow/pm-agent/sections

print "== per-section artifact presence and checker verdict =="
typeset -i n_brief_ok=0 n_brief_bad=0 n_handoff_ok=0 n_handoff_bad=0 n_state=0
for d in $SECTIONS/*(/); do
  key=${d:t}
  bverdict=MISSING; hverdict=MISSING; sverdict=MISSING
  if [[ -f $d/brief.md ]]; then
    if berr=$(python3 $ENGINE/export.py check --kind brief $d/brief.md 2>&1); then
      bverdict=ACCEPT; (( n_brief_ok++ ))
    else
      bverdict="REJECT[${berr}]"; (( n_brief_bad++ ))
    fi
  fi
  if [[ -f $d/handoff.md ]]; then
    if herr=$(python3 $ENGINE/export.py check --kind handoff $d/handoff.md 2>&1); then
      hverdict=ACCEPT; (( n_handoff_ok++ ))
    else
      hverdict="REJECT[${herr}]"; (( n_handoff_bad++ ))
    fi
  fi
  if [[ -f $d/state.md ]]; then sverdict=PRESENT; (( n_state++ )); fi
  printf '%-22s brief=%s handoff=%s state=%s\n' $key $bverdict $hverdict $sverdict
done
print "totals: brief ok=$n_brief_ok bad=$n_brief_bad | handoff ok=$n_handoff_ok bad=$n_handoff_bad | state.md=$n_state"

print ""
print "== state.md headings that could carry completed evidence =="
grep -h '^## ' $SECTIONS/*/state.md | sort | uniq -c | sort -rn | head -30

print ""
print "== per-section text files present across all sections =="
for f in name.txt status.txt priority.txt summary.txt owned_paths.txt dependency_handoffs.txt run_path.txt updated_at.txt; do
  printf '%-26s %d/%d\n' $f $(ls $SECTIONS/*/$f 2>/dev/null | wc -l | tr -d ' ') $(ls -d $SECTIONS/*(/) | wc -l | tr -d ' ')
done

print ""
print "== acceptance IDs parsed from a known section brief (otel-semconv) =="
python3 -c "
import sys, json
sys.path.insert(0, '$ENGINE')
import export
text = open('$SECTIONS/otel-semconv/brief.md').read()
parsed = export.parse_brief(text)
print('priority:', parsed['priority'])
print('shape:', parsed['shape'])
print('acceptance_ids:', json.dumps(parsed['acceptance_ids'][:3], indent=1))
print('n_ids:', len(parsed['acceptance_ids']))
h = export.parse_handoff(open('$SECTIONS/otel-semconv/handoff.md').read())
print('handoff keys:', sorted(k for k in h))
"

print ""
print "== owned_paths.txt / dependency_handoffs.txt raw shape (otel-semconv) =="
print "--- owned_paths.txt"; cat $SECTIONS/otel-semconv/owned_paths.txt
print "--- dependency_handoffs.txt"; cat $SECTIONS/otel-semconv/dependency_handoffs.txt
print "--- status/priority"; cat $SECTIONS/otel-semconv/status.txt $SECTIONS/otel-semconv/priority.txt
