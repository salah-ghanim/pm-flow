#!/bin/zsh -f
set -uo pipefail
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
MAIN=/Users/salah/code/personal/pm-flow
TMP=/var/folders/9x/9xzxgmhn75q66kr2x3n691hw0000gn/T//aq-review.7X98GD

print -r -- "=== artifact-quality/brief.md BEFORE ==="
grep 'sections/artifact-quality/brief.md' "$TMP/live.before.out"
print -r -- ""
print -r -- "=== artifact-quality/brief.md AFTER ==="
grep 'sections/artifact-quality/brief.md' "$TMP/live.after.out"
print -r -- ""
print -r -- "=== expanded-brief contract selection, live briefs ==="
for name in ${PM_FLOW_X:-}; do :; done
PYTHONPATH="$WT/src" python3 - "$MAIN" <<'PY'
import sys, pathlib
sys.path.insert(0, "/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality/src")
from pm_flow.quality import required_headings, has_heading, EXPANDED_BRIEF_HEADINGS
root = pathlib.Path(sys.argv[1]) / ".agentic/pm_flow/pm-agent/sections"
for brief in sorted(root.glob("*/brief.md")):
    text = brief.read_text(errors="replace")
    contract = "expanded" if required_headings("brief.md", text) is EXPANDED_BRIEF_HEADINGS else "legacy"
    missing = [h for h in required_headings("brief.md", text) if not has_heading(text, h)]
    print(f"{brief.parent.name:22} {contract:8} missing={missing}")
PY
