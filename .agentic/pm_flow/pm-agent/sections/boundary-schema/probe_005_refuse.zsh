#!/bin/zsh
# Cycle 005: scenario 4 end to end on a copy of the live project, via the same engine
# the installed verb resolves. Nothing here touches the real flow directory.
emulate -L zsh
setopt no_unset

REPO=/Users/salah/code/personal/pm-flow
ENGINE=$REPO/template/.agentic/pm_flow
OUT=$REPO/.agentic/pm_flow/pm-agent/sections/boundary-schema/probe_005
WORK=$(mktemp -d /tmp/bs005.XXXXXX)

cp -R $REPO/.agentic/pm_flow $WORK/flow
export PM_FLOW_FLOW_DIR=$WORK/flow

print "== baseline: the copy exports clean =="
zsh $ENGINE/pm_flow.sh export --json > $WORK/clean.json 2> $WORK/clean.err
print "exit=$?"
head -c 300 $WORK/clean.err
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('sections=%d project=%s' % (len(d['sections']), d['project']))" $WORK/clean.json

print "\n== corrupt one live section's handoff in the copy =="
grep -v '## What is unproven' $WORK/flow/pm-agent/sections/otel-semconv/handoff.md > $WORK/tmp.md
mv $WORK/tmp.md $WORK/flow/pm-agent/sections/otel-semconv/handoff.md
zsh $ENGINE/pm_flow.sh export --json > $WORK/bad.json 2> $WORK/bad.err
print "exit=$?"
print "stdout bytes=$(wc -c < $WORK/bad.json)"
cat $WORK/bad.err

print "\n== the checker rejects the same file on its own =="
python3 $ENGINE/export.py check --kind handoff $WORK/flow/pm-agent/sections/otel-semconv/handoff.md
print "checker exit=$?"

cp $WORK/bad.err $OUT/copy_bad.err
rm -rf $WORK
