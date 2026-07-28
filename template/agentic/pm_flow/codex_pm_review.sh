#!/bin/zsh -f
# codex_pm_review.sh - Run a PM review via Codex CLI instead of Claude.
#
# Use this when the Claude API is rate-limited or unavailable. The script reads
# the prepared pending directory, inlines all referenced workspace files into a
# self-contained prompt, invokes `codex exec`, and writes a pm_flow-compatible
# response.json.
#
# Usage:
#   codex_pm_review.sh <pending-dir> [--model <model>]
#
# Arguments:
#   <pending-dir>   Path to a pending review directory produced by pm_flow.sh
#                   prepare-step or prepare-complete.
#   --model <name>  Codex model to use. Omit to use the Codex CLI default.
#
# After this script completes, run the normal record step:
#   pm_flow.sh record-step <pending-dir>
#   pm_flow.sh record-complete <pending-dir>
#
# Prerequisites:
#   - codex CLI must be in PATH (https://github.com/openai/codex)
#   - python3 must be in PATH

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
PROJECT_ROOT="$(cd -P -- "$SCRIPT_DIR/../.." && pwd -P)"

usage() {
  cat <<'EOF'
Usage:
  codex_pm_review.sh <pending-dir> [--model <model>]

Arguments:
  <pending-dir>   Pending review dir produced by pm_flow.sh prepare-step or prepare-complete.
  --model <name>  Codex model. Omit to use the Codex CLI default.

Examples:
  # Run a step review via Codex:
  codex_pm_review.sh agentic/pm_flow/<project>/runs/<run>/pending/<step-dir>

  # Use a specific model:
  codex_pm_review.sh agentic/pm_flow/<project>/runs/<run>/pending/<step-dir> --model o3
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -ge 1 ]] || { usage; exit 1; }
case "${1:-}" in -h|--help|help) usage; exit 0 ;; esac

PENDING_DIR="$(cd -P -- "$1" && pwd -P)"
shift

