#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
PROJECT_INPUT=""
PROJECT_KEY=""
RUNS_DIR=""
STATE_FILE=""
PID_FILE=""
STOP_FILE=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

slugify() {
  local input="${1:-project}"
  local slug
  slug="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | \
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  [[ -n "$slug" ]] || slug="project"
  printf '%s\n' "$slug"
}

now_compact_utc() {
  date -u +"%Y%m%dT%H%M%SZ"
}

now_iso_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

state_value() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  sed -n "s/^${key}=//p" "$STATE_FILE" | /usr/bin/head -n 1
}

pid_is_live() {
  local pid="$1"
  [[ "$pid" == <-> ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

write_state() {
  local pid="$1"
  local started_at="$2"
  local log="$3"
  local section="$4"
  local max_ticks="$5"
  local engine="$6"
  local ticks="$7"
  local tmp="$STATE_FILE.tmp.$$"
  {
    printf 'pid=%s\n' "$pid"
    printf 'started_at=%s\n' "$started_at"
    printf 'log=%s\n' "$log"
    printf 'section=%s\n' "$section"
    printf 'max_ticks=%s\n' "$max_ticks"
    printf 'engine=%s\n' "$engine"
    printf 'ticks=%s\n' "$ticks"
  } > "$tmp"
  mv -f -- "$tmp" "$STATE_FILE"
}

resolve_project() {
  local flow_dir="${PM_FLOW_FLOW_DIR:-$SCRIPT_DIR}"
  if [[ -n "$PROJECT_INPUT" ]]; then
    PROJECT_KEY="$(slugify "$PROJECT_INPUT")"
  elif [[ -n "${PM_FLOW_PROJECT:-}" ]]; then
    PROJECT_KEY="$(slugify "$PM_FLOW_PROJECT")"
  elif [[ -f "$flow_dir/.project-key" ]]; then
    PROJECT_KEY="$(/usr/bin/head -n 1 "$flow_dir/.project-key" | tr -d '\r')"
    [[ -n "$PROJECT_KEY" && "$PROJECT_KEY" == "$(slugify "$PROJECT_KEY")" ]] || \
      fail "invalid persisted project key: $flow_dir/.project-key"
    [[ -d "$flow_dir/$PROJECT_KEY" ]] || \
      fail "persisted project workspace does not exist: $flow_dir/$PROJECT_KEY"
  fi

  if [[ -n "${PM_FLOW_RUNS_DIR:-}" ]]; then
    RUNS_DIR="$PM_FLOW_RUNS_DIR"
  elif [[ -n "${PM_FLOW_PROJECT_DIR:-}" ]]; then
    RUNS_DIR="$PM_FLOW_PROJECT_DIR/runs"
  else
    [[ -n "$PROJECT_KEY" ]] || \
      fail "could not resolve project under $flow_dir; use --project <name>"
    RUNS_DIR="$flow_dir/$PROJECT_KEY/runs"
  fi
  STATE_FILE="$RUNS_DIR/run-detach.state"
  PID_FILE="$RUNS_DIR/run-detach.pid"
  STOP_FILE="$RUNS_DIR/run-detach.stop"
}

resolve_engine() {
  local engine=""
  if [[ -n "${PM_FLOW_RUN_DETACH_CMD:-}" ]]; then
    engine="$PM_FLOW_RUN_DETACH_CMD"
  elif [[ -n "${PM_FLOW_ENGINE_ROOT:-}" && -n "${PM_FLOW_FLOW_DIR:-}" && \
          -n "${PM_FLOW_REPO_ROOT:-}" && -x "$SCRIPT_DIR/pm_flow.sh" ]]; then
    engine="$SCRIPT_DIR/pm_flow.sh"
  else
    engine="$(command -v pm-flow 2>/dev/null || true)"
  fi
  [[ -n "$engine" ]] || fail "could not resolve the pm-flow tick command"
  [[ "$engine" != *$'\n'* ]] || fail "tick command must be one executable"
  command -v "$engine" >/dev/null 2>&1 || fail "tick command not found: $engine"
  printf '%s\n' "$engine"
}

loop_main() {
  RUNS_DIR="$1"
  PROJECT_INPUT="$2"
  local section="$3"
  local max_ticks="$4"
  STATE_FILE="$RUNS_DIR/run-detach.state"
  PID_FILE="$RUNS_DIR/run-detach.pid"
  STOP_FILE="$RUNS_DIR/run-detach.stop"

  local ready_attempt=0
  while (( ready_attempt < 1000 )); do
    if [[ "$(state_value pid)" == "$$" && -f "$PID_FILE" && \
          "$(/bin/cat "$PID_FILE" 2>/dev/null)" == "$$" ]]; then
      break
    fi
    (( ready_attempt += 1 ))
    sleep 0.01
  done
  (( ready_attempt < 1000 )) || return 1

  local started_at log engine ticks=0 tick_status=0 tick_output="" reason="tick budget reached"
  started_at="$(state_value started_at)"
  log="$(state_value log)"
  engine="$(state_value engine)"
  printf '[%s] run-detach started pid=%s\n' "$(now_iso_utc)" "$$"

  local -a tick_command
  while (( ticks < max_ticks )); do
    tick_command=("$engine")
    [[ -z "$PROJECT_INPUT" ]] || tick_command+=(--project "$PROJECT_INPUT")
    [[ -z "$section" ]] || tick_command+=(--section "$section")
    tick_command+=(run --max-ticks 1)

    tick_status=0
    tick_output="$("${tick_command[@]}" 2>&1)" || tick_status=$?
    printf '%s\n' "$tick_output"
    (( ticks += 1 ))
    write_state "$$" "$started_at" "$log" "$section" "$max_ticks" "$engine" "$ticks"

    if (( tick_status != 0 )); then
      reason="tick failed with status $tick_status"
      break
    fi
    if [[ "$tick_output" == *"no section has actionable work"* ]]; then
      reason="no actionable work"
      break
    fi
  done

  printf '[%s] run-detach finished after tick %s: %s\n' \
    "$(now_iso_utc)" "$ticks" "$reason"
  if [[ -f "$PID_FILE" && "$(/bin/cat "$PID_FILE" 2>/dev/null)" == "$$" ]]; then
    rm -f -- "$PID_FILE"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  run_detach.zsh [--project <key>] start [--max-ticks N] [--section <key>]
  run_detach.zsh [--project <key>] status
EOF
}

cmd_start() {
  local max_ticks=100
  local section=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-ticks)
        shift || fail "--max-ticks requires a value"
        max_ticks="${1:-}"
        [[ "$max_ticks" == <-> && "$max_ticks" -gt 0 ]] || \
          fail "--max-ticks requires a positive integer"
        ;;
      --section)
        shift || fail "--section requires a value"
        section="${1:-}"
        [[ -n "$section" ]] || fail "--section requires a value"
        ;;
      *) fail "unknown start argument: $1" ;;
    esac
    shift || true
  done

  mkdir -p -- "$RUNS_DIR"
  local existing_pid=""
  [[ ! -f "$PID_FILE" ]] || existing_pid="$(/bin/cat "$PID_FILE" 2>/dev/null)"
  if pid_is_live "$existing_pid"; then
    printf 'pid=%s\n' "$existing_pid"
    printf 'log=%s\n' "$(state_value log)"
    return 1
  fi
  rm -f -- "$PID_FILE"

  local engine started_at log supervisor_pid
  engine="$(resolve_engine)"
  started_at="$(now_iso_utc)"
  log="$RUNS_DIR/run-detach-$(now_compact_utc).log"
  : >> "$log"

  python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    zsh -f "$SCRIPT_DIR/run_detach.zsh" __loop "$RUNS_DIR" "$PROJECT_INPUT" \
    "$section" "$max_ticks" >> "$log" 2>&1 &!
  supervisor_pid=$!

  write_state "$supervisor_pid" "$started_at" "$log" "$section" \
    "$max_ticks" "$engine" 0
  local pid_tmp="$PID_FILE.tmp.$$"
  printf '%s\n' "$supervisor_pid" > "$pid_tmp"
  mv -f -- "$pid_tmp" "$PID_FILE"

  printf 'pid=%s\n' "$supervisor_pid"
  printf 'log=%s\n' "$log"
}

cmd_status() {
  local pid started_at ticks log state="idle"
  pid="$(state_value pid)"
  started_at="$(state_value started_at)"
  ticks="$(state_value ticks)"
  log="$(state_value log)"
  if [[ -f "$PID_FILE" ]] && pid_is_live "$(/bin/cat "$PID_FILE" 2>/dev/null)"; then
    state="running"
    [[ ! -f "$STOP_FILE" ]] || state="stopping"
  fi
  printf '%s\n' "$state"
  printf 'pid=%s\n' "$pid"
  printf 'started_at=%s\n' "$started_at"
  printf 'ticks=%s\n' "$ticks"
  printf 'log=%s\n' "$log"
}

if [[ "${1:-}" == "__loop" ]]; then
  shift
  loop_main "$@"
  exit $?
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      shift || fail "--project requires a value"
      PROJECT_INPUT="${1:-}"
      [[ -n "$PROJECT_INPUT" ]] || fail "--project requires a value"
      shift || true
      ;;
    *) break ;;
  esac
done

resolve_project
case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  status) shift; [[ $# -eq 0 ]] || fail "status takes no arguments"; cmd_status ;;
  -h|--help|help|"") usage ;;
  *) fail "unknown command: $1" ;;
esac
