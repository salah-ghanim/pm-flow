#!/bin/zsh
# Cycle 005 scoping probe: does the section's COMPLETE claim hold on merged main?
emulate -L zsh
setopt no_unset

REPO=/Users/salah/code/personal/pm-flow
OUT=$REPO/.agentic/pm_flow/pm-agent/sections/boundary-schema/probe_005
rm -rf $OUT
mkdir -p $OUT

print "== head =="
git -C $REPO log --oneline -1
print "== dirty tracked files outside .agentic =="
git -C $REPO status --porcelain | grep -v '\.agentic/' || print "(none)"

print "\n== A1: export verb from the repo, as installed =="
git -C $REPO status --porcelain > $OUT/status_before.txt
pm-flow export --json > $OUT/export1.json 2> $OUT/export1.err
print "exit1=$?"
git -C $REPO status --porcelain > $OUT/status_after.txt
if cmp -s $OUT/status_before.txt $OUT/status_after.txt; then
  print "git-status-identical=YES"
else
  print "git-status-identical=NO"
  diff $OUT/status_before.txt $OUT/status_after.txt
fi
head -c 400 $OUT/export1.err

pm-flow export --json > $OUT/export2.json 2> $OUT/export2.err
print "exit2=$?"
if cmp -s $OUT/export1.json $OUT/export2.json; then print "stable=YES"; else print "stable=NO"; fi

python3 -m json.tool $OUT/export1.json > /dev/null
print "json-tool-exit=$?"

print "\n== A1: section coverage and one spot check =="
python3 $REPO/.agentic/pm_flow/pm-agent/sections/boundary-schema/probe_005_check.py \
  $OUT/export1.json $REPO/.agentic/pm_flow/pm-agent/sections

print "\n== A4: acp binding, quick reconfirmation =="
grep -n '"acp"' $REPO/template/.agentic/pm_flow/schemas/config.schema.json
grep -rn 'acp' $REPO/template/.agentic/pm_flow/topology.py | head -5

print "\n== A5: suites on the current checkout =="
for suite in tests/boundary_schema_test.sh tests/pm_flow_test.sh tests/topology_compare_test.sh tests/agent_bindings_test.sh template/.agentic/pm_flow/tests/verdict_parser.zsh; do
  name=${suite:t}
  zsh $REPO/$suite > $OUT/$name.log 2> $OUT/$name.err
  print "$suite exit=$?"
  tail -3 $OUT/$name.log
  print "---"
done
