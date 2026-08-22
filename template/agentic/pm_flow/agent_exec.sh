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

# The flow directory hosts several projects and each records its own domain, so
# resolve the calling project before falling back to the flow-wide default.
PROJECT_CONFIG_FILE=""
agent_project_key="${PM_FLOW_PROJECT:-}"
if [[ -z "$agent_project_key" && -f "$SCRIPT_DIR/.project-key" ]]; then
  agent_project_key="$(/usr/bin/head -n 1 "$SCRIPT_DIR/.project-key" | tr -d '\r')"
fi
if [[ -n "$agent_project_key" && -f "$SCRIPT_DIR/$agent_project_key/project.json" ]]; then
  PROJECT_CONFIG_FILE="$SCRIPT_DIR/$agent_project_key/project.json"
fi

# Resolve the role binding once, up front, so a misconfigured role fails before
# any model is called.
AGENT_PROJECT_DIR=""
if [[ -n "$agent_project_key" && -d "$SCRIPT_DIR/$agent_project_key" ]]; then
  AGENT_PROJECT_DIR="$SCRIPT_DIR/$agent_project_key"
fi

role_binding="$(python3 - "$CONFIG_FILE" "$ROLE" "$SEAT" "$PROJECT_CONFIG_FILE" \
    "$PROJECT_ROOT" "$AGENT_PROJECT_DIR" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
role = sys.argv[2]
seat = int(sys.argv[3])
project_config = sys.argv[4]
project_root = sys.argv[5]
project_dir = sys.argv[6]
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

access_config = config.get("access", {})
if not isinstance(access_config, dict):
    raise SystemExit("config.access must be an object")

# Three access tiers, not two.
#
#   write   the building roles; the whole repository is theirs to change
#   scoped  the managing roles; they must be able to write their own state,
#           handoff and cycle records, commit them, and run the acceptance
#           check, but must not be able to quietly rewrite source
#   read    everyone else; a review can never edit anything
#
# Before this tier existed the managing roles got no permission flag at all,
# so every write they were instructed to make was denied and their state files
# sat at template text.
write_roles = set(access_config.get("write_roles") or ["developer", "10x_developer"])
scoped_roles = set(access_config.get("scoped_roles") or ["pm", "cpo"])
if role in write_roles:
    access = "write"
elif role in scoped_roles:
    access = "scoped"
else:
    access = "read"

DEFAULT_SCOPED_BASH = [
    "git status:*", "git add:*", "git commit:*", "git diff:*", "git log:*",
    "git show:*", "git rev-parse:*", "git ls-files:*", "git branch:*",
    "git push:*", "git pull:*", "git restore --staged:*",
    "python3 -m pytest:*", ".venv/bin/python -m pytest:*", "pytest:*",
    # A reviewer that cannot run the acceptance check has to take the developer
    # at its word, so every spelling of the test runner it will reach for has to
    # be here. Bare `python` was missing and cost a real review its evidence.
    "python -m pytest:*",
    "ls:*", "cat:*", "head:*", "tail:*", "wc:*", "grep:*", "rg:*",
    # Probing the world the criteria describe: a listening port is a fact about
    # whether an external dependency is actually satisfied.
    "nc:*", "lsof:*",
    # `git -C <dir>` is how a role reaches the repo without a `cd`, and a `cd`
    # makes the command compound, which no prefix rule can match.
    "git -C:*",
    # Changing the dependency graph has to go through the validated command, so
    # the managing roles are given it and nothing else from this script. `tick`
    # and `run` are deliberately not reachable: a dispatched role must not be
    # able to dispatch the flow.
    "./agentic/pm_flow/pm_flow.sh section-dependencies:*",
    "agentic/pm_flow/pm_flow.sh section-dependencies:*",
    "./agentic/pm_flow/pm_flow.sh list-sections:*",
    "agentic/pm_flow/pm_flow.sh list-sections:*",
    "./agentic/pm_flow/pm_flow.sh status:*",
    "agentic/pm_flow/pm_flow.sh status:*",
]

# The two wrappers every role needs whatever tier it runs in.
#
# heartbeat.sh is not a convenience. Keeping the heartbeat current is what stops
# a working dispatch being killed as stalled, and the obvious inline form,
# `printf '%s ...' "$(date -u ...)" >> heartbeat.txt`, is shell the permission
# layer cannot analyse statically and therefore refuses. A refused heartbeat is
# a silent role, and a silent role is terminated and retried while it is working
# perfectly well. The wrapper exists so the timestamp needs no substitution, and
# it is allowlisted here so the call itself is not what gets refused.
#
# fetch.sh is the only way any role reads the outside world.
FLOW_WRAPPERS = [
    "./agentic/pm_flow/heartbeat.sh:*",
    "agentic/pm_flow/heartbeat.sh:*",
    "./agentic/pm_flow/fetch.sh:*",
    "agentic/pm_flow/fetch.sh:*",
]

