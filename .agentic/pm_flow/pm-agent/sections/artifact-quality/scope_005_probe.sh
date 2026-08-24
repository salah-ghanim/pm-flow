#!/bin/zsh
# Read-only-ish scope probe for cycle 005: confirm A1-A6 hold on main.
set -uo pipefail
ROOT=/Users/salah/code/personal/pm-flow
TMP=$(mktemp -d)

zsh "$ROOT/tests/artifact_quality_test.sh" >"$TMP/aq.out" 2>"$TMP/aq.err"
print "ARTIFACT_QUALITY_EXIT=$?"

zsh "$ROOT/tests/pm_flow_test.sh" >"$TMP/pmf.out" 2>"$TMP/pmf.err"
print "PM_FLOW_TEST_EXIT=$?"
tail -3 "$TMP/pmf.out"

zsh "$ROOT/template/.agentic/pm_flow/tests/run.zsh" >"$TMP/tpl.out" 2>"$TMP/tpl.err"
print "TEMPLATE_RUN_EXIT=$?"
tail -3 "$TMP/tpl.out"

git -C "$ROOT" status --porcelain >"$TMP/status.before"

cd "$ROOT"
python -m pm_flow.quality rank --project pm-agent >"$TMP/rank.out" 2>"$TMP/rank.err"
print "RANK_EXIT=$?"
python -m pm_flow.quality show --project pm-agent >"$TMP/show.out" 2>"$TMP/show.err"
print "SHOW_EXIT=$?"

git -C "$ROOT" status --porcelain >"$TMP/status.after"
cmp -s "$TMP/status.before" "$TMP/status.after"
print "STATUS_CMP_EXIT=$?"
cmp -s "$TMP/show.out" "$TMP/rank.out"
print "SHOW_VS_RANK_CMP_EXIT=$?"
cmp -s "$TMP/show.out" "$ROOT/.agentic/pm_flow/pm-agent/quality/latest.md"
print "SHOW_VS_RECORD_CMP_EXIT=$?"

print "RANK_STDERR:"; cat "$TMP/rank.err"
print "COMPOSITE_HITS=$(grep -Ec 'composite|quality:[0-9]|score[=:][0-9]' "$TMP/rank.out")"
print "RANK_LINES=$(wc -l < "$TMP/rank.out")"
print "DIMENSION_COUNTS:"
for d in length echo shape boundaries stale; do
  print "  $d=$(grep -c "$d:" "$TMP/rank.out")"
done
print "QUALITY_DIR:"; ls "$ROOT/.agentic/pm_flow/pm-agent/quality/"
print "SECTION_SCORE_FILES:"; find "$ROOT/.agentic/pm_flow/pm-agent/sections" \( -name 'quality*' -o -name '*.score' \) -print
print "IGNORE_CHECK:"; git -C "$ROOT" check-ignore -v .agentic/pm_flow/pm-agent/quality/latest.json
print "PROBE_TMP=$TMP"
