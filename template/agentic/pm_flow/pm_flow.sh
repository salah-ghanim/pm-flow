#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
PROJECT_ROOT="$(cd -P -- "$SCRIPT_DIR/../.." && pwd -P)"
PM_SYSTEM_PROMPT="You are a section-scoped project management reviewer for another software agent. You are not the acting PM and you have no sub-agents: your entire output is a written review that the calling section PM will act on. Reason only about the assigned project section. Review the proposed engineering step or completion report, critique the reasoning, detect mission drift, suggest improvements, approve or reject the path forward, and name the next bounded assignment. Do not write code, do not edit files, and do not attempt to launch agents or run the flow's commands yourself. Recommend that each implementation assignment go to a fresh developer sub-agent with no inherited conversation, seeded only with the bounded assignment and explicitly allowlisted files. Focus on scope control, validation, sequencing, risks, interfaces, and drift management. Be direct and concrete, and answer only with the requested sections."
PROJECT_OVERRIDE="${PM_FLOW_PROJECT:-}"
SECTION_OVERRIDE="${PM_FLOW_SECTION:-}"
PROJECT_KEY=""
PROJECT_DIR=""
RUNS_DIR=""
STATE_DIR=""
CURRENT_RUN_FILE=""
CONTRACT_FILE=""
SECTIONS_DIR=""
SECTIONS_INDEX_FILE=""
SECTION_KEY=""
SECTION_NAME=""
SECTION_DIR=""
RUN_RECORD_LOCK=""
SECTION_CREATE_LOCK=""
SESSION_REVISION="0"
typeset -A LEGACY_METADATA

