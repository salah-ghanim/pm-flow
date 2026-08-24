#!/bin/zsh -f
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality

print "=== changed paths in the worktree"
git -C "$WT" status --porcelain

print ""
print "=== 'show' subcommand present?"
grep -n "show" "$WT/src/pm_flow/quality.py"
print "(end)"

print ""
print "=== any 'pm-flow quality' arm or quality caller outside the owned module?"
grep -rn "pm_flow.quality\|pm-flow quality" "$WT/src" "$WT/template" "$WT/pm_flow.sh" 2>/dev/null
print "(end)"

print ""
print "=== rubric / paths.py / cli.py / driver touched?"
git -C "$WT" diff --stat -- src/pm_flow/paths.py src/pm_flow/cli.py pm_flow.sh \
  template/.agentic/pm_flow/prompt_quality.py template/.agentic/pm_flow/artifact_quality.md \
  template/.agentic/pm_flow/driver.zsh
print "(end)"

print ""
print "=== rank subparser and entry point"
sed -n '575,590p' "$WT/src/pm_flow/quality.py"

print ""
print "=== cross-repo --out probe: destination inside a DIFFERENT tracked repo"
P=/tmp/pm-flow-aq-crossrepo
rm -rf -- "$P"; mkdir -p "$P/fixture/.agentic/pm_flow/fx/sections/a" "$P/other"
printf 'fx\n' > "$P/fixture/.agentic/pm_flow/.project-key"
for f in brief workplan state handoff; do
  printf '# a %s\n\n## Objective\n- x\n' "$f" > "$P/fixture/.agentic/pm_flow/fx/sections/a/$f.md"
done
mkdir -p "$P/fixture/.agentic/pm_flow/fx/project_state"
printf '# plan\n\n## Objective\n- x\n' > "$P/fixture/.agentic/pm_flow/fx/project_state/plan.md"
git -C "$P/other" init -q
PM_FLOW_REPO_ROOT="$P/fixture" PYTHONPATH="$WT/src" \
  python3 -m pm_flow.quality rank --project fx --out "$P/other/quality" \
  > "$P/cross.out" 2> "$P/cross.err"
print "CROSS_EXIT=$?"
print "--- stderr"; cat "$P/cross.err"
print "--- did it write into the other repo?"
ls -1 "$P/other" 2>/dev/null
find "$P/other" -name 'latest.*' -print
print "(end)"
print "--- git check-ignore return code from the fixture repo_root for that path"
git -C "$P/fixture" check-ignore -q "$P/other/quality"
print "rc=$?"
