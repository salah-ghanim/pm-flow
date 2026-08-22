#!/bin/zsh -f
# Append one timestamped line to a dispatch's heartbeat file.
#
# This exists because of where the timestamp comes from. The natural way to
# write one inline is `printf '%s ...' "$(date -u ...)" >> heartbeat.txt`, and a
# command substitution is shell the permission layer cannot analyse statically,
# so it is refused. The role then goes silent, the supervisor sees no progress,
# and a dispatch that was working normally is killed as stalled and retried.
#
# So the timestamp is produced here and the caller passes only its message:
#
#   ./agentic/pm_flow/heartbeat.sh <file> "finished reading the existing records"
#
# No substitution, no redirect, nothing to analyse: one command, two literal
# arguments. `$PM_FLOW_HEARTBEAT` is honoured when no file is given, so a role
# that was handed the path in its environment can pass the message alone.

set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  heartbeat.sh <heartbeat-file> <message>
  heartbeat.sh <message>              # uses $PM_FLOW_HEARTBEAT

Appends "<UTC timestamp> <message>" to the heartbeat file. Keeping it current
is what stops a working dispatch being killed as stalled.
EOF
  exit 0
fi

local_file=""
message=""
if [[ $# -ge 2 ]]; then
  local_file="$1"
  shift
  message="$*"
elif [[ $# -eq 1 ]]; then
  local_file="${PM_FLOW_HEARTBEAT:-}"
  message="$1"
else
  fail "usage: heartbeat.sh <heartbeat-file> <message>"
fi

[[ -n "$local_file" ]] || fail "no heartbeat file given and PM_FLOW_HEARTBEAT is unset"
[[ -n "$message" ]] || fail "refusing to append an empty heartbeat message"

# Written on one line so a partial write cannot leave the supervisor reading a
# line that has no timestamp.
printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" >> "$local_file"
