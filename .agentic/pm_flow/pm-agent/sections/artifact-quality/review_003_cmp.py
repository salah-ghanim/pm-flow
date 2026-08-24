import json
import sys

record_path, stdout_path = sys.argv[1:3]
with open(record_path, encoding="utf-8") as handle:
    record = json.load(handle)
with open(stdout_path, encoding="utf-8") as handle:
    lines = [line.rstrip("\n") for line in handle if line.strip()]

expected = []
for line in lines:
    parts = line.split(" | ")
    findings = []
    if parts[1] != "findings: none":
        for value in parts[1:]:
            code, message = value.split(": ", 1)
            findings.append({"code": code, "message": message})
    expected.append({"file": parts[0], "findings": findings})

actual = [
    {"file": a["file"], "findings": a["findings"]} for a in record["artifacts"]
]

print("record keys:", sorted(record))
print("project:", record["project"], "generated_at:", record["generated_at"])
print("stdout lines:", len(expected), "record entries:", len(actual))
print("order equal:", [a["file"] for a in actual] == [e["file"] for e in expected])
print("findings equal:", [a["findings"] for a in actual] == [e["findings"] for e in expected])
print("entry keys uniform:", sorted({tuple(sorted(a)) for a in record["artifacts"]}))
if actual != expected:
    for a, e in zip(actual, expected):
        if a != e:
            print("FIRST MISMATCH")
            print("  record:", a)
            print("  stdout:", e)
            break
    raise SystemExit("MISMATCH")
print("first 3 record entries with full fields:")
for a in record["artifacts"][:3]:
    print(" ", json.dumps(a))
print("MATCH: latest.json equals stdout in order and findings")