# The audit trail. A role that can rewrite the record of what it decided cannot
# be checked against it, so the officer is denied the cycle artifacts outright.
# The section manager is not: its persona says its cycle records are its own,
# and it authors part of them.
DEFAULT_AUDIT_DENY_ROLES = ["cpo"]
DEFAULT_AUDIT_DENY_PATHS = ["**/cycles/**"]

# Everything the managing roles may write, as absolute paths. The project's own
# pm-flow workspace is always included: that is where state.md, handoff.md and
# the cycle records live.
scoped_roots = []
if project_dir:
    scoped_roots.append(project_dir)
for entry in access_config.get("scoped_write_paths") or []:
    if not isinstance(entry, str) or not entry.strip():
        continue
    candidate = entry.strip()
    if candidate.startswith("/"):
        scoped_roots.append(candidate)
    else:
        scoped_roots.append(str(Path(project_root) / candidate))

scoped_bash = access_config.get("scoped_bash")
if scoped_bash is None:
    scoped_bash = DEFAULT_SCOPED_BASH
if not isinstance(scoped_bash, list):
    raise SystemExit("config.access.scoped_bash must be a list of command prefixes")
scoped_bash = list(scoped_bash) + [
    entry for entry in FLOW_WRAPPERS if entry not in scoped_bash
]

audit_deny_roles = access_config.get("audit_deny_roles")
if audit_deny_roles is None:
    audit_deny_roles = DEFAULT_AUDIT_DENY_ROLES
audit_deny_paths = access_config.get("audit_deny_paths")
if audit_deny_paths is None:
    audit_deny_paths = DEFAULT_AUDIT_DENY_PATHS
scoped_deny = []
if role in set(audit_deny_roles):
    for root in scoped_roots:
        for pattern in audit_deny_paths:
            scoped_deny.append(str(root).rstrip("/") + "/" + str(pattern).lstrip("/"))

print(cli)
print(binding.get("model", ""))
print(difficulty)
print(access)
print(positive_int(supervision, "max_attempts", 4))
print(positive_int(supervision, "retry_backoff_seconds", 30))
print(positive_int(supervision, "usage_limit_pause_seconds", 1800))
project_domain = ""
if project_config:
    project_domain = json.loads(Path(project_config).read_text()).get("domain") or ""
print(project_domain or config.get("domain") or "generic")
print(positive_int(supervision, "heartbeat_stall_seconds", 900))
# A dispatch with no heartbeat writes nothing until it is finished, so it needs
# a far longer silence budget than one that was asked to report as it works.
print(positive_int(supervision, "silent_stall_seconds", 3600))
# A hard ceiling on one attempt, so a process that keeps producing output while
# making no progress still ends.
print(positive_int(supervision, "max_attempt_seconds", 10800))
# Single line, always last: the scoped-access policy as JSON.
print(json.dumps({
    "roots": scoped_roots,
    "bash": [str(entry) for entry in scoped_bash],
    "deny": scoped_deny,
    "isolate_settings": bool(access_config.get("scoped_isolate_settings", True)),
}))
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
SILENT_STALL_SECONDS="$(printf '%s\n' "$role_binding" | sed -n '10p')"
MAX_ATTEMPT_SECONDS="$(printf '%s\n' "$role_binding" | sed -n '11p')"
SCOPED_POLICY="$(printf '%s\n' "$role_binding" | sed -n '12p')"

file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0\n'
}

