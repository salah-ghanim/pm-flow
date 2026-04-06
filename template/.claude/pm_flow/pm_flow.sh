#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
RUNS_DIR="$SCRIPT_DIR/runs"
CONTRACT_FILE="$SCRIPT_DIR/task_contract.md"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PM_SYSTEM_PROMPT="You are the project manager for another software agent. Review proposed engineering steps and completion reports, critique reasoning, detect mission drift, suggest improvements, approve or reject the path forward, and recommend the next action. Do not write code. Focus on scope control, validation, sequencing, risks, and drift management. Be direct and concrete."

usage() {
  cat <<'EOF'
Usage:
  pm_flow.sh validate
  pm_flow.sh init <task-name>
  pm_flow.sh rotate-session <run-dir> [reason]
  pm_flow.sh prepare-step <run-dir> <stage-name>
  pm_flow.sh prepare-step <run-dir> <stage-name> --file <markdown-file>
  pm_flow.sh record-step <pending-dir>
  pm_flow.sh record-step <pending-dir> --response-file <markdown-file>
  pm_flow.sh prepare-complete <run-dir>
  pm_flow.sh prepare-complete <run-dir> --file <markdown-file>
  pm_flow.sh record-complete <pending-dir>
  pm_flow.sh record-complete <pending-dir> --response-file <markdown-file>
  pm_flow.sh print-command <pending-dir>

Important:
  This script never invokes `claude -p`.
  It writes a direct top-shell Claude command into command.txt.
  The first PM call uses plain `claude -p --output-format json`.
  Later calls add `--resume <session_id>` using the captured value from response.json.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 command not found"
}

extract_json_field() {
  local json_path="$1"
  local field_name="$2"
  python3 - "$json_path" "$field_name" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]
payload = json.loads(path.read_text())
value = payload.get(field, "")
if value is None:
    value = ""
print(value)
PY
}

now_compact_utc() {
  date -u +"%Y%m%dT%H%M%SZ"
}

now_iso_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

lower_uuid() {
  uuidgen | tr '[:upper:]' '[:lower:]'
}

slugify() {
  local input="${1:-task}"
  local slug
  slug="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$slug" ]]; then
    slug="task"
  fi
  printf '%s\n' "$slug"
}

read_stdin_body() {
  if [[ -t 0 ]]; then
    fail "this command expects markdown input on stdin"
  fi
  /bin/cat
}

read_body_arg() {
  local mode="${1:-stdin}"
  local path="${2:-}"
  case "$mode" in
    stdin)
      read_stdin_body
      ;;
    file)
      [[ -n "$path" ]] || fail "body file path is required"
      [[ -f "$path" ]] || fail "body file not found: $path"
      /bin/cat "$path"
      ;;
    *)
      fail "unknown body mode: $mode"
      ;;
  esac
}

read_contract() {
  [[ -f "$CONTRACT_FILE" ]] || fail "missing task contract: $CONTRACT_FILE"
  /bin/cat "$CONTRACT_FILE"
}

persist_meta() {
  local meta_path="$1"
  {
    printf 'RUN_DIR=%q\n' "$RUN_DIR"
    printf 'TASK_NAME=%q\n' "$TASK_NAME"
    printf 'TASK_SLUG=%q\n' "$TASK_SLUG"
    printf 'SESSION_ID=%q\n' "$SESSION_ID"
    printf 'SESSION_STARTED=%q\n' "$SESSION_STARTED"
    printf 'CREATED_AT_UTC=%q\n' "$CREATED_AT_UTC"
  } > "$meta_path"
}

load_run() {
  local run_dir_input="${1:-}"
  [[ -n "$run_dir_input" ]] || fail "run directory is required"
  local abs_run_dir
  abs_run_dir="$(cd "$run_dir_input" && pwd)"
  [[ -f "$abs_run_dir/meta.env" ]] || fail "missing $abs_run_dir/meta.env"
  # shellcheck disable=SC1090
  source "$abs_run_dir/meta.env"
  RUN_DIR="$abs_run_dir"
}

load_pending() {
  local pending_dir_input="${1:-}"
  [[ -n "$pending_dir_input" ]] || fail "pending directory is required"
  local abs_pending_dir
  abs_pending_dir="$(cd "$pending_dir_input" && pwd)"
  [[ -f "$abs_pending_dir/pending.env" ]] || fail "missing $abs_pending_dir/pending.env"
  # shellcheck disable=SC1090
  source "$abs_pending_dir/pending.env"
  PENDING_DIR="$abs_pending_dir"
  load_run "$RUN_DIR"
}

