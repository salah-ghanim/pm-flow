#!/bin/zsh
# PM review, cycle 004: is acceptance state real, or vacuously "met"?
set -u
LIVE=/Users/salah/code/personal/pm-flow
python3 - /tmp/pm-review-004/run1.json "$LIVE/.agentic/pm_flow/pm-agent/sections" <<'PY'
import json, re, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
freeform = {"agents-md", "green-suite", "installer", "worktree-isolation"}

print("%-20s %-6s %-4s %s" % ("section", "state", "ids", "met/open"))
open_examples = []
for s in sorted(doc["sections"], key=lambda x: x["key"]):
    met = [a["id"] for a in s["acceptance"] if a["state"] == "met"]
    opn = [a["id"] for a in s["acceptance"] if a["state"] == "open"]
    tag = "FREEFORM" if s["key"] in freeform else ""
    print("%-20s %-6s %-4d met=%s open=%s %s"
          % (s["key"], s["status"], len(s["acceptance"]),
             ",".join(met) or "-", ",".join(opn) or "-", tag))
    for i in opn:
        open_examples.append((s["key"], i))

print()
print("free-form-heading sections with at least one met ID:")
for key in sorted(freeform):
    s = next(x for x in doc["sections"] if x["key"] == key)
    heads = [l for l in (root / key / "state.md").read_text().splitlines() if l.startswith("#")]
    print("  %-20s met=%d/%d  state.md headings=%s"
          % (key, sum(1 for a in s["acceptance"] if a["state"] == "met"),
             len(s["acceptance"]), heads))

print()
print("negative check: an 'open' ID must be absent outside Blockers/Next eligible task")
for key, ident in open_examples[:4]:
    text = (root / key / "state.md").read_text()
    secs, cur, buf = {}, None, []
    for line in text.splitlines():
        m = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
        if m:
            if cur is not None and cur not in secs:
                secs[cur] = "\n".join(buf).strip()
            cur, buf = m.group(1).strip().casefold(), []
        elif cur is not None:
            buf.append(line)
    if cur is not None and cur not in secs:
        secs[cur] = "\n".join(buf).strip()
    ev = "\n".join(b for h, b in secs.items() if h not in {"blockers", "next eligible task"})
    hit = re.search(rf"(?<!\w){ident}(?!\w)", ev)
    whole = re.search(rf"(?<!\w){ident}(?!\w)", text)
    print("  %-20s %s outside-excluded=%s anywhere-in-state.md=%s"
          % (key, ident, bool(hit), bool(whole)))
PY