# Run one attempt in the background and watch it for silence. A role that stops
# making observable progress is treated as hung: it is killed and retried rather
# than left to block the run forever.
#
# Every dispatch is policed, not only the ones carrying a heartbeat file. A
# dispatch with no heartbeat used to get a bare `wait` with no timeout at all,
# so a wedged review blocked the run indefinitely. Such a dispatch does write
# nothing until it finishes, so it is judged against the much longer
# `silent_stall_seconds` budget and against a hard ceiling on the whole attempt.
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
  local child last_activity heartbeat_seen output_seen log_seen now_epoch
  local started_at stall_budget
  if [[ "$AGENT_CLI" == "codex" ]]; then
    ( cd "$PROJECT_ROOT" && exec python3 -c "$PGROUP_SHIM" "${AGENT_ARGV[@]}" ) > "$ATTEMPT_LOG" 2>&1 &
  else
    ( cd "$PROJECT_ROOT" && exec python3 -c "$PGROUP_SHIM" "${AGENT_ARGV[@]}" ) > "$RAW_OUTPUT" 2> "$ATTEMPT_LOG" &
  fi
  child=$!
  started_at="$(date +%s)"
  if [[ -n "$HEARTBEAT_FILE" ]]; then
    stall_budget="$STALL_SECONDS"
  else
    stall_budget="$SILENT_STALL_SECONDS"
  fi

  # Poll every second. A few cheap syscalls per second is nothing next to a
  # model call that runs for minutes, and a coarser interval would make a fast
  # agent wait just to be observed finishing.
  while kill -0 "$child" 2>/dev/null; do
    sleep 1
    kill -0 "$child" 2>/dev/null || break
    now_epoch="$(date +%s)"
    # The attempt log is the only stream that receives incremental output on
    # every backend, so it counts as activity. Leaving it out made the sole
    # liveness signal a file the role was merely asked to append to.
    output_seen="$(file_mtime "$RAW_OUTPUT")"
    log_seen="$(file_mtime "$ATTEMPT_LOG")"
    heartbeat_seen=0
    [[ -z "$HEARTBEAT_FILE" ]] || heartbeat_seen="$(file_mtime "$HEARTBEAT_FILE")"
    last_activity=$(( output_seen > log_seen ? output_seen : log_seen ))
    last_activity=$(( heartbeat_seen > last_activity ? heartbeat_seen : last_activity ))
    last_activity=$(( last_activity > 0 ? last_activity : started_at ))
    if (( now_epoch - last_activity >= stall_budget )); then
      if [[ -n "$HEARTBEAT_FILE" ]]; then
        printf '%s stalled with no progress for %ss; terminating\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stall_budget" >> "$HEARTBEAT_FILE"
      fi
      printf 'pm-flow: %s stalled with no progress for %ss; terminating\n' \
        "$LABEL" "$stall_budget" >> "$ATTEMPT_LOG"
      terminate_group "$child"
      STALLED="1"
      break
    fi
    if (( now_epoch - started_at >= MAX_ATTEMPT_SECONDS )); then
      printf 'pm-flow: %s exceeded the %ss attempt ceiling; terminating\n' \
        "$LABEL" "$MAX_ATTEMPT_SECONDS" >> "$ATTEMPT_LOG"
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

# Render the scoped tier as a claude settings file. The tier is expressed as an
# allow-list under the default permission mode: a headless run cannot prompt, so
# anything the list does not name is denied outright. `acceptEdits` is
# deliberately not used here, because it would accept every edit including the
# ones this tier exists to refuse.
write_scoped_settings() {
  local settings_path="$1"
  python3 - "$settings_path" "$SCOPED_POLICY" <<'PY'
import json
import sys
from pathlib import Path

settings_path, policy_json = sys.argv[1:]
policy = json.loads(policy_json)

allow = []
for root in policy.get("roots", []):
    # A leading `//` is how a claude permission rule spells an absolute path.
    pattern = "//" + str(root).lstrip("/").rstrip("/") + "/**"
    for tool in ("Edit", "Write", "NotebookEdit"):
        allow.append(f"{tool}({pattern})")
for prefix in policy.get("bash", []):
    allow.append(f"Bash({prefix})")

# Deny wins over allow, so this carves the audit trail back out of the roots
# granted above.
deny = []
for entry in policy.get("deny", []):
    pattern = "//" + str(entry).lstrip("/")
    for tool in ("Edit", "Write", "NotebookEdit"):
        deny.append(f"{tool}({pattern})")

Path(settings_path).write_text(json.dumps({
    "permissions": {"defaultMode": "default", "allow": allow, "deny": deny},
}, indent=2) + "\n")
PY
}