usage() {
  cat <<'EOF'
Usage:
  pm_flow.sh [--project <name>] validate
  pm_flow.sh [--project <name>] config
  pm_flow.sh [--project <name>] role-prompt <role>
  pm_flow.sh [--project <name>] consult-panel <section-name> [--file <markdown-file>]
  pm_flow.sh [--project <name>] init <task-name>
  pm_flow.sh [--project <name>] init-section <section-name>
  pm_flow.sh [--project <name>] init-section <section-name> --file <markdown-file>
  pm_flow.sh [--project <name>] list-sections
  pm_flow.sh [--project <name>] section-prompt <section-name>
  pm_flow.sh [--project <name>] section-run <section-name>
  pm_flow.sh [--project <name>] section-handoff <section-name> <status> <summary>
  pm_flow.sh [--project <name>] section-handoff <section-name> <status> <summary> --file <markdown-file>
  pm_flow.sh [--project <name>] adopt-pending <legacy-pending-dir>
  pm_flow.sh [--project <name>] cancel-pending <pending-dir> [reason]
  pm_flow.sh [--project <name>] rotate-session <run-dir> [reason]
  pm_flow.sh [--project <name>] [--section <name>] prepare-step <run-dir> <stage-name>
  pm_flow.sh [--project <name>] [--section <name>] prepare-step <run-dir> <stage-name> --file <markdown-file>
  pm_flow.sh [--project <name>] record-step <pending-dir>
  pm_flow.sh [--project <name>] record-step <pending-dir> --response-file <markdown-file>
  pm_flow.sh [--project <name>] [--section <name>] prepare-complete <run-dir>
  pm_flow.sh [--project <name>] [--section <name>] prepare-complete <run-dir> --file <markdown-file>
  pm_flow.sh [--project <name>] record-complete <pending-dir>
  pm_flow.sh [--project <name>] record-complete <pending-dir> --response-file <markdown-file>
  pm_flow.sh [--project <name>] print-command <pending-dir>
  pm_flow.sh [--project <name>] [--section <name>] current-run

  Important:
  This script never invokes `claude -p`.
  It writes a top-shell Claude command into command.txt routed through
  `./agentic/pm_flow/net_exec.sh`.
  One section owns one isolated, resumable PM session and one audit run.
  The root coordinator reads list-sections output and bounded handoff.md files,
  never section transcripts or developer conversations.
  Each section PM must create a no-history developer sub-agent for every implementation assignment.
  The first section PM call uses `claude -p --output-format json`; later calls
  add `--resume <session_id>` using the captured value from response.json.
  Use `--section <name>` with the special run-dir value `current` to target
  that section without relying on the project-global legacy pointer.
  The active project defaults to the repo basename when that project directory exists.
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

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

repo_relative_path() {
  local target_path="$1"
  python3 - "$PROJECT_ROOT" "$target_path" <<'PY'
from pathlib import Path
import os
import sys

project_root = Path(sys.argv[1]).resolve()
target_path = Path(sys.argv[2]).resolve()
print(os.path.relpath(target_path, project_root))
PY
}

write_current_run_file() {
  local run_path="$1"
  ensure_state_dir
  local current_tmp="${CURRENT_RUN_FILE}.$$.tmp"
  printf '%s\n' "$(repo_relative_path "$run_path")" > "$current_tmp"
  mv "$current_tmp" "$CURRENT_RUN_FILE"
}

resolve_current_run() {
  ensure_state_dir
  if [[ -n "${SECTION_OVERRIDE:-}" ]]; then
    resolve_section_run "$SECTION_OVERRIDE"
    return
  fi
  [[ -f "$CURRENT_RUN_FILE" ]] || fail "missing current run pointer: $CURRENT_RUN_FILE"
  python3 - "$PROJECT_ROOT" "$CURRENT_RUN_FILE" <<'PY'
from pathlib import Path
import sys

project_root = Path(sys.argv[1]).resolve()
current_run_file = Path(sys.argv[2])
lines = current_run_file.read_text().splitlines()
rel_path = lines[0].strip() if lines else ""
if not rel_path or rel_path == "none":
    raise SystemExit(1)
print((project_root / rel_path).resolve())
PY
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

resolve_project_key() {
  if [[ -n "${PROJECT_OVERRIDE:-}" ]]; then
    printf '%s\n' "$(slugify "$PROJECT_OVERRIDE")"
    return
  fi
  local key_file="$SCRIPT_DIR/.project-key"
  if [[ -f "$key_file" ]]; then
    local persisted_project
    persisted_project="$(/usr/bin/head -n 1 "$key_file" | tr -d '\r')"
    [[ -n "$persisted_project" && "$persisted_project" == "$(slugify "$persisted_project")" ]] || \
      fail "invalid persisted project key: $key_file"
    [[ -d "$SCRIPT_DIR/$persisted_project" ]] || \
      fail "persisted project workspace does not exist: $SCRIPT_DIR/$persisted_project"
    printf '%s\n' "$persisted_project"
    return
  fi
  local default_project
  default_project="$(slugify "$(basename "$PROJECT_ROOT")")"
  if [[ -d "$SCRIPT_DIR/$default_project" ]]; then
    printf '%s\n' "$default_project"
    return
  fi
  fail "could not resolve project under $SCRIPT_DIR; use --project <name>"
}

AGENT_CONFIG_FILE=""
ROLES_DIR=""
DOMAINS_DIR=""

# Roles are named, never vendors. This composes a role's persona with the
# project's configured domain so prompts read as a real practitioner in the
# problem space instead of a generic assistant.
compose_role_prompt() {
  local role="$1"
  [[ -f "$AGENT_CONFIG_FILE" ]] || fail "missing agent config: $AGENT_CONFIG_FILE"
  local role_file="$ROLES_DIR/$role.md"
  [[ -f "$role_file" ]] || fail "unknown role '$role'; no persona at $role_file"
  local project_name="$PROJECT_KEY"
  if [[ -f "$CONTRACT_FILE" ]]; then
    local contract_heading
    contract_heading="$(/usr/bin/head -n 1 "$CONTRACT_FILE" | sed -E 's/^#[[:space:]]*//; s/[[:space:]]+Task Contract[[:space:]]*$//')"
    [[ -z "$contract_heading" ]] || project_name="$contract_heading"
  fi
  python3 - "$AGENT_CONFIG_FILE" "$DOMAINS_DIR" "$role_file" "$role" "$project_name" <<'PY'
import json
import sys
from pathlib import Path

config_path, domains_dir, role_path, role, project_name = sys.argv[1:]
config = json.loads(Path(config_path).read_text())
domain = config.get("domain") or "generic"
domain_file = Path(domains_dir) / f"{domain}.json"
if not domain_file.is_file():
    raise SystemExit(f"unknown domain {domain!r}; no definition at {domain_file}")
definition = json.loads(domain_file.read_text())
titles = definition.get("titles", {})
if role not in titles:
    raise SystemExit(f"domain {domain!r} does not define a title for role {role!r}")
context = definition.get("context", [])
rendered = Path(role_path).read_text()
rendered = rendered.replace("{{ROLE_TITLE}}", titles[role])
rendered = rendered.replace("{{DOMAIN_LABEL}}", definition.get("label", "software project"))
rendered = rendered.replace("{{DOMAIN_CONTEXT}}", "\n".join(f"- {line}" for line in context))
rendered = rendered.replace("{{PROJECT_NAME}}", project_name)
sys.stdout.write(rendered)
PY
}

role_seat_count() {
  local role="$1"
  python3 - "$AGENT_CONFIG_FILE" "$role" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
binding = config.get("roles", {}).get(sys.argv[2])
if binding is None:
    raise SystemExit(f"unknown role: {sys.argv[2]}")
print(len(binding) if isinstance(binding, list) else 1)
PY
}

# Compose a role's standing persona with the specific task it is being asked to
# perform on this call. Persona and task are separate so the same role can be
# given different work without rewriting who it is.
compose_role_task() {
  local role="$1"
  local task_file="$2"
  shift 2
  compose_role_prompt "$role"
  printf '\n'
  python3 - "$task_file" "$@" <<'PY'
import sys
from pathlib import Path

rendered = Path(sys.argv[1]).read_text()
for pair in sys.argv[2:]:
    if "=" not in pair:
        raise SystemExit(f"task substitution must be key=value, got {pair!r}")
    key, value = pair.split("=", 1)
    rendered = rendered.replace("{{" + key + "}}", value)
sys.stdout.write(rendered)
PY
}

# Run every consultant seat against the same brief, at the same time, with no
# seat able to see another's answer. Independence is the whole point of a panel.
cmd_consult_panel() {
  local section_input="${1:-}"
  [[ -n "$section_input" ]] || fail "consult-panel requires a section name"
  local body_mode="stdin"
  local body_path=""
  if [[ "${2:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown consult-panel argument: ${2:-}"
  fi

  local section_dir failure_brief
  section_dir="$(resolve_section_dir "$section_input")"
  failure_brief="$(read_body_arg "$body_mode" "$body_path")"
  [[ -n "$failure_brief" ]] || fail "the failure brief must not be empty"

  local seat_count
  seat_count="$(role_seat_count consultant)"
  [[ "$seat_count" -ge 1 ]] || fail "the consultant role has no seats"

  local panel_dir="$section_dir/panels/$(now_compact_utc)-$(lower_uuid | cut -c1-8)"
  mkdir -p "$panel_dir"
  printf '%s\n' "$failure_brief" > "$panel_dir/failure_brief.md"

  local consultant_persona="$panel_dir/consultant_prompt.md"
  {
    compose_role_prompt consultant
    printf '\n---\n\n# The section that failed\n\n'
    printf 'Section: %s\n\n' "$(basename "$section_dir")"
    printf 'Read `%s` for the section brief and `%s` for the failure history.\n\n' \
      "$(repo_relative_path "$section_dir/brief.md")" \
      "$(repo_relative_path "$panel_dir/failure_brief.md")"
    printf 'Respond with these sections only, each as a Markdown heading:\n'
    printf '1. Diagnosis\n2. Prior art considered\n3. Alternatives\n4. What would prove each one\n5. Decision\n\n'
    printf 'The Decision section must contain exactly one line, and that line must\n'
    printf 'begin with one of these exact tokens: ALTERNATIVE, RETRY_INFORMED, ABANDON.\n'
    printf 'A short justification may follow the token on the same line.\n'
  } > "$consultant_persona"

  local seat pids=() seat_status=0
  for seat in {1..$seat_count}; do
    (
      "$SCRIPT_DIR/agent_exec.sh" consultant \
        --seat "$seat" \
        --prompt-file "$consultant_persona" \
        --output "$panel_dir/proposal_${seat}.json" \
        --heartbeat "$panel_dir/heartbeat_seat_${seat}.txt" \
        --label "consultant seat $seat" \
        > "$panel_dir/seat_${seat}.log" 2>&1
    ) &
    pids+=($!)
  done
  for seat in {1..$seat_count}; do
    wait "${pids[$seat]}" || seat_status=1
  done

  # A seat that errors, times out, or returns something unreadable must not take
  # the panel down with it. That tolerance is the reason to run a panel at all.
  local delivered=0
  for seat in {1..$seat_count}; do
    [[ -f "$panel_dir/proposal_${seat}.json" ]] || continue
    if python3 - "$panel_dir/proposal_${seat}.json" "$panel_dir/proposal_${seat}.md" <<'PY' 2>>"$panel_dir/seat_errors.log"
import json
import sys
from pathlib import Path

try:
    payload = json.loads(Path(sys.argv[1]).read_text())
except json.JSONDecodeError as error:
    raise SystemExit(f"seat response is not valid JSON: {error}")
if payload.get("is_error"):
    raise SystemExit(f"seat reported an error: {payload.get('failure_reason', 'unknown')}")
text = (payload.get("result") or "").strip()
if not text:
    raise SystemExit("seat returned an empty proposal")
Path(sys.argv[2]).write_text(text + "\n")
PY
    then
      delivered=$(( delivered + 1 ))
    else
      printf 'WARNING: consultant seat %d did not produce a usable proposal\n' "$seat" >&2
    fi
  done

  [[ "$delivered" -ge 1 ]] || fail "no consultant seat produced a usable proposal; see $panel_dir"
  if [[ "$delivered" -lt "$seat_count" ]]; then
    printf 'WARNING: only %d of %d consultant seats answered; adjudicating on what arrived\n' \
      "$delivered" "$seat_count" >&2
  fi

  local panel_files=""
  for seat in {1..$seat_count}; do
    [[ -f "$panel_dir/proposal_${seat}.md" ]] || continue
    panel_files+="- Proposal ${seat}: $(repo_relative_path "$panel_dir/proposal_${seat}.md")"$'\n'
  done
  panel_files+="- Failure brief: $(repo_relative_path "$panel_dir/failure_brief.md")"$'\n'
  panel_files+="- Section brief: $(repo_relative_path "$section_dir/brief.md")"

  compose_role_task cpo \
    "$SCRIPT_DIR/tasks/consultant_panel_adjudication.md" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "PANEL_FILES=$panel_files" \
    > "$panel_dir/adjudication_prompt.md"

  printf 'panel_dir=%s\n' "$panel_dir"
  printf 'seats=%s\n' "$seat_count"
  printf 'proposals=%s\n' "$delivered"
  printf 'adjudication_prompt=%s\n' "$panel_dir/adjudication_prompt.md"
  [[ "$seat_status" == "0" ]] || printf 'note=at least one seat failed; see the seat logs\n'
}

cmd_role_prompt() {
  local role="${1:-}"
  [[ -n "$role" ]] || fail "role-prompt requires a role name"
  compose_role_prompt "$role"
}

cmd_config() {
  [[ -f "$AGENT_CONFIG_FILE" ]] || fail "missing agent config: $AGENT_CONFIG_FILE"
  python3 - "$AGENT_CONFIG_FILE" "$DOMAINS_DIR" "$ROLES_DIR" <<'PY'
import json
import sys
from pathlib import Path

config_path, domains_dir, roles_dir = sys.argv[1:]
config = json.loads(Path(config_path).read_text())
if config.get("version") != 1:
    raise SystemExit(f"unsupported config version: {config.get('version')!r}")
domain = config.get("domain") or "generic"
domain_file = Path(domains_dir) / f"{domain}.json"
if not domain_file.is_file():
    raise SystemExit(f"unknown domain {domain!r}; no definition at {domain_file}")
titles = json.loads(domain_file.read_text()).get("titles", {})

print(f"domain={domain}")
roles = config.get("roles", {})
if not roles:
    raise SystemExit("config.json defines no roles")
for name in sorted(roles):
    binding = roles[name]
    seats = binding if isinstance(binding, list) else [binding]
    if not seats:
        raise SystemExit(f"role {name!r} is an empty panel")
    if not (Path(roles_dir) / f"{name}.md").is_file():
        raise SystemExit(f"role {name!r} has no persona file under {roles_dir}")
    if name not in titles:
        raise SystemExit(f"domain {domain!r} does not define a title for role {name!r}")
    print(f"{name}: seats={len(seats)} title={titles[name]!r}")
    for index, seat in enumerate(seats, start=1):
        if not isinstance(seat, dict):
            raise SystemExit(f"role {name!r} seat {index} has an invalid binding")
        cli = seat.get("cli", "")
        if cli not in {"claude", "codex", "copilot"}:
            raise SystemExit(f"role {name!r} seat {index} has an unsupported cli: {cli!r}")
        difficulty = seat.get("difficulty", "medium")
        if difficulty not in {"low", "medium", "high", "xhigh", "max"}:
            raise SystemExit(f"role {name!r} seat {index} has an invalid difficulty: {difficulty!r}")
        print(f"  seat {index}: cli={cli} model={seat.get('model') or '(cli default)'} "
              f"difficulty={difficulty}")
    if len(seats) > 1 and len({seat.get("cli") for seat in seats}) == 1:
        print(f"  note: every {name} seat uses the same cli, which weakens an "
              f"independent panel")
PY
}

initialize_project_paths() {
  PROJECT_KEY="$(resolve_project_key)"
  PROJECT_DIR="$SCRIPT_DIR/$PROJECT_KEY"
  AGENT_CONFIG_FILE="$SCRIPT_DIR/config.json"
  ROLES_DIR="$SCRIPT_DIR/roles"
  DOMAINS_DIR="$SCRIPT_DIR/domains"
  RUNS_DIR="$PROJECT_DIR/runs"
  STATE_DIR="$PROJECT_DIR/project_state"
  CURRENT_RUN_FILE="$STATE_DIR/current_run.txt"
  CONTRACT_FILE="$PROJECT_DIR/task_contract.md"
  SECTIONS_DIR="$PROJECT_DIR/sections"
  SECTIONS_INDEX_FILE="$STATE_DIR/sections.md"
}

resolve_section_dir() {
  local section_input="${1:-}"
  [[ -n "$section_input" ]] || fail "section name is required"
  local section_key
  section_key="$(slugify "$section_input")"
  local section_dir="$SECTIONS_DIR/$section_key"
  [[ -d "$section_dir" ]] || fail "unknown section: $section_input"
  printf '%s\n' "$section_dir"
}

resolve_section_run() {
  local section_dir
  section_dir="$(resolve_section_dir "$1")"
  local run_path_file="$section_dir/run_path.txt"
  [[ -f "$run_path_file" ]] || fail "section has no run pointer: $run_path_file"
  python3 - "$PROJECT_ROOT" "$run_path_file" <<'PY'
from pathlib import Path
import sys

project_root = Path(sys.argv[1]).resolve()
pointer = Path(sys.argv[2])
lines = pointer.read_text().splitlines()
rel_path = lines[0].strip() if lines else ""
if not rel_path or rel_path == "none":
    raise SystemExit(1)
run_path = (project_root / rel_path).resolve()
try:
    run_path.relative_to(project_root)
except ValueError:
    raise SystemExit("section run pointer escapes the project root")
if not run_path.is_dir():
    raise SystemExit("section run directory does not exist")
print(run_path)
PY
}

refresh_sections_index() {
  ensure_state_dir
  mkdir -p "$SECTIONS_DIR"
  python3 - "$PROJECT_ROOT" "$PROJECT_DIR" "$SECTIONS_DIR" "$SECTIONS_INDEX_FILE" "$SECTIONS_DIR/.index.lock" <<'PY'
from pathlib import Path
import fcntl
import os
import sys

project_root = Path(sys.argv[1]).resolve()
project_dir = Path(sys.argv[2]).resolve()
sections_dir = Path(sys.argv[3]).resolve()
index_path = Path(sys.argv[4]).resolve()
# The mutex lives beside the data it guards. Under tempfile.gettempdir() two
# workers with different TMPDIR values lock different files and exclude nothing.
lock_path = Path(sys.argv[5])
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock_path.touch(exist_ok=True)

def first_line(path: Path, default: str) -> str:
    if not path.is_file():
        return default
    lines = path.read_text().splitlines()
    value = lines[0].strip() if lines else ""
    return value or default

def cell(value: str) -> str:
    return " ".join(value.split()).replace("|", r"\|")

index_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open("a+") as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    rows = []
    for section_dir in sorted(p for p in sections_dir.iterdir() if p.is_dir() and not p.name.startswith(".")):
        name = first_line(section_dir / "name.txt", section_dir.name)
        status = first_line(section_dir / "status.txt", "unknown")
        summary = first_line(section_dir / "summary.txt", "No bounded handoff yet.")
        updated = first_line(section_dir / "updated_at.txt", "unknown")
        run_path = first_line(section_dir / "run_path.txt", "none")
        handoff_path = section_dir / "handoff.md"
        handoff_rel = os.path.relpath(handoff_path, index_path.parent)
        rows.append(
            f"| {cell(name)} | {cell(status)} | {cell(summary)} | "
            f"[handoff]({cell(handoff_rel)}) | `{cell(run_path)}` | {cell(updated)} |"
        )

    lines = [
        "# Project sections",
        "",
        "This is a generated, bounded portfolio view for the root project coordinator.",
        "Per-section files are authoritative; run `pm_flow.sh list-sections` to refresh this index.",
        "The root coordinator should read this file and the linked handoffs, not section transcripts.",
        "",
        "| Section | Status | Summary | PM handoff | Run | Updated (UTC) |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    lines.extend(rows or ["| _none_ | — | Create a section with `init-section`. | — | — | — |"])
    lines.extend([
        "",
        "Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.",
        "A handoff is capped at 500 words and 8192 bytes and carries only outcomes, decisions, interfaces, risks, and the next action.",
        "",
    ])

    temp_path = index_path.with_name(f".{index_path.name}.{os.getpid()}.tmp")
    temp_path.write_text("\n".join(lines))
    os.replace(temp_path, index_path)
PY
}

commit_section_handoff_files() {
  local section_dir="$1"
  local handoff_tmp="$2"
  local section_status="$3"
  local summary="$4"
  local updated_at="$5"
  python3 - "$PROJECT_DIR" "$section_dir" "$handoff_tmp" "$section_status" "$summary" "$updated_at" "$SECTIONS_DIR/.index.lock" <<'PY'
from pathlib import Path
import fcntl
import os
import sys

project_dir = Path(sys.argv[1]).resolve()
section_dir = Path(sys.argv[2]).resolve()
handoff_tmp = Path(sys.argv[3]).resolve()
status, summary, updated_at = sys.argv[4:7]
lock_path = Path(sys.argv[7])
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock_path.touch(exist_ok=True)

def atomic_text(path: Path, value: str) -> None:
    temp_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temp_path.write_text(value + "\n")
    os.replace(temp_path, path)

with lock_path.open("a+") as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    os.replace(handoff_tmp, section_dir / "handoff.md")
    atomic_text(section_dir / "status.txt", status)
    atomic_text(section_dir / "summary.txt", summary)
    atomic_text(section_dir / "updated_at.txt", updated_at)
PY
}

write_section_pm_prompt() {
  local section_dir="$1"
  local section_name="$2"
  local section_key="$3"
  local run_path="$4"
  local logical_section_dir="${5:-$section_dir}"
  local section_rel
  section_rel="$(repo_relative_path "$logical_section_dir")"
  cat > "$section_dir/pm_prompt.md" <<EOF
# Section PM launch prompt: $section_name

You are the long-lived PM sub-agent for exactly one project section: \`$section_name\` (\`$section_key\`).
The root agent coordinates the whole project; you own this section end to end.
You must have been created without inherited root conversation history, seeded
only with this prompt. (Claude Code subagents already start fresh; in Codex
collaboration the root must launch you with \`fork_turns="none"\`.)

Read only the bounded context needed to start:

1. \`$section_rel/brief.md\`
2. \`$section_rel/state.md\`
3. \`$section_rel/handoff.md\`
4. \`$(repo_relative_path "$CONTRACT_FILE")\`
5. Dependency handoffs explicitly named in the section brief

The audit run is \`$(repo_relative_path "$run_path")\`. Do not load its full transcript merely to reconstruct context.

Operating contract:

- Break this section into bounded engineering assignments.
- Spawn a fresh developer sub-agent for every assignment with no inherited PM conversation.
- Never resume, reuse, or keep a developer conversation alive.
- Give each developer only its objective, owned paths, constraints, acceptance checks, and the minimum relevant files.
- Review the developer's report and validation evidence before deciding the next assignment.
- Keep detailed section decisions and progress in \`$section_rel/state.md\`.
- After every material outcome or blocker, replace the bounded handoff with:
  \`./agentic/pm_flow/pm_flow.sh section-handoff "$section_key" <status> "<one-line summary>" --file <handoff-file>\`
- Keep the handoff at 500 words and 8192 bytes or fewer with these headings: Outcome, Decisions, Interfaces, Risks, Next action.
- Report to the root coordinator through the handoff only. Do not send raw transcripts or developer conversations upward.
- Do not manage another section. Escalate cross-section changes through Interfaces or Risks so the root coordinator can reconcile them.
- Do not implement code yourself; manage, delegate, review, validate, and integrate this section.

Continue until this section is validated as done, explicitly blocked, or cancelled.
EOF
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
  python3 - \
    "$meta_path" \
    "$TASK_NAME" \
    "$TASK_SLUG" \
    "${SECTION_KEY:-}" \
    "${SESSION_ID:-}" \
    "${SESSION_STARTED:-0}" \
    "${SESSION_REVISION:-0}" \
    "$CREATED_AT_UTC" <<'PY'
from pathlib import Path
import json
import os
import sys

path = Path(sys.argv[1])
payload = {
    "version": 1,
    "task_name": sys.argv[2],
    "task_slug": sys.argv[3],
    "section_key": sys.argv[4],
    "session_id": sys.argv[5],
    "session_started": sys.argv[6],
    "session_revision": sys.argv[7],
    "created_at_utc": sys.argv[8],
}
temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
temp.write_text(json.dumps(payload, indent=2) + "\n")
os.replace(temp, path)
PY
}

load_legacy_metadata_file() {
  local metadata_path="$1"
  local allowed_csv="$2"
  LEGACY_METADATA=()
  local metadata_line field_name raw_value decoded_value
  while IFS= read -r metadata_line || [[ -n "$metadata_line" ]]; do
    [[ -n "$metadata_line" ]] || continue
    [[ "$metadata_line" == *=* ]] || fail "malformed legacy metadata line in $metadata_path"
    field_name="${metadata_line%%=*}"
    [[ "$field_name" =~ '^[A-Z][A-Z0-9_]*$' ]] || \
      fail "invalid legacy metadata field in $metadata_path"
    case ",$allowed_csv," in
      *",$field_name,"*) ;;
      *) fail "unexpected legacy metadata field '$field_name' in $metadata_path" ;;
    esac
    (( ${+LEGACY_METADATA[$field_name]} == 0 )) || \
      fail "duplicate legacy metadata field '$field_name' in $metadata_path"
    raw_value="${metadata_line#*=}"
    decoded_value="${(Q)raw_value}"
    LEGACY_METADATA[$field_name]="$decoded_value"
  done < "$metadata_path"
}

legacy_metadata_value() {
  local field_name="$1"
  local default_value="${2:-}"
  if (( ${+LEGACY_METADATA[$field_name]} )); then
    printf '%s\n' "${LEGACY_METADATA[$field_name]}"
  else
    printf '%s\n' "$default_value"
  fi
}

validate_loaded_run_metadata() {
  [[ -n "${TASK_NAME:-}" ]] || fail "run metadata is missing task_name"
  [[ -n "${TASK_SLUG:-}" && "$TASK_SLUG" == "$(slugify "$TASK_SLUG")" ]] || \
    fail "run metadata has an invalid task_slug"
  [[ -z "${SECTION_KEY:-}" || "$SECTION_KEY" == "$(slugify "$SECTION_KEY")" ]] || \
    fail "run metadata has an invalid section_key"
  [[ "${SESSION_STARTED:-}" == "0" || "${SESSION_STARTED:-}" == "1" ]] || \
    fail "run metadata has an invalid session_started value"
  [[ "${SESSION_REVISION:-}" == <-> ]] || \
    fail "run metadata has an invalid session_revision"
  [[ -z "${SESSION_ID:-}" || "$SESSION_ID" =~ '^[A-Za-z0-9._:-]+$' ]] || \
    fail "run metadata has an invalid session_id"
  [[ -n "${CREATED_AT_UTC:-}" ]] || fail "run metadata is missing created_at_utc"
}

validate_loaded_pending_metadata() {
  [[ "${PENDING_SCHEMA_VERSION:-}" == "1" || "${PENDING_SCHEMA_VERSION:-}" == "2" ]] || \
    fail "pending metadata has an unsupported version"
  [[ "${KIND:-}" == "step" || "${KIND:-}" == "complete" ]] || \
    fail "pending metadata has an invalid kind"
  [[ -n "${LABEL:-}" ]] || fail "pending metadata is missing its label"
  [[ "${MODE_FLAG:-}" == "start" || "${MODE_FLAG:-}" == "resume" ]] || \
    fail "pending metadata has an invalid mode"
  [[ "${EXPECTED_SESSION_STARTED:-}" == "0" || "${EXPECTED_SESSION_STARTED:-}" == "1" ]] || \
    fail "pending metadata has an invalid expected_session_started value"
  [[ "${EXPECTED_SESSION_REVISION:-}" == <-> ]] || \
    fail "pending metadata has an invalid expected_session_revision"
  [[ -z "${EXPECTED_SESSION_ID:-}" || "$EXPECTED_SESSION_ID" =~ '^[A-Za-z0-9._:-]+$' ]] || \
    fail "pending metadata has an invalid expected_session_id"
}

load_run() {
  local run_dir_input="${1:-}"
  [[ -n "$run_dir_input" ]] || fail "run directory is required"
  if [[ "$run_dir_input" == "current" ]]; then
    run_dir_input="$(resolve_current_run)" || fail "current run pointer is empty: $CURRENT_RUN_FILE"
  fi
  local abs_run_dir
  abs_run_dir="$(cd -P "$run_dir_input" && pwd -P)"
  case "$abs_run_dir" in
    "$RUNS_DIR"/*) ;;
    *) fail "run directory is outside the selected project: $abs_run_dir" ;;
  esac
  SECTION_KEY=""
  SECTION_NAME=""
  SECTION_DIR=""
  TASK_NAME=""
  TASK_SLUG=""
  SESSION_ID=""
  SESSION_STARTED="0"
  SESSION_REVISION="0"
  CREATED_AT_UTC=""
  if [[ -f "$abs_run_dir/meta.json" ]]; then
    local metadata_version
    metadata_version="$(extract_json_field "$abs_run_dir/meta.json" "version")"
    [[ "$metadata_version" == "1" ]] || fail "unsupported run metadata version: $metadata_version"
    TASK_NAME="$(extract_json_field "$abs_run_dir/meta.json" "task_name")"
    TASK_SLUG="$(extract_json_field "$abs_run_dir/meta.json" "task_slug")"
    SECTION_KEY="$(extract_json_field "$abs_run_dir/meta.json" "section_key")"
    SESSION_ID="$(extract_json_field "$abs_run_dir/meta.json" "session_id")"
    SESSION_STARTED="$(extract_json_field "$abs_run_dir/meta.json" "session_started")"
    SESSION_REVISION="$(extract_json_field "$abs_run_dir/meta.json" "session_revision")"
    CREATED_AT_UTC="$(extract_json_field "$abs_run_dir/meta.json" "created_at_utc")"
  elif [[ -f "$abs_run_dir/meta.env" ]]; then
    load_legacy_metadata_file \
      "$abs_run_dir/meta.env" \
      "RUN_DIR,TASK_NAME,TASK_SLUG,SECTION_KEY,SECTION_NAME,SESSION_ID,SESSION_STARTED,SESSION_REVISION,CREATED_AT_UTC"
    TASK_NAME="$(legacy_metadata_value TASK_NAME)"
    TASK_SLUG="$(legacy_metadata_value TASK_SLUG)"
    SECTION_KEY="$(legacy_metadata_value SECTION_KEY)"
    SESSION_ID="$(legacy_metadata_value SESSION_ID)"
    SESSION_STARTED="$(legacy_metadata_value SESSION_STARTED 0)"
    SESSION_REVISION="$(legacy_metadata_value SESSION_REVISION 0)"
    CREATED_AT_UTC="$(legacy_metadata_value CREATED_AT_UTC)"
  else
    fail "missing run metadata in $abs_run_dir"
  fi
  validate_loaded_run_metadata
  RUN_DIR="$abs_run_dir"
  if [[ -n "${SECTION_KEY:-}" ]]; then
    SECTION_DIR="$SECTIONS_DIR/$SECTION_KEY"
    [[ -d "$SECTION_DIR" ]] || fail "missing section workspace after resolving run: $SECTION_DIR"
    if [[ -f "$SECTION_DIR/name.txt" ]]; then
      SECTION_NAME="$(/usr/bin/head -n 1 "$SECTION_DIR/name.txt" | tr -d '\r')"
    fi
  else
    SECTION_DIR=""
  fi
  if [[ -n "${SECTION_OVERRIDE:-}" ]]; then
    local expected_section
    expected_section="$(slugify "$SECTION_OVERRIDE")"
    [[ "${SECTION_KEY:-}" == "$expected_section" ]] || \
      fail "run belongs to section '${SECTION_KEY:-legacy}', not '$expected_section'"
  fi
}

load_pending() {
  local pending_dir_input="${1:-}"
  [[ -n "$pending_dir_input" ]] || fail "pending directory is required"
  local abs_pending_dir
  abs_pending_dir="$(cd -P "$pending_dir_input" && pwd -P)"
  [[ "$(basename "$(dirname "$abs_pending_dir")")" == "pending" ]] || \
    fail "pending directory is not inside a run's pending directory: $abs_pending_dir"
  local inferred_run_dir
  inferred_run_dir="$(cd -P "$abs_pending_dir/../.." && pwd -P)"
  case "$inferred_run_dir" in
    "$RUNS_DIR"/*) ;;
    *) fail "pending review is outside the selected project's runs: $abs_pending_dir" ;;
  esac
  case "$abs_pending_dir" in
    "$inferred_run_dir"/pending/*) ;;
    *) fail "pending directory escapes its inferred run: $abs_pending_dir" ;;
  esac
  PENDING_SCHEMA_VERSION="1"
  EXPECTED_SESSION_ID=""
  EXPECTED_SESSION_STARTED="0"
  EXPECTED_SESSION_REVISION="0"
  KIND=""
  LABEL=""
  MODE_FLAG=""
  local pending_section_key=""
  if [[ -f "$abs_pending_dir/pending.json" ]]; then
    PENDING_SCHEMA_VERSION="$(extract_json_field "$abs_pending_dir/pending.json" "version")"
    KIND="$(extract_json_field "$abs_pending_dir/pending.json" "kind")"
    LABEL="$(extract_json_field "$abs_pending_dir/pending.json" "label")"
    MODE_FLAG="$(extract_json_field "$abs_pending_dir/pending.json" "mode")"
    pending_section_key="$(extract_json_field "$abs_pending_dir/pending.json" "section_key")"
    EXPECTED_SESSION_ID="$(extract_json_field "$abs_pending_dir/pending.json" "expected_session_id")"
    EXPECTED_SESSION_STARTED="$(extract_json_field "$abs_pending_dir/pending.json" "expected_session_started")"
    EXPECTED_SESSION_REVISION="$(extract_json_field "$abs_pending_dir/pending.json" "expected_session_revision")"
  elif [[ -f "$abs_pending_dir/pending.env" ]]; then
    load_legacy_metadata_file \
      "$abs_pending_dir/pending.env" \
      "PENDING_SCHEMA_VERSION,RUN_DIR,KIND,LABEL,MODE_FLAG,SECTION_KEY,EXPECTED_SESSION_ID,EXPECTED_SESSION_STARTED,EXPECTED_SESSION_REVISION"
    PENDING_SCHEMA_VERSION="$(legacy_metadata_value PENDING_SCHEMA_VERSION 1)"
    KIND="$(legacy_metadata_value KIND)"
    LABEL="$(legacy_metadata_value LABEL)"
    MODE_FLAG="$(legacy_metadata_value MODE_FLAG)"
    pending_section_key="$(legacy_metadata_value SECTION_KEY)"
    EXPECTED_SESSION_ID="$(legacy_metadata_value EXPECTED_SESSION_ID)"
    EXPECTED_SESSION_STARTED="$(legacy_metadata_value EXPECTED_SESSION_STARTED 0)"
    EXPECTED_SESSION_REVISION="$(legacy_metadata_value EXPECTED_SESSION_REVISION 0)"
  else
    fail "missing pending metadata in $abs_pending_dir"
  fi
  validate_loaded_pending_metadata
  PENDING_DIR="$abs_pending_dir"
  load_run "$inferred_run_dir"
  [[ "$pending_section_key" == "${SECTION_KEY:-}" ]] || \
    fail "pending review section does not match its run"
}

assert_pending_session_current() {
  local expected_id="${EXPECTED_SESSION_ID:-}"
  local expected_started="${EXPECTED_SESSION_STARTED:-0}"
  local expected_revision="${EXPECTED_SESSION_REVISION:-0}"
  if [[ "$expected_id" != "${SESSION_ID:-}" || \
        "$expected_started" != "${SESSION_STARTED:-0}" || \
        "$expected_revision" != "${SESSION_REVISION:-0}" ]]; then
    fail "stale pending review: the PM session changed after this review was prepared; prepare it again"
  fi
}

assert_current_pending_schema() {
  [[ "${PENDING_SCHEMA_VERSION:-1}" == "2" ]] || \
    fail "legacy pending review must be migrated first: run adopt-pending '$PENDING_DIR'"
}

# Locking uses fcntl through zsh/system. The lock is held by an open descriptor
# and the kernel releases it when the process dies, so there is no staleness
# heuristic to get wrong. The previous PID-file scheme could be acquired by two
# processes at once: both could observe the same dead owner, both remove it, and
# the loser would then delete the winner's live owner file.
LOCK_WAIT_SECONDS="${PM_FLOW_LOCK_WAIT:-60}"

acquire_lock() {
  local lock_file="$1"
  local fd_var="$2"
  local wait_seconds="${3:-$LOCK_WAIT_SECONDS}"
  zmodload zsh/system 2>/dev/null || fail "the zsh/system module is required for safe locking"
  mkdir -p "$(dirname "$lock_file")"
  [[ -e "$lock_file" ]] || : >> "$lock_file"
  if ! zsystem flock -t "$wait_seconds" -f "$fd_var" "$lock_file"; then
    fail "timed out after ${wait_seconds}s waiting for $(basename "$lock_file")"
  fi
}

release_lock() {
  local fd_var="$1"
  local fd="${(P)fd_var:-}"
  [[ -n "$fd" ]] || return 0
  zsystem flock -u "$fd" 2>/dev/null || true
  unset "$fd_var"
}

release_record_lock() {
  release_lock RUN_RECORD_LOCK
}

acquire_record_lock() {
  acquire_lock "$RUN_DIR/.record.lock" RUN_RECORD_LOCK
  trap release_record_lock EXIT HUP INT TERM
}

release_section_create_lock() {
  release_lock SECTION_CREATE_LOCK
}

acquire_section_create_lock() {
  mkdir -p "$SECTIONS_DIR"
  acquire_lock "$SECTIONS_DIR/.create.lock" SECTION_CREATE_LOCK
  trap 'release_section_create_lock; release_record_lock' EXIT HUP INT TERM
}

active_pending_dir() {
  printf '%s\n' "$RUN_DIR/.active-pending"
}

assert_no_active_pending() {
  local active_dir
  active_dir="$(active_pending_dir)"
  if [[ -d "$active_dir" ]]; then
    if [[ ! -f "$active_dir/path.txt" ]]; then
      if rmdir "$active_dir" 2>/dev/null; then
        return 0
      fi
      fail "section has an incomplete active-pending claim that could not be recovered"
    fi
    local active_path="unknown"
    active_path="$(/usr/bin/head -n 1 "$active_dir/path.txt" | tr -d '\r')"
    fail "section already has an active pending review: $active_path; record it or use cancel-pending"
  fi
}

claim_active_pending() {
  local pending_dir="$1"
  local active_dir
  active_dir="$(active_pending_dir)"
  if ! mkdir "$active_dir" 2>/dev/null; then
    assert_no_active_pending
    fail "could not claim the section's active pending slot"
  fi
  printf '%s\n' "$(repo_relative_path "$pending_dir")" > "$active_dir/path.txt"
}

assert_active_pending() {
  local active_dir expected_path actual_path
  active_dir="$(active_pending_dir)"
  [[ -f "$active_dir/path.txt" ]] || fail "pending review is not the active review for this section"
  expected_path="$(/usr/bin/head -n 1 "$active_dir/path.txt" | tr -d '\r')"
  actual_path="$(repo_relative_path "$PENDING_DIR")"
  [[ "$expected_path" == "$actual_path" ]] || \
    fail "pending review is not active; active review is $expected_path"
}

release_active_pending() {
  local active_dir
  active_dir="$(active_pending_dir)"
  if [[ -d "$active_dir" ]]; then
    rm -f "$active_dir/path.txt"
    rmdir "$active_dir" 2>/dev/null || true
  fi
}

assert_execution_claimed() {
  [[ -d "$PENDING_DIR/.execution-claimed" ]] || \
    fail "pending review has not claimed execution; run its generated command or claim-execution first"
}

assert_section_open_for_work() {
  [[ -n "${SECTION_DIR:-}" ]] || return 0
  local section_lifecycle_status="active"
  if [[ -f "$SECTION_DIR/status.txt" ]]; then
    section_lifecycle_status="$(/usr/bin/head -n 1 "$SECTION_DIR/status.txt" | tr -d '\r')"
  fi
  case "$section_lifecycle_status" in
    done|cancelled)
      fail "section is $section_lifecycle_status; publish an active or planned handoff before preparing more PM work"
      ;;
  esac
}

# Cheap pre-flight so a rejected prepare fails before writing a pending
# directory. activate_prepared_pending still re-checks under the record lock,
# which is what actually makes the decision safe.
assert_ready_to_prepare() {
  assert_section_open_for_work
  assert_no_active_pending
}

activate_prepared_pending() {
  local pending_dir="$1"
  local run_dir_before_lock="$RUN_DIR"
  acquire_record_lock
  load_run "$run_dir_before_lock"
  assert_section_open_for_work
  assert_pending_session_current
  assert_no_active_pending
  claim_active_pending "$pending_dir"
  release_record_lock
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
    if [[ -n "${SECTION_KEY:-}" ]]; then
      printf -- '- section: %s\n' "$SECTION_KEY"
    fi
    printf -- '- session_id: %s\n' "$SESSION_ID"
    printf '\n### Codex Update\n\n%s\n\n' "$engineer_body"
    printf '### Claude Response\n\n%s\n\n' "$claude_response"
  } >> "$transcript_path"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "content missing required marker: $needle"
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  local label="$3"
  printf '%s\n' "$haystack" | python3 -c 'import re, sys; sys.exit(0 if re.search(sys.argv[1], sys.stdin.read(), re.MULTILINE) else 1)' "$pattern" || fail "content missing valid $label"
}

validate_step_response() {
  local response="$1"
  assert_contains "$response" "Assessment"
  assert_matches "$response" '(?i)drift review' "drift review section"
  assert_contains "$response" "Risks"
  assert_contains "$response" "Improvements"
  assert_contains "$response" "Decision"
  assert_contains "$response" "Next action"
  extract_markdown_decision "$response" "GO,GO_WITH_CHANGES,NO_GO" >/dev/null
}

validate_completion_response() {
  local response="$1"
  assert_contains "$response" "Outcome assessment"
  assert_matches "$response" '(?i)drift review' "drift review section"
  assert_contains "$response" "Expected vs observed"
  assert_contains "$response" "Feedback"
  assert_contains "$response" "Recommended next steps"
  assert_contains "$response" "Decision"
  extract_markdown_decision "$response" "DONE,FOLLOW_UP,REWORK" >/dev/null
}

extract_markdown_decision() {
  local response="$1"
  local allowed_csv="$2"
  printf '%s\n' "$response" | python3 -c '
import re
import sys

allowed = set(sys.argv[1].split(","))
lines = sys.stdin.read().splitlines()
inside = False
values = []
for line in lines:
    heading = re.match(r"^#{0,6}\s*Decision\s*:?\s*$", line, re.IGNORECASE)
    if heading:
        if inside:
            raise SystemExit("response contains more than one Decision section")
        inside = True
        continue
    if inside and re.match(r"^#{1,6}\s+", line):
        break
    if inside and line.strip():
        value = re.sub(r"^\s*[-*]\s+", "", line).strip()
        value = value.strip("*_` ")
        values.append(value)
if not inside or not values:
    raise SystemExit("response Decision section is empty")
# The decision line must lead with the verdict token. A trailing justification
# on the same line is accepted so a well-formed review is not discarded after
# the PM call has already been spent.
token = re.match(r"^([A-Z][A-Z_]*)\b", values[0])
decision = token.group(1) if token else values[0]
if decision not in allowed:
    raise SystemExit(
        f"response Decision must begin with one of {sorted(allowed)}, got {values[0]!r}"
    )
print(decision)
' "$allowed_csv" || fail "content missing valid decision"
}

validate_section_brief() {
  local brief="$1"
  assert_matches "$brief" '(?im)^#{1,6}\s+Objective\s*$' "section Objective heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Scope\s*$' "section Scope heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Owned paths\s*$' "section Owned paths heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Dependencies\s*$' "section Dependencies heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Acceptance\s*$' "section Acceptance heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Rejection conditions\s*$' "section Rejection conditions heading"
}

extract_owned_paths() {
  local brief="$1"
  printf '%s\n' "$brief" | python3 -c '
import re
import sys

inside = False
paths = []
for line in sys.stdin.read().splitlines():
    heading = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
    if heading:
        inside = heading.group(1).strip().lower() == "owned paths"
        continue
    if inside:
        bullet = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
        if bullet:
            value = bullet.group(1).strip()
            ticked = re.search(r"`([^`]+)`", value)
            paths.append((ticked.group(1) if ticked else value).strip())
if not paths:
    raise SystemExit("Owned paths must contain at least one bullet")
print("\n".join(paths))
'
}

extract_dependency_handoffs() {
  local brief="$1"
  local section_key="$2"
  printf '%s\n' "$brief" | python3 -c '
from pathlib import Path
import os
import re
import sys

project_root = Path(sys.argv[1]).resolve()
sections_dir = Path(sys.argv[2]).resolve()
section_key = sys.argv[3]
inside = False
found_bullet = False
handoffs = []

def slugify(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return re.sub(r"-+", "-", value) or "section"

for line in sys.stdin.read().splitlines():
    heading = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
    if heading:
        inside = heading.group(1).strip().lower() == "dependencies"
        continue
    if not inside:
        continue
    bullet = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
    if not bullet:
        continue
    found_bullet = True
    value = bullet.group(1).strip()
    ticked = re.fullmatch(r"`([^`]+)`", value)
    if ticked:
        value = ticked.group(1).strip()
    if value.lower().rstrip(".") in {"none", "no dependencies"}:
        continue
    if "/" in value:
        candidate = (project_root / value).resolve()
        if candidate.name != "handoff.md" or candidate.parent.parent != sections_dir:
            raise SystemExit(
                "dependency paths must name a section handoff.md under this pm-flow project"
            )
        dependency_key = candidate.parent.name
    else:
        if value != slugify(value):
            raise SystemExit(
                f"dependency must be an exact section key or handoff path, got: {value}"
            )
        dependency_key = value
        candidate = sections_dir / dependency_key / "handoff.md"
    if dependency_key == section_key:
        raise SystemExit("a section cannot depend on its own handoff")
    if not candidate.is_file():
        raise SystemExit(f"dependency section handoff does not exist: {candidate}")
    relative = os.path.relpath(candidate, project_root)
    if relative not in handoffs:
        handoffs.append(relative)

if not found_bullet:
    raise SystemExit("Dependencies must contain at least one bullet (use `- None.` when empty)")
print("\n".join(handoffs))
' "$PROJECT_ROOT" "$SECTIONS_DIR" "$section_key"
}

assert_no_owned_path_overlap() {
  local section_key="$1"
  local owned_paths="$2"
  local conflict
  conflict="$(python3 - "$SECTIONS_DIR" "$section_key" "$owned_paths" <<'PY'
from pathlib import Path, PurePosixPath
import re
import sys

sections_dir = Path(sys.argv[1])
new_key = sys.argv[2]
new_entries = [line.strip() for line in sys.argv[3].splitlines() if line.strip()]

def normalized_prefix(entry: str) -> str:
    entry = entry.strip().strip("`").replace("\\", "/")
    if entry.startswith("/") or ".." in PurePosixPath(entry).parts:
        raise SystemExit(f"owned path must be repo-relative and must not contain '..': {entry}")
    wildcard = re.search(r"[*?{\[]", entry)
    prefix = entry
    if wildcard:
        prefix = entry[:wildcard.start()]
        if prefix and not prefix.endswith("/"):
            prefix = prefix.rsplit("/", 1)[0] if "/" in prefix else "."
    prefix = prefix.rstrip("/")
    return prefix or "."

def overlaps(left: str, right: str) -> bool:
    left_prefix = normalized_prefix(left)
    right_prefix = normalized_prefix(right)
    if "." in (left_prefix, right_prefix):
        return True
    return (
        left_prefix == right_prefix
        or left_prefix.startswith(right_prefix + "/")
        or right_prefix.startswith(left_prefix + "/")
    )

for new_entry in new_entries:
    normalized_prefix(new_entry)

for section_dir in sorted(p for p in sections_dir.iterdir() if p.is_dir() and not p.name.startswith(".")):
    if section_dir.name == new_key:
        continue
    status_path = section_dir / "status.txt"
    status = status_path.read_text().strip() if status_path.is_file() else "active"
    if status in {"done", "cancelled"}:
        continue
    owned_path = section_dir / "owned_paths.txt"
    if not owned_path.is_file():
        continue
    for existing in owned_path.read_text().splitlines():
        existing = existing.strip()
        if not existing:
            continue
        for new_entry in new_entries:
            if overlaps(existing, new_entry):
                print(f"{section_dir.name}: {existing} overlaps {new_entry}")
                raise SystemExit(0)
PY
)"
  [[ -z "$conflict" ]] || fail "section owned paths overlap active section $conflict"
}

validate_handoff() {
  local handoff="$1"
  local word_count byte_count
  word_count="$(printf '%s\n' "$handoff" | wc -w | tr -d '[:space:]')"
  byte_count="$(printf '%s\n' "$handoff" | LC_ALL=C wc -c | tr -d '[:space:]')"
  [[ "$word_count" -le 500 ]] || fail "section handoff exceeds the 500-word context budget ($word_count words)"
  [[ "$byte_count" -le 8192 ]] || fail "section handoff exceeds the 8192-byte context budget ($byte_count bytes)"
  assert_matches "$handoff" '(?im)^#{1,6}\s+Outcome\s*$' "handoff Outcome heading"
  assert_matches "$handoff" '(?im)^#{1,6}\s+Decisions\s*$' "handoff Decisions heading"
  assert_matches "$handoff" '(?im)^#{1,6}\s+Interfaces\s*$' "handoff Interfaces heading"
  assert_matches "$handoff" '(?im)^#{1,6}\s+Risks\s*$' "handoff Risks heading"
  assert_matches "$handoff" '(?im)^#{1,6}\s+Next action\s*$' "handoff Next action heading"
}

write_completion_marker() {
  local decision="$1"
  local pending_dir="$2"
  local marker_path="$RUN_DIR/completion.env"
  local marker_tmp="$RUN_DIR/.completion.env.$$.tmp"
  {
    printf 'decision=%s\n' "$decision"
    printf 'session_revision=%s\n' "${SESSION_REVISION:-0}"
    printf 'recorded_at_utc=%s\n' "$(now_iso_utc)"
    printf 'pending_path=%s\n' "$(repo_relative_path "$pending_dir")"
  } > "$marker_tmp"
  mv "$marker_tmp" "$marker_path"
}

assert_current_done_completion() {
  local marker_path="$RUN_DIR/completion.env"
  [[ -f "$marker_path" ]] || \
    fail "section cannot be marked done without a recorded PM completion review"
  local completion_decision completion_revision
  completion_decision="$(awk -F= '$1 == "decision" {print substr($0, index($0, "=") + 1); exit}' "$marker_path")"
  completion_revision="$(awk -F= '$1 == "session_revision" {print substr($0, index($0, "=") + 1); exit}' "$marker_path")"
  [[ "$completion_decision" == "DONE" ]] || \
    fail "section cannot be marked done; latest PM completion decision is ${completion_decision:-missing}"
  [[ "$completion_revision" == "${SESSION_REVISION:-0}" ]] || \
    fail "section cannot be marked done; PM activity occurred after the DONE completion review"
}

update_session_from_response() {
  local response_path="$1"
  local response_session_id response_resumable response_backend
  response_session_id="$(extract_json_field "$response_path" "session_id")"
  response_resumable="$(extract_json_field "$response_path" "session_resumable")"
  response_backend="$(extract_json_field "$response_path" "pm_backend")"

  if [[ "$response_resumable" == "False" || "$response_resumable" == "false" || \
        "$response_backend" == "codex" || "$response_session_id" == codex-fallback-* ]]; then
    SESSION_ID=""
    SESSION_STARTED="0"
    return
  fi

  if [[ -n "$response_session_id" ]]; then
    SESSION_ID="$response_session_id"
    SESSION_STARTED="1"
  else
    SESSION_ID=""
    SESSION_STARTED="0"
  fi
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
  local prompt_path="$pending_dir/prompt.md"
  local system_prompt_path="$pending_dir/system_prompt.txt"
  local response_path="$pending_dir/response.json"
  local net_exec_path="./agentic/pm_flow/net_exec.sh"
  local pm_flow_path="./agentic/pm_flow/pm_flow.sh"
  # The prompt is passed by command substitution rather than inlined, so the
  # PM receives the structured multi-line prompt exactly as written in
  # prompt.md instead of a flattened single line.
  {
    printf '%q --project %q claim-execution %q && ' "$pm_flow_path" "$PROJECT_KEY" "$pending_dir"
    printf '%q claude -p --output-format json ' "$net_exec_path"
    printf -- '--add-dir %q ' "$PROJECT_ROOT"
    if [[ "$mode_flag" == "resume" && -n "${SESSION_ID:-}" ]]; then
      printf -- '--resume %q ' "$SESSION_ID"
    fi
    printf -- '--append-system-prompt-file %q -- ' "$system_prompt_path"
    printf -- '"$(/bin/cat %q)" > %q\n' "$prompt_path" "$response_path"
  } > "$command_path"
}

prepare_pending_dir() {
  local kind_slug="$1"
  local label="$2"
  local pending_dir
  pending_dir="$RUN_DIR/pending/$(now_compact_utc)-${kind_slug}-$(slugify "$label")-$(lower_uuid | cut -c1-8)"
  mkdir -p "$pending_dir"
  printf '%s\n' "$pending_dir"
}

record_pending_meta() {
  local pending_dir="$1"
  local kind="$2"
  local label="$3"
  local mode_flag="$4"
  EXPECTED_SESSION_ID="${SESSION_ID:-}"
  EXPECTED_SESSION_STARTED="${SESSION_STARTED:-0}"
  EXPECTED_SESSION_REVISION="${SESSION_REVISION:-0}"
  PENDING_SCHEMA_VERSION="2"
  python3 - \
    "$pending_dir/pending.json" \
    "$kind" \
    "$label" \
    "$mode_flag" \
    "${SECTION_KEY:-}" \
    "$EXPECTED_SESSION_ID" \
    "$EXPECTED_SESSION_STARTED" \
    "$EXPECTED_SESSION_REVISION" <<'PY'
from pathlib import Path
import json
import os
import sys

path = Path(sys.argv[1])
payload = {
    "version": 2,
    "kind": sys.argv[2],
    "label": sys.argv[3],
    "mode": sys.argv[4],
    "section_key": sys.argv[5],
    "expected_session_id": sys.argv[6],
    "expected_session_started": sys.argv[7],
    "expected_session_revision": sys.argv[8],
}
temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
temp.write_text(json.dumps(payload, indent=2) + "\n")
os.replace(temp, path)
PY
}

write_context_manifest() {
  local pending_dir="$1"
  shift
  python3 - "$pending_dir/context_files.json" "$PROJECT_ROOT" "$@" <<'PY'
from pathlib import Path
import json
import os
import sys

manifest_path = Path(sys.argv[1])
project_root = Path(sys.argv[2]).resolve()
files = []
for raw_path in sys.argv[3:]:
    path = Path(raw_path).resolve()
    try:
        path.relative_to(project_root)
    except ValueError:
        raise SystemExit(f"context file escapes the project root: {path}")
    if not path.is_file():
        raise SystemExit(f"context file does not exist: {path}")
    value = os.path.relpath(path, project_root)
    if value not in files:
        files.append(value)

payload = {
    "version": 1,
    "files": files,
}
manifest_path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

write_review_context_manifest() {
  local pending_dir="$1"
  local context_files=(
    "$RUN_DIR/task_brief.md"
    "$CONTRACT_FILE"
    "$pending_dir/engineer_update.md"
  )
  if [[ -n "${SECTION_KEY:-}" ]]; then
    context_files+=(
      "$SECTION_DIR/brief.md"
      "$SECTION_DIR/state.md"
      "$SECTION_DIR/handoff.md"
    )
    local dependency_rel
    if [[ -f "$pending_dir/dependency_snapshots.txt" ]]; then
      while IFS= read -r dependency_rel; do
        [[ -n "$dependency_rel" ]] || continue
        context_files+=("$PROJECT_ROOT/$dependency_rel")
      done < "$pending_dir/dependency_snapshots.txt"
    fi
  fi
  write_context_manifest "$pending_dir" "${context_files[@]}"
}

dependency_prompt_lines() {
  local pending_dir="$1"
  [[ -f "$pending_dir/dependency_snapshots.txt" ]] || return 0
  local dependency_rel
  while IFS= read -r dependency_rel; do
    [[ -n "$dependency_rel" ]] || continue
    printf -- '- %s\n' "$PROJECT_ROOT/$dependency_rel"
  done < "$pending_dir/dependency_snapshots.txt"
}

snapshot_dependency_handoffs() {
  local pending_dir="$1"
  local snapshot_dir="$pending_dir/dependencies"
  local snapshots_file="$pending_dir/dependency_snapshots.txt"
  mkdir -p "$snapshot_dir"
  : > "$snapshots_file"
  [[ -n "${SECTION_DIR:-}" && -f "$SECTION_DIR/dependency_handoffs.txt" ]] || return 0
  local dependency_rel dependency_key snapshot_path
  while IFS= read -r dependency_rel; do
    [[ -n "$dependency_rel" ]] || continue
    dependency_key="$(basename "$(dirname "$dependency_rel")")"
    snapshot_path="$snapshot_dir/${dependency_key}-handoff.md"
    /bin/cp "$PROJECT_ROOT/$dependency_rel" "$snapshot_path"
    printf '%s\n' "$(repo_relative_path "$snapshot_path")" >> "$snapshots_file"
  done < "$SECTION_DIR/dependency_handoffs.txt"
}

cmd_validate() {
  require_command claude
  require_command uuidgen
  require_command python3
  printf 'claude_path=%s\n' "$(command -v claude)"
  claude --version
}

create_run() {
  local task_name="$1"
  local task_brief="$2"
  local update_project_pointer="${3:-0}"
  mkdir -p "$RUNS_DIR"

  local created_at task_slug run_dir run_suffix
  created_at="$(now_compact_utc)"
  task_slug="$(slugify "$task_name")"
  run_suffix="$(lower_uuid | cut -c1-8)"
  run_dir="$RUNS_DIR/${created_at}-${task_slug}-${run_suffix}"
  if ! mkdir "$run_dir" 2>/dev/null; then
    fail "could not create an exclusive PM run directory: $run_dir"
  fi
  mkdir "$run_dir/pending"

  RUN_DIR="$run_dir"
  TASK_NAME="$task_name"
  TASK_SLUG="$task_slug"
  SESSION_ID=""
  SESSION_STARTED="0"
  SESSION_REVISION="0"
  CREATED_AT_UTC="$(now_iso_utc)"

  printf '%s\n' "$task_brief" > "$RUN_DIR/task_brief.md"
  persist_meta "$RUN_DIR/meta.json"

  local contract_body
  contract_body="$(read_contract)"
  {
    if [[ -n "${SECTION_KEY:-}" ]]; then
      printf '# Section PM Flow Transcript\n\n'
      printf -- '- section_name: %s\n' "$SECTION_NAME"
      printf -- '- section_key: %s\n' "$SECTION_KEY"
    else
      printf '# Claude PM Flow Transcript\n\n'
    fi
    printf -- '- task_name: %s\n' "$TASK_NAME"
    printf -- '- task_slug: %s\n' "$TASK_SLUG"
    printf -- '- created_at_utc: %s\n' "$CREATED_AT_UTC"
    printf -- '- session_id: %s\n' "$SESSION_ID"
    if [[ -n "${SECTION_KEY:-}" ]]; then
      printf -- '- rule: this section owns one isolated PM session and every developer assignment uses a fresh sub-agent\n'
    else
      printf -- '- rule: this legacy run owns a fresh Claude session and does not reuse unrelated conversations\n'
    fi
    printf '\n## Task Brief\n\n%s\n\n' "$task_brief"
    printf '## Task Contract\n\n%s\n\n' "$contract_body"
  } > "$RUN_DIR/transcript.md"

  if [[ "$update_project_pointer" == "1" ]]; then
    write_current_run_file "$RUN_DIR"
  fi
}

cmd_init() {
  local task_name="${1:-}"
  [[ -n "$task_name" ]] || fail "init requires a task name"
  [[ -z "${SECTION_OVERRIDE:-}" ]] || fail "use init-section to create a section-scoped PM run"

  local task_brief
  task_brief="$(read_stdin_body)"
  SECTION_KEY=""
  SECTION_NAME=""
  SECTION_DIR=""
  create_run "$task_name" "$task_brief" "1"

  printf '%s\n' "$RUN_DIR"
}

cmd_init_section() {
  local section_name="${1:-}"
  [[ -n "$section_name" ]] || fail "init-section requires a section name"
  local body_mode="stdin"
  local body_path=""
  if [[ "${2:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown init-section argument: ${2:-}"
  fi

  local section_brief owned_paths dependency_handoffs
  section_brief="$(read_body_arg "$body_mode" "$body_path")"
  [[ -n "$section_brief" ]] || fail "section brief must not be empty"
  [[ -f "$CONTRACT_FILE" ]] || fail "missing task contract: $CONTRACT_FILE"
  validate_section_brief "$section_brief"
  owned_paths="$(extract_owned_paths "$section_brief")"

  SECTION_NAME="$section_name"
  SECTION_KEY="$(slugify "$section_name")"
  local final_section_dir="$SECTIONS_DIR/$SECTION_KEY"
  local staged_section_dir="$SECTIONS_DIR/.creating-${SECTION_KEY}-$(lower_uuid | cut -c1-8)"
  mkdir -p "$SECTIONS_DIR"
  acquire_section_create_lock
  if [[ -e "$final_section_dir" ]]; then
    fail "section already exists: $SECTION_KEY"
  fi
  assert_no_owned_path_overlap "$SECTION_KEY" "$owned_paths"
  dependency_handoffs="$(extract_dependency_handoffs "$section_brief" "$SECTION_KEY")"
  mkdir "$staged_section_dir"
  SECTION_DIR="$staged_section_dir"

  printf '%s\n' "$SECTION_NAME" > "$SECTION_DIR/name.txt"
  printf '%s\n' "$owned_paths" > "$SECTION_DIR/owned_paths.txt"
  printf '%s\n' "$dependency_handoffs" > "$SECTION_DIR/dependency_handoffs.txt"
  printf 'planned\n' > "$SECTION_DIR/status.txt"
  printf 'Section created; its PM sub-agent has not been launched yet.\n' > "$SECTION_DIR/summary.txt"
  printf '%s\n' "$(now_iso_utc)" > "$SECTION_DIR/updated_at.txt"
  printf '%s\n' "$section_brief" > "$SECTION_DIR/brief.md"
  {
    printf '# %s section PM state\n\n' "$SECTION_NAME"
    printf '## Objective\n\n- Derive the current objective from `brief.md`.\n\n'
    printf '## Owned paths\n\n- Record the files or components this section owns before delegating work.\n\n'
    printf '## Plan\n\n- Break the section into bounded developer assignments.\n\n'
    printf '## Decisions and evidence\n\n- Keep detailed local decisions and validation evidence here, not in the root context.\n\n'
    printf '## Current assignment\n\n- None yet.\n\n'
    printf '## Dependencies\n\n- Read only dependency handoffs explicitly required by `brief.md`.\n'
  } > "$SECTION_DIR/state.md"
  {
    printf '# %s section handoff\n\n' "$SECTION_NAME"
    printf '## Outcome\n\n- Section initialized; no implementation outcome yet.\n\n'
    printf '## Decisions\n\n- None yet.\n\n'
    printf '## Interfaces\n\n- None identified yet.\n\n'
    printf '## Risks\n\n- No implementation evidence exists yet.\n\n'
    printf '## Next action\n\n- Launch the section PM with `pm_prompt.md`.\n'
  } > "$SECTION_DIR/handoff.md"

  create_run "$SECTION_NAME" "$section_brief" "0"
  printf '%s\n' "$(repo_relative_path "$RUN_DIR")" > "$SECTION_DIR/run_path.txt"
  write_section_pm_prompt \
    "$SECTION_DIR" \
    "$SECTION_NAME" \
    "$SECTION_KEY" \
    "$RUN_DIR" \
    "$final_section_dir"
  mv "$staged_section_dir" "$final_section_dir"
  SECTION_DIR="$final_section_dir"
  refresh_sections_index
  release_section_create_lock

  printf 'section_key=%s\n' "$SECTION_KEY"
  printf 'section_dir=%s\n' "$SECTION_DIR"
  printf 'run_dir=%s\n' "$RUN_DIR"
  printf 'pm_prompt=%s\n' "$SECTION_DIR/pm_prompt.md"
  printf 'handoff=%s\n' "$SECTION_DIR/handoff.md"
}

cmd_list_sections() {
  refresh_sections_index
  /bin/cat "$SECTIONS_INDEX_FILE"
}

cmd_section_prompt() {
  local section_dir
  section_dir="$(resolve_section_dir "${1:-}")"
  [[ -f "$section_dir/pm_prompt.md" ]] || fail "missing section PM prompt: $section_dir/pm_prompt.md"
  /bin/cat "$section_dir/pm_prompt.md"
}

cmd_section_run() {
  local run_dir
  run_dir="$(resolve_section_run "${1:-}")" || fail "section run pointer is empty"
  printf '%s\n' "$run_dir"
}

cmd_section_handoff() {
  local section_input="${1:-}"
  local section_status="${2:-}"
  local summary="${3:-}"
  [[ -n "$section_input" ]] || fail "section-handoff requires a section name"
  [[ -n "$section_status" ]] || fail "section-handoff requires a status"
  [[ -n "$summary" ]] || fail "section-handoff requires a one-line summary"
  case "$section_status" in
    planned|active|blocked|done|cancelled) ;;
    *) fail "invalid section status: $section_status" ;;
  esac
  [[ "$summary" != *$'\n'* ]] || fail "section summary must be one line"
  [[ "${#summary}" -le 200 ]] || fail "section summary exceeds 200 characters"

  local body_mode="stdin"
  local body_path=""
  if [[ "${4:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${5:-}"
  elif [[ -n "${4:-}" ]]; then
    fail "unknown section-handoff argument: ${4:-}"
  fi

  local handoff_body section_dir handoff_tmp handoff_lock_held="0" ownership_lock_held="0"
  handoff_body="$(read_body_arg "$body_mode" "$body_path")"
  validate_handoff "$handoff_body"
  section_dir="$(resolve_section_dir "$section_input")"
  local section_run_dir
  section_run_dir="$(resolve_section_run "$section_input")"
  load_run "$section_run_dir"
  acquire_record_lock
  load_run "$section_run_dir"
  handoff_lock_held="1"
  local previous_section_status="active"
  if [[ -f "$SECTION_DIR/status.txt" ]]; then
    previous_section_status="$(/usr/bin/head -n 1 "$SECTION_DIR/status.txt" | tr -d '\r')"
  fi
  if [[ "$previous_section_status" == "done" || "$previous_section_status" == "cancelled" ]]; then
    case "$section_status" in
      planned|active|blocked)
        [[ -f "$SECTION_DIR/owned_paths.txt" ]] || \
          fail "terminal section cannot reopen without persisted owned_paths.txt"
        acquire_section_create_lock
        ownership_lock_held="1"
        assert_no_owned_path_overlap \
          "$SECTION_KEY" \
          "$(/bin/cat "$SECTION_DIR/owned_paths.txt")"
        ;;
    esac
  fi
  if [[ "$section_status" == "done" || "$section_status" == "cancelled" ]]; then
    assert_no_active_pending
  fi
  if [[ "$section_status" == "done" ]]; then
    assert_current_done_completion
  fi
  section_dir="$SECTION_DIR"
  handoff_tmp="$section_dir/.handoff.$$.tmp"
  printf '%s\n' "$handoff_body" > "$handoff_tmp"
  commit_section_handoff_files \
    "$section_dir" \
    "$handoff_tmp" \
    "$section_status" \
    "$summary" \
    "$(now_iso_utc)"
  refresh_sections_index
  if [[ "$ownership_lock_held" == "1" ]]; then
    release_section_create_lock
  fi
  if [[ "$handoff_lock_held" == "1" ]]; then
    release_record_lock
  fi

  printf 'recorded=section-handoff\n'
  printf 'section=%s\n' "$(slugify "$section_input")"
  printf 'status=%s\n' "$section_status"
  printf 'handoff=%s\n' "$section_dir/handoff.md"
}

cmd_adopt_pending() {
  local pending_dir_input="${1:-}"
  load_pending "$pending_dir_input"
  [[ "${PENDING_SCHEMA_VERSION:-1}" == "1" ]] || \
    fail "pending review already uses the current lifecycle schema"
  acquire_record_lock
  load_pending "$pending_dir_input"
  assert_no_active_pending
  [[ ! -d "$PENDING_DIR/.execution-claimed" ]] || \
    fail "legacy pending review has an unexpected execution claim"

  local legacy_resume_id=""
  if [[ "${MODE_FLAG:-start}" == "resume" ]]; then
    legacy_resume_id="$(python3 - "$PENDING_DIR/command.txt" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(r"(?:^|\s)--resume\s+([A-Za-z0-9._:-]+)", text)
print(match.group(1) if match else "")
PY
)"
    [[ -n "$legacy_resume_id" ]] || \
      fail "could not recover the legacy pending review's expected session id"
    [[ "${SESSION_STARTED:-0}" == "1" && "$legacy_resume_id" == "${SESSION_ID:-}" ]] || \
      fail "legacy pending review is stale; its resume session is no longer current"
  elif [[ "${MODE_FLAG:-start}" == "start" ]]; then
    [[ "${SESSION_STARTED:-0}" == "0" && -z "${SESSION_ID:-}" ]] || \
      fail "legacy pending review is stale; the run has since started a PM session"
  else
    fail "legacy pending review has an invalid mode: ${MODE_FLAG:-missing}"
  fi
  case "${KIND:-}" in
    step|complete) ;;
    *) fail "legacy pending review has an invalid kind: ${KIND:-missing}" ;;
  esac

  local response_result=""
  local response_ready="0"
  if [[ -s "$PENDING_DIR/response.json" ]]; then
    if ! response_result="$(extract_json_field "$PENDING_DIR/response.json" "result" 2>/dev/null)"; then
      fail "legacy response.json is not valid JSON"
    fi
    if [[ -n "$response_result" ]]; then
      response_ready="1"
    fi
  fi

  record_pending_meta "$PENDING_DIR" "$KIND" "$LABEL" "$(session_mode_flag)"
  if [[ "$response_ready" == "0" ]]; then
    write_command_file "$PENDING_DIR/command.txt" "$PENDING_DIR" "$(session_mode_flag)"
  fi
  {
    printf 'adopted_at_utc=%s\n' "$(now_iso_utc)"
    printf 'response_already_executed=%s\n' "$response_ready"
  } > "$PENDING_DIR/legacy-adoption.txt"
  if [[ "$response_ready" == "1" ]]; then
    mkdir "$PENDING_DIR/.execution-claimed"
    {
      printf 'claimed_at_utc=%s\n' "$(now_iso_utc)"
      printf 'claimant_pid=%s\n' "$$"
      printf 'session_revision=%s\n' "${SESSION_REVISION:-0}"
      printf 'source=legacy-adoption\n'
    } > "$PENDING_DIR/.execution-claimed/claim.txt"
  fi
  claim_active_pending "$PENDING_DIR"
  release_record_lock

  printf 'adopted=pending\n'
  printf 'pending_dir=%s\n' "$PENDING_DIR"
  printf 'response_already_executed=%s\n' "$response_ready"
}

cmd_claim_execution() {
  local pending_dir_input="${1:-}"
  load_pending "$pending_dir_input"
  assert_current_pending_schema
  acquire_record_lock
  assert_active_pending
  assert_pending_session_current
  local claim_dir="$PENDING_DIR/.execution-claimed"
  if ! mkdir "$claim_dir" 2>/dev/null; then
    fail "pending review execution was already claimed; refusing a duplicate PM call"
  fi
  {
    printf 'claimed_at_utc=%s\n' "$(now_iso_utc)"
    printf 'claimant_pid=%s\n' "$$"
    printf 'session_revision=%s\n' "${SESSION_REVISION:-0}"
  } > "$claim_dir/claim.txt"
  release_record_lock
  printf 'claimed=execution\n'
  printf 'pending_dir=%s\n' "$PENDING_DIR"
}

cmd_cancel_pending() {
  local pending_dir_input="${1:-}"
  local reason="${2:-cancelled before completion}"
  load_pending "$pending_dir_input"
  assert_current_pending_schema
  acquire_record_lock
  assert_active_pending

  local session_rotated="0"
  if [[ -d "$PENDING_DIR/.execution-claimed" ]]; then
    SESSION_ID=""
    SESSION_STARTED="0"
    SESSION_REVISION="$(( ${SESSION_REVISION:-0} + 1 ))"
    persist_meta "$RUN_DIR/meta.json"
    session_rotated="1"
  fi
  {
    printf '## Pending Review Cancelled: %s\n\n' "$LABEL"
    printf -- '- timestamp_utc: %s\n' "$(now_iso_utc)"
    printf -- '- pending_dir: %s\n' "$(repo_relative_path "$PENDING_DIR")"
    printf -- '- reason: %s\n' "$reason"
    printf -- '- session_rotated: %s\n\n' "$session_rotated"
  } >> "$RUN_DIR/transcript.md"
  release_active_pending
  release_record_lock
  printf 'cancelled=pending\n'
  printf 'session_rotated=%s\n' "$session_rotated"
}

cmd_rotate_session() {
  local run_dir_input="${1:-}"
  local reason="${2:-manual session rotation}"
  load_run "$run_dir_input"
  local locked_run_dir="$RUN_DIR"
  acquire_record_lock
  load_run "$locked_run_dir"
  assert_no_active_pending
  local old_session_id="$SESSION_ID"
  SESSION_ID=""
  SESSION_STARTED="0"
  SESSION_REVISION="$(( ${SESSION_REVISION:-0} + 1 ))"
  persist_meta "$RUN_DIR/meta.json"
  {
    printf '## Session Rotation\n\n'
    printf -- '- timestamp_utc: %s\n' "$(now_iso_utc)"
    printf -- '- old_session_id: %s\n' "$old_session_id"
    printf -- '- new_session_id: pending_first_response\n'
    printf -- '- reason: %s\n\n' "$reason"
  } >> "$RUN_DIR/transcript.md"
  release_record_lock
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
  assert_ready_to_prepare

  local engineer_body prompt mode_flag pending_dir section_context
  engineer_body="$(read_body_arg "$body_mode" "$body_path")"
  mode_flag="$(session_mode_flag)"
  pending_dir="$(prepare_pending_dir "step" "$stage_name")"
  snapshot_dependency_handoffs "$pending_dir"
  section_context=""
  if [[ -n "${SECTION_KEY:-}" ]]; then
    section_context="$(cat <<EOF
- $SECTION_DIR/brief.md
- $SECTION_DIR/state.md
- $SECTION_DIR/handoff.md
$(dependency_prompt_lines "$pending_dir")

Section boundary:
- Own only section "$SECTION_NAME" ($SECTION_KEY).
- Do not read another section's transcript or developer conversation.
- Read another section only through a dependency handoff explicitly required by this section brief.
- Every new implementation assignment goes to a no-history developer sub-agent, and a developer conversation is never resumed.
EOF
)"
  fi
  prompt="$(cat <<EOF
You are reviewing a proposed engineering step inside an ongoing task.

Task name: $TASK_NAME
Stage: $stage_name
Section: ${SECTION_NAME:-legacy task}

Read these files from the workspace before answering:
- $RUN_DIR/task_brief.md
- $CONTRACT_FILE
- $pending_dir/engineer_update.md
$section_context

Respond with these sections only, each as a Markdown heading:
1. Assessment
2. Drift review
3. Risks
4. Improvements
5. Decision
6. Next action

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: GO, GO_WITH_CHANGES, NO_GO. A short
justification may follow the token on the same line.
EOF
)"

  printf '%s\n' "$engineer_body" > "$pending_dir/engineer_update.md"
  printf '%s\n' "$prompt" > "$pending_dir/prompt.md"
  printf '%s\n' "$PM_SYSTEM_PROMPT" > "$pending_dir/system_prompt.txt"
  : > "$pending_dir/response.json"
  write_review_context_manifest "$pending_dir"
  record_pending_meta "$pending_dir" "step" "$stage_name" "$mode_flag"
  write_command_file \
    "$pending_dir/command.txt" \
    "$pending_dir" \
    "$mode_flag"
  activate_prepared_pending "$pending_dir"

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
  assert_ready_to_prepare

  local engineer_body prompt mode_flag pending_dir section_context
  engineer_body="$(read_body_arg "$body_mode" "$body_path")"
  mode_flag="$(session_mode_flag)"
  pending_dir="$(prepare_pending_dir "complete" "final")"
  snapshot_dependency_handoffs "$pending_dir"
  section_context=""
  if [[ -n "${SECTION_KEY:-}" ]]; then
    section_context="$(cat <<EOF
- $SECTION_DIR/brief.md
- $SECTION_DIR/state.md
- $SECTION_DIR/handoff.md
$(dependency_prompt_lines "$pending_dir")

Section boundary:
- Assess only section "$SECTION_NAME" ($SECTION_KEY).
- Do not load another section's transcript or developer conversation.
- A DONE decision still requires a bounded section-handoff before the root coordinator treats the section as done.
EOF
)"
  fi
  prompt="$(cat <<EOF
You are reviewing the completion report for an engineering task.

Task name: $TASK_NAME
Section: ${SECTION_NAME:-legacy task}

Read these files from the workspace before answering:
- $RUN_DIR/task_brief.md
- $CONTRACT_FILE
- $pending_dir/engineer_update.md
$section_context

Respond with these sections only, each as a Markdown heading:
1. Outcome assessment
2. Drift review
3. Expected vs observed
4. Feedback
5. Recommended next steps
6. Decision

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: DONE, FOLLOW_UP, REWORK. A short justification
may follow the token on the same line.
EOF
)"

  printf '%s\n' "$engineer_body" > "$pending_dir/engineer_update.md"
  printf '%s\n' "$prompt" > "$pending_dir/prompt.md"
  printf '%s\n' "$PM_SYSTEM_PROMPT" > "$pending_dir/system_prompt.txt"
  : > "$pending_dir/response.json"
  write_review_context_manifest "$pending_dir"
  record_pending_meta "$pending_dir" "complete" "final" "$mode_flag"
  write_command_file \
    "$pending_dir/command.txt" \
    "$pending_dir" \
    "$mode_flag"
  activate_prepared_pending "$pending_dir"

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
  [[ "$KIND" == "step" ]] || fail "record-step requires a pending step review"
  assert_current_pending_schema
  acquire_record_lock
  assert_active_pending
  assert_execution_claimed
  assert_pending_session_current

  local response_path="$PENDING_DIR/response.json"
  if [[ -n "$response_file_override" ]]; then
    response_path="$response_file_override"
  fi
  [[ -f "$response_path" ]] || fail "response file not found: $response_path"

  local engineer_body claude_response claude_is_error
  engineer_body="$(/bin/cat "$PENDING_DIR/engineer_update.md")"
  claude_is_error="$(extract_json_field "$response_path" "is_error")"
  claude_response="$(extract_json_field "$response_path" "result")"
  [[ -n "$claude_response" ]] || fail "response file is empty: $response_path"
  if [[ "$claude_is_error" == "True" || "$claude_is_error" == "true" ]]; then
    fail "Claude CLI returned an error: $claude_response"
  fi
  validate_step_response "$claude_response"
  update_session_from_response "$response_path"
  SESSION_REVISION="$(( ${SESSION_REVISION:-0} + 1 ))"
  persist_meta "$RUN_DIR/meta.json"
  append_exchange "Step Review" "$LABEL" "$engineer_body" "$claude_response"
  release_active_pending
  release_record_lock
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
  [[ "$KIND" == "complete" ]] || fail "record-complete requires a pending completion review"
  assert_current_pending_schema
  acquire_record_lock
  assert_active_pending
  assert_execution_claimed
  assert_pending_session_current

  local response_path="$PENDING_DIR/response.json"
  if [[ -n "$response_file_override" ]]; then
    response_path="$response_file_override"
  fi
  [[ -f "$response_path" ]] || fail "response file not found: $response_path"

  local engineer_body claude_response claude_is_error completion_decision
  engineer_body="$(/bin/cat "$PENDING_DIR/engineer_update.md")"
  claude_is_error="$(extract_json_field "$response_path" "is_error")"
  claude_response="$(extract_json_field "$response_path" "result")"
  [[ -n "$claude_response" ]] || fail "response file is empty: $response_path"
  if [[ "$claude_is_error" == "True" || "$claude_is_error" == "true" ]]; then
    fail "Claude CLI returned an error: $claude_response"
  fi
  validate_completion_response "$claude_response"
  completion_decision="$(extract_markdown_decision "$claude_response" "DONE,FOLLOW_UP,REWORK")"
  update_session_from_response "$response_path"
  SESSION_REVISION="$(( ${SESSION_REVISION:-0} + 1 ))"
  persist_meta "$RUN_DIR/meta.json"
  append_exchange "Completion Review" "$LABEL" "$engineer_body" "$claude_response"
  write_completion_marker "$completion_decision" "$PENDING_DIR"
  release_active_pending
  release_record_lock
  printf 'recorded=complete\n'
  if [[ -n "${SECTION_KEY:-}" ]]; then
    printf 'handoff_required=%s\n' "$SECTION_DIR/handoff.md"
  fi
}