case "$PENDING_DIR" in
  "$SCRIPT_DIR"/*/runs/*/pending/*)
    pending_rel="${PENDING_DIR#$SCRIPT_DIR/}"
    PROJECT_KEY="${pending_rel%%/*}"
    ;;
  *)
    fail "pending directory is outside the installed pm-flow project runs: $PENDING_DIR"
    ;;
esac

MODEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="${2:-}"; [[ -n "$MODEL" ]] || fail "--model requires a value"; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

command -v codex  >/dev/null 2>&1 || fail "codex not found in PATH; install it from https://github.com/openai/codex"
command -v python3 >/dev/null 2>&1 || fail "python3 not found in PATH"

SYSTEM_PROMPT_FILE="$PENDING_DIR/system_prompt.txt"
# Current pending reviews carry the structured multi-line prompt.md. Pending
# reviews prepared by an older pm_flow.sh only have the flattened one-liner.
PROMPT_FILE="$PENDING_DIR/prompt.md"
[[ -f "$PROMPT_FILE" ]] || PROMPT_FILE="$PENDING_DIR/prompt_one_line.txt"
ENGINEER_UPDATE="$PENDING_DIR/engineer_update.md"
CONTEXT_MANIFEST="$PENDING_DIR/context_files.json"
RESPONSE_FILE="$PENDING_DIR/response.json"

[[ -f "$SYSTEM_PROMPT_FILE" ]] || fail "system_prompt.txt not found in $PENDING_DIR"
[[ -f "$PROMPT_FILE" ]]        || fail "prompt.md not found in $PENDING_DIR"
[[ -f "$ENGINEER_UPDATE" ]]    || fail "engineer_update.md not found in $PENDING_DIR"

# Build the self-contained prompt and run codex via Python to avoid shell
# argument length limits and quoting issues with multi-line strings.
LAST_MSG_FILE="$(mktemp /tmp/codex_pm_response.XXXXXX)"
trap 'rm -f "$LAST_MSG_FILE"' EXIT

printf 'Running Codex PM review (model=%s)...\n' "${MODEL:-codex-cli-default}" >&2
"$SCRIPT_DIR/pm_flow.sh" --project "$PROJECT_KEY" claim-execution "$PENDING_DIR" >&2

python3 - "$SYSTEM_PROMPT_FILE" "$PROMPT_FILE" "$ENGINEER_UPDATE" "$MODEL" "$LAST_MSG_FILE" "$CONTEXT_MANIFEST" "$PROJECT_ROOT" << 'PY'
import json
import subprocess
import sys
from pathlib import Path

system_prompt_file, prompt_file, engineer_update, model, out_file, context_manifest, project_root_arg = sys.argv[1:]

system_prompt = Path(system_prompt_file).read_text().strip()
base_prompt   = Path(prompt_file).read_text().strip()
eng_update    = Path(engineer_update).read_text().strip()
project_root  = Path(project_root_arg).resolve()

# New pending reviews carry an explicit, repo-relative context allowlist. The
# fallback for old pending directories always includes engineer_update.md and
# discovers any unambiguous absolute paths from the prompt.
manifest_path = Path(context_manifest)
if manifest_path.is_file():
    payload = json.loads(manifest_path.read_text())
    if payload.get("version") != 1 or not isinstance(payload.get("files"), list):
        raise SystemExit(f"invalid context manifest: {manifest_path}")
    referenced_paths = []
    for relative_path in payload["files"]:
        if not isinstance(relative_path, str) or not relative_path:
            raise SystemExit(f"invalid context path in manifest: {relative_path!r}")
        candidate = (project_root / relative_path).resolve()
        try:
            candidate.relative_to(project_root)
        except ValueError:
            raise SystemExit(f"context path escapes project root: {relative_path}")
        if not candidate.is_file():
            raise SystemExit(f"context file not found: {candidate}")
        referenced_paths.append(candidate)
else:
    import re
    referenced_paths = [Path(engineer_update).resolve()]
    for match in re.findall(r'(/.*?\.(?:md|txt|json))(?=\s+-\s+|\s+Respond\b|$)', base_prompt):
        candidate = Path(match).resolve()
        try:
            candidate.relative_to(project_root)
        except ValueError:
            continue
        if candidate.is_file() and candidate not in referenced_paths:
            referenced_paths.append(candidate)

# Build inline section for each referenced file
inline_sections = []
for path in referenced_paths:
    content = path.read_text().strip()
    relative_path = path.relative_to(project_root)
    inline_sections.append(f"=== FILE: {relative_path} ===\n{content}\n=== END FILE ===")

inline_block = "\n\n".join(inline_sections)

full_prompt = (
    f"{base_prompt}"
    + ("\n\n--- Referenced workspace files (inlined) ---\n\n" + inline_block if inline_block else "")
)

# Codex -c flag sets config fields: instructions maps to the system prompt
cmd = [
    "codex", "exec",
    "--sandbox", "read-only",
    "--ephemeral",
    "--cd", str(project_root),
    "-c", f"instructions={system_prompt}",
    "-o", out_file,
]
if model:
    cmd += ["-m", model]
cmd.append(full_prompt)
result = subprocess.run(cmd, cwd=project_root)
sys.exit(result.returncode)
PY

RESPONSE_TEXT="$(/bin/cat "$LAST_MSG_FILE")"
[[ -n "$RESPONSE_TEXT" ]] || fail "codex returned an empty response"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

python3 - "$RESPONSE_FILE" "$RESPONSE_TEXT" "$TIMESTAMP" << 'PY'
import json, sys
from pathlib import Path

out_path, result_text, ts = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "type":         "result",
    "subtype":      "success",
    "is_error":     False,
    "result":       result_text,
    # Codex fallback reviews are stateless. Leaving the session id empty and
    # marking it non-resumable prevents the next Claude review from trying to
    # resume a fake or stale session that never saw this exchange.
    "session_id":   "",
    "session_resumable": False,
    "pm_backend":   "codex",
    "stop_reason":  "end_turn",
    "total_cost_usd": 0,
    "usage":        {},
}
Path(out_path).write_text(json.dumps(payload, indent=2))
print(f"response.json written: {out_path}")
PY