build_command() {
  local settings_path
  case "$AGENT_CLI" in
    claude)
      AGENT_ARGV=(claude -p --output-format json --effort "$AGENT_DIFFICULTY" --add-dir "$PROJECT_ROOT")
      [[ -z "$AGENT_MODEL" ]] || AGENT_ARGV+=(--model "$AGENT_MODEL")
      case "$AGENT_ACCESS" in
        write)
          # acceptEdits auto-accepts file edits, not Bash. An unrecognised
          # local script still prompts, and a prompt in a headless run is a
          # denial, so the wrappers are named explicitly or the role cannot
          # heartbeat and cannot read a page.
          # Bare `Bash` first, because naming only the wrappers turns the grant
          # into the whole allow-list and takes away everything else: a
          # developer that cannot run its own test command, or an analyst that
          # cannot validate the file it just wrote, is worse off than before
          # the wrappers existed. The wrapper rules stay because a rule that
          # names the script survives a stricter default later.
          AGENT_ARGV+=(--permission-mode acceptEdits
                       --allowedTools
                       "Bash"
                       "Bash(./agentic/pm_flow/heartbeat.sh:*)"
                       "Bash(agentic/pm_flow/heartbeat.sh:*)"
                       "Bash(./agentic/pm_flow/fetch.sh:*)"
                       "Bash(agentic/pm_flow/fetch.sh:*)")
          ;;
        scoped)
          settings_path="$WORK_DIR/scoped_settings.json"
          write_scoped_settings "$settings_path"
          AGENT_ARGV+=(--settings "$settings_path")
          # Ambient user or project settings could grant back exactly what this
          # tier withholds, so the policy is the only one loaded.
          if [[ "$(printf '%s' "$SCOPED_POLICY" | python3 -c 'import json,sys; print("1" if json.load(sys.stdin).get("isolate_settings") else "0")')" == "1" ]]; then
            AGENT_ARGV+=(--setting-sources "")
          fi
          ;;
      esac
      AGENT_ARGV+=(-- "$(/bin/cat "$PROMPT_FILE")")
      ;;
    codex)
      AGENT_ARGV=(codex exec --ephemeral --cd "$PROJECT_ROOT"
                  -c "model_reasoning_effort=$(codex_effort "$AGENT_DIFFICULTY")"
                  -o "$RAW_OUTPUT")
      [[ -z "$AGENT_MODEL" ]] || AGENT_ARGV+=(-m "$AGENT_MODEL")
      case "$AGENT_ACCESS" in
        # codex makes the working root writable and offers no way to narrow
        # below it while keeping repo-relative paths meaningful, so the scoped
        # tier is only a prompt-level boundary on this backend. Bind the
        # managing roles to a backend that can express the tier if that matters.
        write|scoped) AGENT_ARGV+=(--sandbox workspace-write) ;;
        *)            AGENT_ARGV+=(--sandbox read-only) ;;
      esac
      AGENT_ARGV+=("$(/bin/cat "$PROMPT_FILE")")
      ;;
    copilot)
      # --no-custom-instructions keeps the repository's own agent instructions
      # out of a role that was given an explicit persona.
      AGENT_ARGV=(copilot -p "$(/bin/cat "$PROMPT_FILE")"
                  --effort "$AGENT_DIFFICULTY" --add-dir "$PROJECT_ROOT"
                  --no-custom-instructions --no-ask-user --silent --stream off)
      [[ -z "$AGENT_MODEL" ]] || AGENT_ARGV+=(--model "$AGENT_MODEL")
      case "$AGENT_ACCESS" in
        # Same limitation as codex: the boundary is stated in the prompt only.
        write|scoped) AGENT_ARGV+=(--allow-all-tools) ;;
      esac
      ;;
  esac
}