cmd_print_command() {
  local pending_dir_input="${1:-}"
  load_pending "$pending_dir_input"
  /bin/cat "$PENDING_DIR/command.txt"
}

cmd_current_run() {
  local abs_run_dir rel_run_dir
  abs_run_dir="$(resolve_current_run)" || fail "current run pointer is empty: $CURRENT_RUN_FILE"
  if [[ -n "${SECTION_OVERRIDE:-}" ]]; then
    local section_dir
    section_dir="$(resolve_section_dir "$SECTION_OVERRIDE")"
    rel_run_dir="$(/usr/bin/head -n 1 "$section_dir/run_path.txt" | tr -d '\r')"
    printf 'section=%s\n' "$(slugify "$SECTION_OVERRIDE")"
  else
    rel_run_dir="$(/usr/bin/head -n 1 "$CURRENT_RUN_FILE" | tr -d '\r')"
  fi
  printf 'current_run_relative=%s\n' "$rel_run_dir"
  printf 'current_run_absolute=%s\n' "$abs_run_dir"
}

main() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        shift || fail "--project requires a value"
        PROJECT_OVERRIDE="${1:-}"
        [[ -n "$PROJECT_OVERRIDE" ]] || fail "--project requires a value"
        ;;
      --section)
        shift || fail "--section requires a value"
        SECTION_OVERRIDE="${1:-}"
        [[ -n "$SECTION_OVERRIDE" ]] || fail "--section requires a value"
        ;;
      *)
        args+=("$1")
        ;;
    esac
    shift || true
  done
  set -- "${args[@]}"

  initialize_project_paths

  local cmd="${1:-}"
  case "$cmd" in
    validate)
      shift || true
      cmd_validate "$@"
      ;;
    config)
      shift || true
      cmd_config "$@"
      ;;
    role-prompt)
      shift || true
      cmd_role_prompt "$@"
      ;;
    consult-panel)
      shift || true
      cmd_consult_panel "$@"
      ;;
    init)
      shift || true
      cmd_init "$@"
      ;;
    init-section)
      shift || true
      cmd_init_section "$@"
      ;;
    list-sections)
      shift || true
      cmd_list_sections "$@"
      ;;
    section-prompt)
      shift || true
      cmd_section_prompt "$@"
      ;;
    section-run)
      shift || true
      cmd_section_run "$@"
      ;;
    section-handoff)
      shift || true
      cmd_section_handoff "$@"
      ;;
    adopt-pending)
      shift || true
      cmd_adopt_pending "$@"
      ;;
    claim-execution)
      shift || true
      cmd_claim_execution "$@"
      ;;
    cancel-pending)
      shift || true
      cmd_cancel_pending "$@"
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
    current-run)
      shift || true
      cmd_current_run "$@"
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