append_exchange() {
  local kind="$1"
  local label="$2"
  local engineer_body="$3"
  local claude_response="$4"
  local transcript_path="$RUN_DIR/transcript.md"
  {
    printf '## %s: %s\n\n' "$kind" "$label"
    printf -- '- timestamp_utc: %s\n' "$(now_iso_utc)"
    printf -- '- session_id: %s\n' "$SESSION_ID"
    printf '\n### Codex Update\n\n%s\n\n' "$engineer_body"
    printf '### Claude Response\n\n%s\n\n' "$claude_response"
  } >> "$transcript_path"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s\n' "$haystack" | rg -F -q "$needle" || fail "Claude response missing required marker: $needle"
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  local label="$3"
  printf '%s\n' "$haystack" | rg -q "$pattern" || fail "Claude response missing valid $label"
}

validate_step_response() {
  local response="$1"
  assert_contains "$response" "Assessment"
  assert_contains "$response" "Drift review"
  assert_contains "$response" "Risks"
  assert_contains "$response" "Improvements"
  assert_contains "$response" "Decision"
  assert_contains "$response" "Next action"
  assert_matches "$response" '\b(GO|GO_WITH_CHANGES|NO_GO)\b' "step decision"
}

validate_completion_response() {
  local response="$1"
  assert_contains "$response" "Outcome assessment"
  assert_contains "$response" "Drift review"
  assert_contains "$response" "Expected vs observed"
  assert_contains "$response" "Feedback"
  assert_contains "$response" "Recommended next steps"
  assert_contains "$response" "Decision"
  assert_matches "$response" '\b(DONE|FOLLOW_UP|REWORK)\b' "completion decision"
}