# Classify a failed attempt from the CLI's own output.
#
# `permanent` is an allow-list, not the fall-through. The fall-through used to
# be "fatal", which meant one unrecognised transport string ended an unattended
# run outright. An unenumerated fault is far more often a new way of spelling a
# transport error than a genuinely permanent one, so the unknown case is retried
# once and only a named permanent condition refuses retry outright.
classify_failure() {
  python3 - "$@" <<'PY'
import re
import sys
from pathlib import Path

text = "\n".join(
    Path(path).read_text(errors="replace")
    for path in sys.argv[1:]
    if Path(path).is_file()
).lower()
# A CLI envelope carries telemetry whose *key names* read like failures:
# `"refused":{"depth_limit":0,...}` with every counter at zero says nothing was
# refused, but the bare substring is enough to condemn a dispatch as permanent
# and skip the retry it needed. Strip JSON keys before matching; a real error
# states itself in a value or on stderr, never in a key.
text = re.sub(r'\\?"[a-z_][a-z0-9_]*\\?"\s*:', " ", text)
usage = [
    r"usage limit", r"rate limit", r"rate.?limited", r"quota", r"429",
    r"too many requests", r"insufficient.{0,20}credit",
]
network = [
    r"econnreset", r"etimedout", r"enotfound", r"econnrefused", r"eai_again",
    r"network error", r"fetch failed", r"socket hang up", r"connection reset",
    r"\b50[2349]\b", r"overloaded", r"timed? ?out",
    # The host slept or was suspended mid-call. The work is interrupted, not
    # refused, and the next attempt usually succeeds.
    r"went to sleep", r"response above may be incomplete",
    # A connection that dies mid-stream is transport-level by definition, and
    # the work is already paid for by the time it happens.
    r"connection closed", r"closed mid-response", r"premature close",
]
# Conditions where the same call will get the same answer. Retrying any of
# these spends quota to learn nothing.
permanent = [
    r"invalid api key", r"authentication.{0,20}fail", r"unauthorized",
    r"\b401\b", r"\b403\b", r"not logged in", r"please run .{0,20}login",
    r"credentials?.{0,20}(?:not found|missing|expired|invalid)",
    r"unknown model", r"invalid model", r"model .{0,40}(?:not found|does not exist)",
    r"unrecognized (?:option|argument|flag)", r"unknown (?:option|argument|flag)",
    r"invalid (?:option|argument|flag)", r"no such (?:option|file or directory)",
    r"usage: ", r"command not found",
    r"refus(?:e|ed|al)", r"violat", r"content policy", r"safety policy",
]
for pattern in usage:
    if re.search(pattern, text):
        print("usage_limit"); break
else:
    for pattern in network:
        if re.search(pattern, text):
            print("network"); break
    else:
        for pattern in permanent:
            if re.search(pattern, text):
                print("permanent"); break
        else:
            print("unknown")
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
# Backends other than claude do not report what the call cost. The field is
# still written so every response envelope has the same shape and the driver's
# budget accounting can tell "nothing was spent" from "the cost is unknown".
cost = None
if cli == "claude":
    try:
        reported = json.loads(text).get("total_cost_usd")
        cost = float(reported) if reported is not None else None
    except (ValueError, AttributeError, TypeError):
        cost = None
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
    "total_cost_usd": cost,
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
  if [[ "$AGENT_ACCESS" == "scoped" && -f "$WORK_DIR/scoped_settings.json" ]]; then
    printf 'scoped_policy=\n'
    /bin/cat "$WORK_DIR/scoped_settings.json"
  fi
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
failure_output="$ATTEMPT_LOG"
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
    reason="$(classify_failure "$ATTEMPT_LOG" "$RAW_OUTPUT")"
  fi
  failure_output="$ATTEMPT_LOG"
  [[ ! -s "$RAW_OUTPUT" ]] || failure_output="$RAW_OUTPUT"
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
    unknown)
      # Not recognised either way. Buy exactly one more attempt: most such
      # faults are transport errors nobody has enumerated yet, and a second
      # identical failure is evidence that it is not one.
      if (( attempt >= 2 )); then
        printf 'pm-flow: %s failed twice with an unrecognised error; giving up\n' "$AGENT_CLI" >&2
        /usr/bin/tail -n 20 "$ATTEMPT_LOG" >&2 || true
        write_response "$failure_output" "1" "unknown" "$attempt"
        exit 3
      fi
      local_backoff=$(( RETRY_BACKOFF * attempt ))
      printf 'pm-flow: %s failed with an unrecognised error; retrying once in %ss\n' \
        "$AGENT_CLI" "$local_backoff" >&2
      sleep "$local_backoff"
      ;;
    *)
      # A named permanent condition. Retrying spends quota to get the same
      # answer.
      printf 'pm-flow: %s failed and the error is permanent\n' "$AGENT_CLI" >&2
      /usr/bin/tail -n 20 "$ATTEMPT_LOG" >&2 || true
      write_response "$failure_output" "1" "permanent" "$attempt"
      exit 3
      ;;
  esac
  (( attempt += 1 ))
done

if [[ "$final_reason" != "none" ]]; then
  printf 'pm-flow: gave up on role %s after %d attempts (%s)\n' \
    "$ROLE" "$MAX_ATTEMPTS" "$final_reason" >&2
  write_response "$failure_output" "1" "$final_reason" "$MAX_ATTEMPTS"
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
# claude already reports total_cost_usd; keep it and normalise its type so the
# driver's budget accounting never has to guess.
try:
    reported = payload.get("total_cost_usd")
    payload["total_cost_usd"] = float(reported) if reported is not None else None
except (ValueError, TypeError):
    payload["total_cost_usd"] = None
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
