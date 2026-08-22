#!/bin/zsh -f
# access_hook.sh - record what a role reached for, before it reaches it.
#
# Installed as a claude PreToolUse hook. It observes and never refuses: the
# question it exists to answer is "what does a role actually read?", and a hook
# that blocked would change the answer while measuring it. It exits zero on
# every path, including its own failure, because a monitoring hook that can
# break a dispatch is worse than no monitoring.
#
# The read boundary is the reason this exists. On codex the `scoped` access tier
# bounds writes and not reads; on claude the `write` tier grants bare Bash,
# which is unrestricted read by construction. Neither is a secret - both are in
# the README - but neither was ever measured. This measures it.
#
# Reads a hook payload on stdin and appends one JSON object per line to
# $PM_FLOW_ACCESS_LOG.

[[ -n "${PM_FLOW_ACCESS_LOG:-}" ]] || exit 0

# Read the payload before python does. `python3 - <<'PY'` feeds the *script* on
# stdin, so the interpreter consumes it and `sys.stdin.read()` inside returns
# nothing: the first version of this hook logged one empty record per tool call
# and looked like it was working. The payload is passed as an argument instead.
PAYLOAD="$(/bin/cat)"

python3 - "$PM_FLOW_ACCESS_LOG" "${PM_FLOW_ACCESS_ROLE:-}" "${PM_FLOW_ACCESS_LABEL:-}" \
    "${PM_FLOW_REPO_ROOT:-}" "${PM_FLOW_ACCESS_WORK_ROOT:-}" "$PAYLOAD" <<'PY' 2>/dev/null
import json
import os
import re
import sys
import time
from pathlib import Path

log_path, role, label, repo_root, work_root = sys.argv[1:6]
raw_payload = sys.argv[6] if len(sys.argv) > 6 else "{}"

try:
    payload = json.loads(raw_payload or "{}")
except ValueError:
    payload = {}

tool = payload.get("tool_name") or ""
tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    tool_input = {}

# Roots a path can be "inside". Anything else is what we are here to notice.
roots = [Path(p).resolve() for p in (work_root, repo_root) if p]


# Not everything outside the repository is equally interesting. A role invoking
# /bin/zsh is not reading your files; a role reading somewhere under your home
# directory is. Keeping them in one bucket buries the signal under the noise,
# and the whole point of this log is to answer one question honestly.
SYSTEM_PREFIXES = ("/bin", "/sbin", "/usr", "/opt", "/System", "/Library", "/etc",
                   "/dev", "/proc", "/nix", "/opt/homebrew")
TEMP_PREFIXES = ("/tmp", "/var/tmp", "/private/tmp", "/private/var", "/var/folders")


def classify(raw):
    """Absolute path, plus where it sits relative to the roots we expected."""
    if not raw:
        return None
    try:
        resolved = Path(raw).expanduser()
        if not resolved.is_absolute():
            base = Path(work_root or repo_root or os.getcwd())
            resolved = base / resolved
        resolved = Path(os.path.normpath(str(resolved)))
    except (OSError, ValueError):
        return None
    text = str(resolved)
    for root in roots:
        try:
            resolved.relative_to(root)
            return {"path": text, "outside": False, "kind": "repo"}
        except ValueError:
            continue
    for prefix in TEMP_PREFIXES:
        if text == prefix or text.startswith(prefix + "/"):
            return {"path": text, "outside": True, "kind": "temp"}
    for prefix in SYSTEM_PREFIXES:
        if text == prefix or text.startswith(prefix + "/"):
            return {"path": text, "outside": True, "kind": "system"}
    return {"path": text, "outside": True, "kind": "other"}


targets = []
for key in ("file_path", "path", "notebook_path"):
    hit = classify(tool_input.get(key))
    if hit:
        targets.append(hit)

command = tool_input.get("command") if tool in ("Bash", "BashOutput") else None
if isinstance(command, str) and command:
    # Not a shell parser, and it does not pretend to be. It lifts anything that
    # looks like a path so a human reading the log can see where a command was
    # pointed; the command itself is recorded verbatim next to it, so nothing
    # depends on this being exhaustive.
    for token in re.findall(r"(?:^|\s)(~?/[^\s;|&'\"()]+|\.{1,2}/[^\s;|&'\"()]+)", command):
        hit = classify(token)
        if hit and hit not in targets:
            targets.append(hit)

record = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "role": role,
    "label": label,
    "tool": tool,
    "targets": targets,
    "outside": any(t["outside"] for t in targets),
    # The one that matters: a path that is neither ours, nor a system binary,
    # nor scratch.
    "reaches_user_files": any(t.get("kind") == "other" for t in targets),
}
if isinstance(command, str) and command:
    record["command"] = command[:600]
for key in ("pattern", "glob", "url"):
    value = tool_input.get(key)
    if isinstance(value, str) and value:
        record[key] = value[:300]

path = Path(log_path)
try:
    path.parent.mkdir(parents=True, exist_ok=True)
    # One open in append mode per record. Lines this short are written
    # atomically by the kernel, which is what makes a shared log safe when
    # several dispatches are running at once.
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")
except OSError:
    pass
PY

exit 0