serialize_prompt_for_claude() {
  local prompt="$1"
  printf '%s' "$prompt" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

session_mode_flag() {
  if [[ "${SESSION_STARTED:-0}" == "1" && -n "${SESSION_ID:-}" ]]; then
    printf '%s\n' "resume"
  else
    printf '%s\n' "start"
  fi
}

write_command_file() {
  local command_path="$1"
  local pending_dir="$2"
  local mode_flag="$3"
  local prompt_path="$pending_dir/prompt_one_line.txt"
  local system_prompt_path="$pending_dir/system_prompt.txt"
  local response_path="$pending_dir/response.json"
  local prompt_one_line system_prompt
  prompt_one_line="$(/bin/cat "$prompt_path")"
  system_prompt="$(/bin/cat "$system_prompt_path")"
  {
    printf 'claude -p --output-format json '
    printf -- '--add-dir %q ' "$PROJECT_ROOT"
    if [[ "$mode_flag" == "resume" && -n "${SESSION_ID:-}" ]]; then
      printf -- '--resume %q ' "$SESSION_ID"
    fi
    printf -- '--append-system-prompt %q -- %q > %q\n' "$system_prompt" "$prompt_one_line" "$response_path"
  } > "$command_path"
}

prepare_pending_dir() {
  local kind_slug="$1"
  local label="$2"
  local pending_dir
  pending_dir="$RUN_DIR/pending/$(now_compact_utc)-${kind_slug}-$(slugify "$label")"
  mkdir -p "$pending_dir"
  printf '%s\n' "$pending_dir"
}

record_pending_meta() {
  local pending_dir="$1"
  local kind="$2"
  local label="$3"
  local mode_flag="$4"
  {
    printf 'RUN_DIR=%q\n' "$RUN_DIR"
    printf 'PROJECT_ROOT=%q\n' "$PROJECT_ROOT"
    printf 'KIND=%q\n' "$kind"
    printf 'LABEL=%q\n' "$label"
    printf 'MODE_FLAG=%q\n' "$mode_flag"
  } > "$pending_dir/pending.env"
}

cmd_validate() {
  require_command claude
  require_command uuidgen
  require_command rg
  require_command python3
  printf 'claude_path=%s\n' "$(command -v claude)"
  claude --version
}

cmd_init() {
  local task_name="${1:-}"
  [[ -n "$task_name" ]] || fail "init requires a task name"

  local task_brief
  task_brief="$(read_stdin_body)"

  mkdir -p "$RUNS_DIR"

  local created_at task_slug run_dir
  created_at="$(now_compact_utc)"
  task_slug="$(slugify "$task_name")"
  run_dir="$RUNS_DIR/${created_at}-${task_slug}"
  mkdir -p "$run_dir/pending"

  RUN_DIR="$run_dir"
  TASK_NAME="$task_name"
  TASK_SLUG="$task_slug"
  SESSION_ID=""
  SESSION_STARTED="0"
  CREATED_AT_UTC="$(now_iso_utc)"

  printf '%s\n' "$task_brief" > "$RUN_DIR/task_brief.md"
  persist_meta "$RUN_DIR/meta.env"

  local contract_body
  contract_body="$(read_contract)"
  {
    printf '# Claude PM Flow Transcript\n\n'
    printf -- '- task_name: %s\n' "$TASK_NAME"
    printf -- '- task_slug: %s\n' "$TASK_SLUG"
    printf -- '- created_at_utc: %s\n' "$CREATED_AT_UTC"
    printf -- '- session_id: %s\n' "$SESSION_ID"
    printf -- '- rule: this run owns a fresh Claude session and does not reuse unrelated conversations\n'
    printf '\n## Task Brief\n\n%s\n\n' "$task_brief"
    printf '## Task Contract\n\n%s\n\n' "$contract_body"
  } > "$RUN_DIR/transcript.md"

  printf '%s\n' "$RUN_DIR"
}

cmd_rotate_session() {
  local run_dir_input="${1:-}"
  local reason="${2:-manual session rotation}"
  load_run "$run_dir_input"
  local old_session_id="$SESSION_ID"
  SESSION_ID=""
  SESSION_STARTED="0"
  persist_meta "$RUN_DIR/meta.env"
  {
    printf '## Session Rotation\n\n'
    printf -- '- timestamp_utc: %s\n' "$(now_iso_utc)"
    printf -- '- old_session_id: %s\n' "$old_session_id"
    printf -- '- new_session_id: pending_first_response\n'
    printf -- '- reason: %s\n\n' "$reason"
  } >> "$RUN_DIR/transcript.md"
  printf 'rotated_session_id=pending_first_response\n'
}

cmd_prepare_step() {
  local run_dir_input="${1:-}"
  local stage_name="${2:-}"
  [[ -n "$stage_name" ]] || fail "prepare-step requires a stage name"
  local body_mode="stdin"
  local body_path=""
  if [[ "${3:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${4:-}"
  elif [[ -n "${3:-}" ]]; then
    fail "unknown prepare-step argument: ${3:-}"
  fi
  load_run "$run_dir_input"

  local engineer_body prompt prompt_one_line mode_flag pending_dir
  engineer_body="$(read_body_arg "$body_mode" "$body_path")"
  mode_flag="$(session_mode_flag)"
  pending_dir="$(prepare_pending_dir "step" "$stage_name")"
  prompt="$(cat <<EOF
You are reviewing a proposed engineering step inside an ongoing task.

Task name: $TASK_NAME
Stage: $stage_name

Read these files from the workspace before answering:
- $RUN_DIR/task_brief.md
- $CONTRACT_FILE
- $pending_dir/engineer_update.md

Respond with these sections only:
1. Assessment
2. Drift review
3. Risks
4. Improvements
5. Decision
6. Next action

Decision must be one of: GO, GO_WITH_CHANGES, or NO_GO.
EOF
)"
  prompt_one_line="$(serialize_prompt_for_claude "$prompt")"

  printf '%s\n' "$engineer_body" > "$pending_dir/engineer_update.md"
  printf '%s\n' "$prompt" > "$pending_dir/prompt.md"
  printf '%s\n' "$prompt_one_line" > "$pending_dir/prompt_one_line.txt"
  printf '%s\n' "$PM_SYSTEM_PROMPT" > "$pending_dir/system_prompt.txt"
  : > "$pending_dir/response.json"
  record_pending_meta "$pending_dir" "step" "$stage_name" "$mode_flag"
  write_command_file \
    "$pending_dir/command.txt" \
    "$pending_dir" \
    "$mode_flag"

  printf 'pending_dir=%s\n' "$pending_dir"
  printf 'mode=%s\n' "$mode_flag"
  printf 'command_file=%s\n' "$pending_dir/command.txt"
  printf 'response_file=%s\n' "$pending_dir/response.json"
}

cmd_prepare_complete() {
  local run_dir_input="${1:-}"
  local body_mode="stdin"
  local body_path=""
  if [[ "${2:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown prepare-complete argument: ${2:-}"
  fi
  load_run "$run_dir_input"

  local engineer_body prompt prompt_one_line mode_flag pending_dir
  engineer_body="$(read_body_arg "$body_mode" "$body_path")"
  mode_flag="$(session_mode_flag)"
  pending_dir="$(prepare_pending_dir "complete" "final")"
  prompt="$(cat <<EOF
You are reviewing the completion report for an engineering task.

Task name: $TASK_NAME

Read these files from the workspace before answering:
- $RUN_DIR/task_brief.md
- $CONTRACT_FILE
- $pending_dir/engineer_update.md

Respond with these sections only:
1. Outcome assessment
2. Drift review
3. Expected vs observed
4. Feedback
5. Recommended next steps
6. Decision

Decision must be one of: DONE, FOLLOW_UP, or REWORK.
EOF
)"
  prompt_one_line="$(serialize_prompt_for_claude "$prompt")"

  printf '%s\n' "$engineer_body" > "$pending_dir/engineer_update.md"
  printf '%s\n' "$prompt" > "$pending_dir/prompt.md"
  printf '%s\n' "$prompt_one_line" > "$pending_dir/prompt_one_line.txt"
  printf '%s\n' "$PM_SYSTEM_PROMPT" > "$pending_dir/system_prompt.txt"
  : > "$pending_dir/response.json"
  record_pending_meta "$pending_dir" "complete" "final" "$mode_flag"
  write_command_file \
    "$pending_dir/command.txt" \
    "$pending_dir" \
    "$mode_flag"

  printf 'pending_dir=%s\n' "$pending_dir"
  printf 'mode=%s\n' "$mode_flag"
  printf 'command_file=%s\n' "$pending_dir/command.txt"
  printf 'response_file=%s\n' "$pending_dir/response.json"
}

cmd_record_step() {
  local pending_dir_input="${1:-}"
  local response_file_override=""
  if [[ "${2:-}" == "--response-file" ]]; then
    response_file_override="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown record-step argument: ${2:-}"
  fi
  load_pending "$pending_dir_input"

  local response_path="$PENDING_DIR/response.json"
  if [[ -n "$response_file_override" ]]; then
    response_path="$response_file_override"
  fi
  [[ -f "$response_path" ]] || fail "response file not found: $response_path"

  local engineer_body claude_response claude_session_id claude_is_error
  engineer_body="$(/bin/cat "$PENDING_DIR/engineer_update.md")"
  claude_is_error="$(extract_json_field "$response_path" "is_error")"
  claude_response="$(extract_json_field "$response_path" "result")"
  claude_session_id="$(extract_json_field "$response_path" "session_id")"
  [[ -n "$claude_response" ]] || fail "response file is empty: $response_path"
  if [[ "$claude_is_error" == "True" || "$claude_is_error" == "true" ]]; then
    fail "Claude CLI returned an error: $claude_response"
  fi
  validate_step_response "$claude_response"
  if [[ -n "$claude_session_id" ]]; then
    SESSION_ID="$claude_session_id"
  fi
  SESSION_STARTED="1"
  persist_meta "$RUN_DIR/meta.env"
  append_exchange "Step Review" "$LABEL" "$engineer_body" "$claude_response"
  printf 'recorded=step\n'
}

cmd_record_complete() {
  local pending_dir_input="${1:-}"
  local response_file_override=""
  if [[ "${2:-}" == "--response-file" ]]; then
    response_file_override="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown record-complete argument: ${2:-}"
  fi
  load_pending "$pending_dir_input"

  local response_path="$PENDING_DIR/response.json"
  if [[ -n "$response_file_override" ]]; then
    response_path="$response_file_override"
  fi
  [[ -f "$response_path" ]] || fail "response file not found: $response_path"

  local engineer_body claude_response claude_session_id claude_is_error
  engineer_body="$(/bin/cat "$PENDING_DIR/engineer_update.md")"
  claude_is_error="$(extract_json_field "$response_path" "is_error")"
  claude_response="$(extract_json_field "$response_path" "result")"
  claude_session_id="$(extract_json_field "$response_path" "session_id")"
  [[ -n "$claude_response" ]] || fail "response file is empty: $response_path"
  if [[ "$claude_is_error" == "True" || "$claude_is_error" == "true" ]]; then
    fail "Claude CLI returned an error: $claude_response"
  fi
  validate_completion_response "$claude_response"
  if [[ -n "$claude_session_id" ]]; then
    SESSION_ID="$claude_session_id"
  fi
  SESSION_STARTED="1"
  persist_meta "$RUN_DIR/meta.env"
  append_exchange "Completion Review" "$LABEL" "$engineer_body" "$claude_response"
  printf 'recorded=complete\n'
}

cmd_print_command() {
  local pending_dir_input="${1:-}"
  load_pending "$pending_dir_input"
  /bin/cat "$PENDING_DIR/command.txt"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    validate)
      shift || true
      cmd_validate "$@"
      ;;
    init)
      shift || true
      cmd_init "$@"
      ;;
    rotate-session)
      shift || true
      cmd_rotate_session "$@"
      ;;
    prepare-step)
      shift || true
      cmd_prepare_step "$@"
      ;;
    record-step)
      shift || true
      cmd_record_step "$@"
      ;;
    prepare-complete)
      shift || true
      cmd_prepare_complete "$@"
      ;;
    record-complete)
      shift || true
      cmd_record_complete "$@"
      ;;
    print-command)
      shift || true
      cmd_print_command "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      fail "unknown command: $cmd"
      ;;
  esac
}

main "$@"
