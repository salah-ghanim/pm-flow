#!/bin/zsh
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
#   --model <name>  Codex model to use. Defaults to o4-mini.
#
# After this script completes, run the normal record step:
#   pm_flow.sh record-step <pending-dir>
#   pm_flow.sh record-complete <pending-dir>
#
# Prerequisites:
#   - codex CLI must be in PATH (https://github.com/openai/codex)
#   - python3 must be in PATH

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  codex_pm_review.sh <pending-dir> [--model <model>]

Arguments:
  <pending-dir>   Pending review dir produced by pm_flow.sh prepare-step or prepare-complete.
  --model <name>  Codex model. Default: o4-mini.

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

PENDING_DIR="$(cd -- "$1" && pwd)"
shift

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
PROMPT_FILE="$PENDING_DIR/prompt_one_line.txt"
ENGINEER_UPDATE="$PENDING_DIR/engineer_update.md"
RESPONSE_FILE="$PENDING_DIR/response.json"

[[ -f "$SYSTEM_PROMPT_FILE" ]] || fail "system_prompt.txt not found in $PENDING_DIR"
[[ -f "$PROMPT_FILE" ]]        || fail "prompt_one_line.txt not found in $PENDING_DIR"
[[ -f "$ENGINEER_UPDATE" ]]    || fail "engineer_update.md not found in $PENDING_DIR"

# Build the self-contained prompt and run codex via Python to avoid shell
# argument length limits and quoting issues with multi-line strings.
LAST_MSG_FILE="$(mktemp /tmp/codex_pm_response.XXXXXX)"
trap 'rm -f "$LAST_MSG_FILE"' EXIT

printf 'Running Codex PM review (model=%s)...\n' "$MODEL" >&2

python3 - "$SYSTEM_PROMPT_FILE" "$PROMPT_FILE" "$ENGINEER_UPDATE" "$MODEL" "$LAST_MSG_FILE" << 'PY'
import subprocess
import sys
from pathlib import Path

system_prompt_file, prompt_file, engineer_update, model, out_file = sys.argv[1:]

system_prompt = Path(system_prompt_file).read_text().strip()
base_prompt   = Path(prompt_file).read_text().strip()
eng_update    = Path(engineer_update).read_text().strip()

# Extract absolute workspace file paths referenced in the prompt
import re
referenced_paths = re.findall(r'(/[^\s]+\.(?:md|txt|json))', base_prompt)

# Build inline section for each referenced file
inline_sections = []
for fpath in referenced_paths:
    p = Path(fpath)
    if p.is_file():
        content = p.read_text().strip()
    else:
        content = "(file not found)"
    inline_sections.append(f"=== FILE: {fpath} ===\n{content}\n=== END FILE ===")

inline_block = "\n\n".join(inline_sections)

full_prompt = (
    f"{base_prompt}"
    + ("\n\n--- Referenced workspace files (inlined) ---\n\n" + inline_block if inline_block else "")
)

# Codex -c flag sets config fields: instructions maps to the system prompt
cmd = [
    "codex", "exec",
    "--dangerously-bypass-approvals-and-sandbox",
    "-c", f"instructions={system_prompt}",
    "-o", out_file,
]
if model:
    cmd += ["-m", model]
cmd.append(full_prompt)
result = subprocess.run(cmd)
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
    "session_id":   f"codex-fallback-{ts}",
    "stop_reason":  "end_turn",
    "total_cost_usd": 0,
    "usage":        {},
}
Path(out_path).write_text(json.dumps(payload, indent=2))
print(f"response.json written: {out_path}")
PY
