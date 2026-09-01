#!/bin/zsh
# PM review, cycle 004, A1 spot check: otel-semconv, export vs its own files.
set -u
LIVE=/Users/salah/code/personal/pm-flow
python3 - /tmp/pm-review-004/run1.json "$LIVE/.agentic/pm_flow/pm-agent/sections/otel-semconv" <<'PY'
import json, re, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
src = Path(sys.argv[2])
sec = next(s for s in doc["sections"] if s["key"] == "otel-semconv")

def first(name):
    return src.joinpath(name).read_text().splitlines()[0].strip()

def lines(name):
    return [l.strip() for l in src.joinpath(name).read_text().splitlines() if l.strip()]

def verdict(ok):
    return "MATCH" if ok else "DIFFER"

print("status   export=%r file=%r %s" % (sec["status"], first("status.txt"), verdict(sec["status"] == first("status.txt"))))
print("priority export=%r file-line1=%r %s" % (sec["priority"], first("priority.txt"), verdict(sec["priority"] == first("priority.txt"))))
print("priority.txt full file:")
for i, l in enumerate(src.joinpath("priority.txt").read_text().splitlines(), 1):
    print("   %d: %s" % (i, l))
print("owned_paths export=%r" % (sec["owned_paths"],))
print("owned_paths file  =%r %s" % (lines("owned_paths.txt"), verdict(sec["owned_paths"] == lines("owned_paths.txt"))))
dep = lines("dependency_handoffs.txt")
print("dependencies export=%r file=%r %s" % (sec["dependencies"], dep, verdict(sec["dependencies"] == dep)))
print("acceptance export=%r" % (sec["acceptance"],))
print("acceptance ids    =%r count=%d" % ([a["id"] for a in sec["acceptance"]], len(sec["acceptance"])))

# handoff: recompute the six sections straight from handoff.md, independently.
text = src.joinpath("handoff.md").read_text()
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

titles = {
    "outcome": "Outcome",
    "decisions": "Decisions",
    "interfaces": "Interfaces",
    "risks": "Risks",
    "unproven": "What is unproven",
    "next_action": "Next action",
}
print("--- handoff fields ---")
for field, title in titles.items():
    got = sec["handoff"][field]
    want = secs[title.casefold()]
    print("%-12s %s  (export %d chars, handoff.md '## %s' %d chars)"
          % (field, verdict(got == want), len(got), title, len(want)))
print("word_count=%d byte_count=%d" % (sec["handoff"]["word_count"], sec["handoff"]["byte_count"]))
print("handoff keys =", sorted(sec["handoff"]))
print("--- outcome, first 3 lines as emitted ---")
for l in sec["handoff"]["outcome"].splitlines()[:3]:
    print("   " + l)
print("--- outcome, first 3 lines of handoff.md '## Outcome' ---")
for l in secs["outcome"].splitlines()[:3]:
    print("   " + l)
PY
