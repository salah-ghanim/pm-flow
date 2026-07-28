#!/bin/zsh -f
# agent_exec.sh - Run one pm-flow role as a fresh, supervised CLI invocation.
#
# Roles are named, not vendors. config.json binds each role to a cli, a model,
# and a difficulty (reasoning effort), so prompts and handoff files never name
# claude, codex, or copilot. Every call is a separate process, so each role
# starts with a fresh context by construction.
#
# Usage:
#   agent_exec.sh <role> --prompt-file <file> --output <response.json>
#                 [--heartbeat <file>] [--label <text>] [--dry-run]
#
# Exit status:
#   0  the role produced a response
#   3  supervision gave up (see the reason in the response envelope)

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
PROJECT_ROOT="$(cd -P -- "$SCRIPT_DIR/../.." && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  agent_exec.sh <role> --prompt-file <file> --output <response.json>
                [--heartbeat <file>] [--label <text>] [--dry-run]

Roles are defined in agentic/pm_flow/config.json. Each call is a fresh process.
EOF
}

ROLE="${1:-}"
[[ -n "$ROLE" ]] || { usage; exit 1; }
case "$ROLE" in -h|--help|help) usage; exit 0 ;; esac
shift

PROMPT_FILE=""
OUTPUT_FILE=""
HEARTBEAT_FILE=""
LABEL="$ROLE"
DRY_RUN="0"
SEAT="1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seat)        SEAT="${2:-}"; [[ "$SEAT" == <-> ]] || fail "--seat requires a positive integer"; shift 2 ;;
    --prompt-file) PROMPT_FILE="${2:-}"; [[ -n "$PROMPT_FILE" ]] || fail "--prompt-file requires a value"; shift 2 ;;
    --output)      OUTPUT_FILE="${2:-}"; [[ -n "$OUTPUT_FILE" ]] || fail "--output requires a value"; shift 2 ;;
    --heartbeat)   HEARTBEAT_FILE="${2:-}"; [[ -n "$HEARTBEAT_FILE" ]] || fail "--heartbeat requires a value"; shift 2 ;;
    --label)       LABEL="${2:-}"; [[ -n "$LABEL" ]] || fail "--label requires a value"; shift 2 ;;
    --dry-run)     DRY_RUN="1"; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$PROMPT_FILE" ]] || fail "--prompt-file is required"
[[ -f "$PROMPT_FILE" ]] || fail "prompt file not found: $PROMPT_FILE"
[[ -n "$OUTPUT_FILE" ]] || fail "--output is required"
[[ -f "$CONFIG_FILE" ]] || fail "missing agent config: $CONFIG_FILE"
command -v python3 >/dev/null 2>&1 || fail "python3 not found in PATH"

