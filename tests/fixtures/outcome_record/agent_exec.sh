#!/bin/zsh -f
set -euo pipefail

output=""
prompt_file=""
while (( $# > 0 )); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --prompt-file) prompt_file="$2"; shift 2 ;;
    --heartbeat|--label|--seat|--work-root|--extra-dir|--read-dir) shift 2 ;;
    *) shift ;;
  esac
done

# The real manager replaces the scaffold workplan during scope. The fixture
# retires only that marker so the canned assignment is checked by the same
# validator as a real response.
if [[ "$prompt_file" == */scope_prompt.md ]]; then
  workplan="${prompt_file:h:h:h}/workplan.md"
  if [[ -f "$workplan" ]]; then
    grep -v 'pm-flow-workplan-template' "$workplan" > "$workplan.tmp"
    mv "$workplan.tmp" "$workplan"
  fi
fi

python3 - "$output" "${PM_FLOW_STUB:-}" <<'PY'
import json
import sys
from pathlib import Path

path, response = sys.argv[1:]
Path(path).parent.mkdir(parents=True, exist_ok=True)
Path(path).write_text(json.dumps({
    "is_error": False,
    "result": response,
    "failure_reason": "none",
    "total_cost_usd": 0.5,
}))
PY
