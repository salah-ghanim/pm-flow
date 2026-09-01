"""Cycle 005 scoping probe: compare the emitted export against the live section files."""
import json
import pathlib
import sys

export_path = pathlib.Path(sys.argv[1])
sections_dir = pathlib.Path(sys.argv[2])

doc = json.loads(export_path.read_text())
emitted = {s["key"]: s for s in doc["sections"]}
on_disk = sorted(p.name for p in sections_dir.iterdir() if p.is_dir())

print(f"export keys={len(emitted)} dirs={len(on_disk)} identical={sorted(emitted) == on_disk}")
missing = sorted(set(on_disk) - set(emitted))
extra = sorted(set(emitted) - set(on_disk))
if missing or extra:
    print(f"missing={missing} extra={extra}")

print(f"top-level keys={sorted(doc)}")
print(f"section keys={sorted(next(iter(emitted.values())))}")


def first_line(p):
    text = p.read_text()
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


def nonempty(p):
    return [ln.strip() for ln in p.read_text().splitlines() if ln.strip()]


# Spot check this section itself, not the one the last cycle checked.
key = "boundary-schema"
sec = emitted[key]
d = sections_dir / key
print(f"\n-- spot check {key} --")
print(f"status export={sec['status']!r} file={first_line(d / 'status.txt')!r}")
print(f"priority export={sec['priority']!r} file={first_line(d / 'priority.txt')!r}")
print(f"owned_paths match={sec['owned_paths'] == nonempty(d / 'owned_paths.txt')}")
print(f"owned_paths export={sec['owned_paths']}")
dep_file = d / "dependency_handoffs.txt"
print(f"dependencies export={sec['dependencies']} file={nonempty(dep_file) if dep_file.exists() else 'absent'}")
print(f"acceptance={sec['acceptance']}")

handoff_text = (d / "handoff.md").read_text()
for field, title in [
    ("outcome", "Outcome"),
    ("decisions", "Decisions"),
    ("interfaces", "Interfaces"),
    ("risks", "Risks"),
    ("unproven", "What is unproven"),
    ("next_action", "Next action"),
]:
    value = sec["handoff"].get(field, "")
    present = value.strip() and value.strip() in handoff_text
    print(f"handoff.{field}: chars={len(value)} verbatim_in_handoff_md={bool(present)}")

print(f"handoff extra keys={sorted(set(sec['handoff']) - {'outcome','decisions','interfaces','risks','unproven','next_action'})}")

# How many sections emit an empty acceptance list (the cycle-004 risk note).
empty_acc = sorted(k for k, s in emitted.items() if not s["acceptance"])
print(f"\nsections with acceptance=[]: {len(empty_acc)} {empty_acc}")
states = {}
for s in emitted.values():
    for a in s["acceptance"]:
        states[a["state"]] = states.get(a["state"], 0) + 1
print(f"acceptance state histogram={states}")