# Roles are dispatched directly rather than through net_exec.sh, so honour the
# same repo-local environment hook here.
export PROJECT_ROOT
export PM_FLOW_ROOT="$SCRIPT_DIR"
export PYTHONUTF8=1
if [[ -d "$PROJECT_ROOT/.venv" && -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
  export VIRTUAL_ENV="$PROJECT_ROOT/.venv"
  export PATH="$PROJECT_ROOT/.venv/bin:$PATH"
fi
if [[ -f "$SCRIPT_DIR/local_env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/local_env.sh"
fi

# Resolve the role binding once, up front, so a misconfigured role fails before
# any model is called.
role_binding="$(python3 - "$CONFIG_FILE" "$ROLE" "$SEAT" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
role = sys.argv[2]
seat = int(sys.argv[3])
if config.get("version") != 1:
    raise SystemExit(f"unsupported config version: {config.get('version')!r}")
roles = config.get("roles")
if not isinstance(roles, dict):
    raise SystemExit("config.json is missing a roles object")
if role not in roles:
    raise SystemExit(f"unknown role {role!r}; configured roles: {', '.join(sorted(roles))}")
binding = roles[role]

# A role may be a single binding or a panel of independent seats. A panel exists
# so different model families answer the same question without seeing each
# other, so each seat is dispatched as its own process.
if isinstance(binding, list):
    if not binding:
        raise SystemExit(f"role {role!r} is an empty panel")
    if seat > len(binding):
        raise SystemExit(f"role {role!r} has {len(binding)} seat(s); seat {seat} was requested")
    binding = binding[seat - 1]
elif seat != 1:
    raise SystemExit(f"role {role!r} is a single binding and has no seat {seat}")
if not isinstance(binding, dict):
    raise SystemExit(f"role {role!r} has an invalid binding")

cli = binding.get("cli", "")
if cli not in {"claude", "codex", "copilot"}:
    raise SystemExit(f"role {role!r} has an unsupported cli: {cli!r}")
difficulty = binding.get("difficulty", "medium")
if difficulty not in {"low", "medium", "high", "xhigh", "max"}:
    raise SystemExit(f"role {role!r} has an invalid difficulty: {difficulty!r}")

supervision = config.get("supervision", {})

def positive_int(section, key, default):
    value = section.get(key, default)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise SystemExit(f"supervision.{key} must be a positive integer, got {value!r}")
    return value

print(cli)
print(binding.get("model", ""))
print(difficulty)
# Only the two building roles may write. Reviewing and planning roles stay
# read-only so a review can never quietly edit the repository.
print("write" if role in {"developer", "10x_developer"} else "read")
print(positive_int(supervision, "max_attempts", 4))
print(positive_int(supervision, "retry_backoff_seconds", 30))
print(positive_int(supervision, "usage_limit_pause_seconds", 1800))
print(config.get("domain", "generic"))
print(positive_int(supervision, "heartbeat_stall_seconds", 900))
PY
)" || fail "could not resolve role '$ROLE' from $CONFIG_FILE"

AGENT_CLI="$(printf '%s\n' "$role_binding" | sed -n '1p')"
AGENT_MODEL="$(printf '%s\n' "$role_binding" | sed -n '2p')"
AGENT_DIFFICULTY="$(printf '%s\n' "$role_binding" | sed -n '3p')"
AGENT_ACCESS="$(printf '%s\n' "$role_binding" | sed -n '4p')"
MAX_ATTEMPTS="$(printf '%s\n' "$role_binding" | sed -n '5p')"
RETRY_BACKOFF="$(printf '%s\n' "$role_binding" | sed -n '6p')"
USAGE_PAUSE="$(printf '%s\n' "$role_binding" | sed -n '7p')"
AGENT_DOMAIN="$(printf '%s\n' "$role_binding" | sed -n '8p')"
STALL_SECONDS="$(printf '%s\n' "$role_binding" | sed -n '9p')"

file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0\n'
}

# Run one attempt in the background and watch it for silence. A role that was
# asked to report progress and then stopped reporting is treated as hung: it is
# killed and retried rather than left to block the run forever. Roles with no
# heartbeat are not policed this way, because a slow but healthy review writes
# nothing until it is finished.
STALLED="0"

# Start the CLI as its own process-group leader so a stalled attempt can be
# terminated whole. Agent CLIs spawn helper processes, and killing only the
# direct child leaves those orphaned and still consuming quota.
PGROUP_SHIM='import os, sys; os.setpgrp(); os.execvp(sys.argv[1], sys.argv[1:])'

terminate_group() {
  local group="$1"
  kill -TERM -- "-$group" 2>/dev/null || kill -TERM "$group" 2>/dev/null || true
  sleep 2
  kill -KILL -- "-$group" 2>/dev/null || kill -KILL "$group" 2>/dev/null || true
}

run_attempt() {
  STALLED="0"
  local child last_activity heartbeat_seen output_seen now_epoch
  if [[ "$AGENT_CLI" == "codex" ]]; then
    ( cd "$PROJECT_ROOT" && exec python3 -c "$PGROUP_SHIM" "${AGENT_ARGV[@]}" ) > "$ATTEMPT_LOG" 2>&1 &
  else
    ( cd "$PROJECT_ROOT" && exec python3 -c "$PGROUP_SHIM" "${AGENT_ARGV[@]}" ) > "$RAW_OUTPUT" 2> "$ATTEMPT_LOG" &
  fi
  child=$!

  if [[ -z "$HEARTBEAT_FILE" ]]; then
    wait "$child"
    return $?
  fi

  # Poll every second. A few cheap syscalls per second is nothing next to a
  # model call that runs for minutes, and a coarser interval would make a fast
  # agent wait just to be observed finishing.
  while kill -0 "$child" 2>/dev/null; do
    sleep 1
    kill -0 "$child" 2>/dev/null || break
    now_epoch="$(date +%s)"
    heartbeat_seen="$(file_mtime "$HEARTBEAT_FILE")"
    output_seen="$(file_mtime "$RAW_OUTPUT")"
    last_activity=$(( heartbeat_seen > output_seen ? heartbeat_seen : output_seen ))
    if (( now_epoch - last_activity >= STALL_SECONDS )); then
      printf '%s stalled with no progress for %ss; terminating\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STALL_SECONDS" >> "$HEARTBEAT_FILE"
      terminate_group "$child"
      STALLED="1"
      break
    fi
  done
  wait "$child" 2>/dev/null || return $?
  return 0
}

# Difficulty is one vocabulary in config.json. Each CLI spells it differently,
# and codex only accepts three levels, so the top two collapse to high.
codex_effort() {
  case "$1" in
    xhigh|max) printf 'high\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

build_command() {
  case "$AGENT_CLI" in
    claude)
      AGENT_ARGV=(claude -p --output-format json --effort "$AGENT_DIFFICULTY" --add-dir "$PROJECT_ROOT")
      [[ -z "$AGENT_MODEL" ]] || AGENT_ARGV+=(--model "$AGENT_MODEL")
      if [[ "$AGENT_ACCESS" == "write" ]]; then
        AGENT_ARGV+=(--permission-mode acceptEdits)
      fi
      AGENT_ARGV+=(-- "$(/bin/cat "$PROMPT_FILE")")
      ;;
    codex)
      AGENT_ARGV=(codex exec --ephemeral --cd "$PROJECT_ROOT"
                  -c "model_reasoning_effort=$(codex_effort "$AGENT_DIFFICULTY")"
                  -o "$RAW_OUTPUT")
      [[ -z "$AGENT_MODEL" ]] || AGENT_ARGV+=(-m "$AGENT_MODEL")
      if [[ "$AGENT_ACCESS" == "write" ]]; then
        AGENT_ARGV+=(--sandbox workspace-write)
      else
        AGENT_ARGV+=(--sandbox read-only)
      fi
      AGENT_ARGV+=("$(/bin/cat "$PROMPT_FILE")")
      ;;
    copilot)
      # --no-custom-instructions keeps the repository's own agent instructions
      # out of a role that was given an explicit persona.
      AGENT_ARGV=(copilot -p "$(/bin/cat "$PROMPT_FILE")"
                  --effort "$AGENT_DIFFICULTY" --add-dir "$PROJECT_ROOT"
                  --no-custom-instructions --no-ask-user --silent --stream off)
      [[ -z "$AGENT_MODEL" ]] || AGENT_ARGV+=(--model "$AGENT_MODEL")
      if [[ "$AGENT_ACCESS" == "write" ]]; then
        AGENT_ARGV+=(--allow-all-tools)
      fi
      ;;
  esac
}

# Classify a failed attempt from the CLI's own output. Usage limits mean wait;
# transient network faults mean retry; anything else is a real failure and
# retrying it just burns quota.
classify_failure() {
  local log_path="$1"
  python3 - "$log_path" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace").lower()
usage = [
    r"usage limit", r"rate limit", r"rate.?limited", r"quota", r"429",
    r"too many requests", r"insufficient.{0,20}credit", r"overloaded",
]
network = [
    r"econnreset", r"etimedout", r"enotfound", r"econnrefused", r"eai_again",
    r"network error", r"fetch failed", r"socket hang up", r"connection reset",
    r"\b50[234]\b", r"timed? ?out",
]
for pattern in usage:
    if re.search(pattern, text):
        print("usage_limit"); break
else:
    for pattern in network:
        if re.search(pattern, text):
            print("network"); break
    else:
        print("fatal")
PY
}

write_response() {
  local result_path="$1"
  local is_error="$2"
  local failure_reason="$3"
  local attempts="$4"
  python3 - "$OUTPUT_FILE" "$result_path" "$is_error" "$failure_reason" \
      "$ROLE" "$AGENT_CLI" "$AGENT_MODEL" "$AGENT_DIFFICULTY" "$attempts" <<'PY'
import json
import os
import sys
from pathlib import Path

out_path, result_path, is_error, reason, role, cli, model, difficulty, attempts = sys.argv[1:]
text = Path(result_path).read_text(errors="replace").strip() if Path(result_path).is_file() else ""
payload = {
    "type": "result",
    "is_error": is_error == "1",
    "result": text,
    "failure_reason": reason,
    "role": role,
    "pm_backend": cli,
    "model": model,
    "difficulty": difficulty,
    "attempts": int(attempts),
    # Every role runs as a fresh process, so nothing is resumable. Continuity
    # lives in the durable state and handoff files, not in a conversation.
    "session_id": "",
    "session_resumable": False,
}
path = Path(out_path)
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
temp.write_text(json.dumps(payload, indent=2) + "\n")
os.replace(temp, path)
PY
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-agent.XXXXXX")"
cleanup_work_dir() {
  [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}
trap cleanup_work_dir EXIT HUP INT TERM

RAW_OUTPUT="$WORK_DIR/raw.txt"
ATTEMPT_LOG="$WORK_DIR/attempt.log"
: > "$RAW_OUTPUT"

build_command

if [[ "$DRY_RUN" == "1" ]]; then
  printf 'role=%s\ncli=%s\nmodel=%s\ndifficulty=%s\naccess=%s\ndomain=%s\n' \
    "$ROLE" "$AGENT_CLI" "$AGENT_MODEL" "$AGENT_DIFFICULTY" "$AGENT_ACCESS" "$AGENT_DOMAIN"
  printf 'argv='
  printf '%q ' "${AGENT_ARGV[@]}"
  printf '\n'
  exit 0
fi

command -v "$AGENT_CLI" >/dev/null 2>&1 || \
  fail "role '$ROLE' is bound to '$AGENT_CLI', which is not in PATH"

if [[ -n "$HEARTBEAT_FILE" ]]; then
  mkdir -p "$(dirname "$HEARTBEAT_FILE")"
  printf '%s starting %s (%s/%s)\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LABEL" "$ROLE" "$AGENT_CLI" >> "$HEARTBEAT_FILE"
fi

attempt=1
final_reason="none"
while (( attempt <= MAX_ATTEMPTS )); do
  : > "$ATTEMPT_LOG"
  : > "$RAW_OUTPUT"
  build_command

  attempt_status=0
  run_attempt || attempt_status=$?

  if (( attempt_status == 0 )) && [[ "$STALLED" == "0" ]] && [[ -s "$RAW_OUTPUT" ]]; then
    final_reason="none"
    break
  fi

  if [[ "$STALLED" == "1" ]]; then
    reason="stall"
  else
    reason="$(classify_failure "$ATTEMPT_LOG")"
  fi
  final_reason="$reason"
  if [[ -n "$HEARTBEAT_FILE" ]]; then
    printf '%s attempt %d of %d failed (%s)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$MAX_ATTEMPTS" "$reason" >> "$HEARTBEAT_FILE"
  fi

  # Never wait after the final attempt; nothing will use the result.
  if (( attempt >= MAX_ATTEMPTS )); then
    break
  fi

  case "$reason" in
    usage_limit)
      printf 'pm-flow: %s hit a usage limit; pausing %ss before retrying\n' \
        "$AGENT_CLI" "$USAGE_PAUSE" >&2
      sleep "$USAGE_PAUSE"
      ;;
    network|stall)
      local_backoff=$(( RETRY_BACKOFF * attempt ))
      printf 'pm-flow: %s attempt ended in a %s; retrying in %ss\n' \
        "$AGENT_CLI" "$reason" "$local_backoff" >&2
      sleep "$local_backoff"
      ;;
    *)
      # A real error. Retrying spends quota to get the same answer.
      printf 'pm-flow: %s failed and the error is not transient\n' "$AGENT_CLI" >&2
      /usr/bin/tail -n 20 "$ATTEMPT_LOG" >&2 || true
      write_response "$ATTEMPT_LOG" "1" "fatal" "$attempt"
      exit 3
      ;;
  esac
  (( attempt += 1 ))
done

if [[ "$final_reason" != "none" ]]; then
  printf 'pm-flow: gave up on role %s after %d attempts (%s)\n' \
    "$ROLE" "$MAX_ATTEMPTS" "$final_reason" >&2
  write_response "$ATTEMPT_LOG" "1" "$final_reason" "$MAX_ATTEMPTS"
  exit 3
fi

# claude already emits the response envelope; the others return plain text.
if [[ "$AGENT_CLI" == "claude" ]]; then
  python3 - "$OUTPUT_FILE" "$RAW_OUTPUT" "$ROLE" "$AGENT_CLI" "$AGENT_MODEL" \
      "$AGENT_DIFFICULTY" "$attempt" <<'PY'
import json
import os
import sys
from pathlib import Path

out_path, raw_path, role, cli, model, difficulty, attempts = sys.argv[1:]
raw = Path(raw_path).read_text(errors="replace")
try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    payload = {"is_error": True, "result": raw.strip(), "failure_reason": "unparsable_response"}
payload.setdefault("failure_reason", "none")
payload.update({
    "role": role,
    "pm_backend": cli,
    "model": model,
    "difficulty": difficulty,
    "attempts": int(attempts),
    "session_resumable": False,
})
path = Path(out_path)
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
temp.write_text(json.dumps(payload, indent=2) + "\n")
os.replace(temp, path)
PY
else
  write_response "$RAW_OUTPUT" "0" "none" "$attempt"
fi

if [[ -n "$HEARTBEAT_FILE" ]]; then
  printf '%s finished %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LABEL" >> "$HEARTBEAT_FILE"
fi

printf 'role=%s\ncli=%s\nresponse=%s\nattempts=%d\n' "$ROLE" "$AGENT_CLI" "$OUTPUT_FILE" "$attempt"
