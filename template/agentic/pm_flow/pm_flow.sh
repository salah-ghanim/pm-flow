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
CONTRACT_FILE=""
SECTIONS_DIR=""
SECTIONS_INDEX_FILE=""
SECTION_KEY=""
SECTION_NAME=""
SECTION_DIR=""
RUN_RECORD_LOCK=""
SECTION_CREATE_LOCK=""

usage() {
  cat <<'EOF'
Usage:
  pm_flow.sh [--project <name>] validate
  pm_flow.sh [--project <name>] config
  pm_flow.sh [--project <name>] status
  pm_flow.sh [--project <name>] [--section <name>] tick
  pm_flow.sh [--project <name>] [--section <name>] run [--max-ticks <n>]
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
  # Not named `path`: zsh ties that name to $PATH, so assigning it here would
  # wipe the command search path for the rest of the function.
  local body_file="${2:-}"
  case "$mode" in
    stdin)
      read_stdin_body
      ;;
    file)
      [[ -n "$body_file" ]] || fail "body file path is required"
      [[ -f "$body_file" ]] || fail "body file not found: $body_file"
      /bin/cat "$body_file"
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
    "created_at_utc": sys.argv[5],
}
temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
temp.write_text(json.dumps(payload, indent=2) + "\n")
os.replace(temp, path)
PY
}

validate_loaded_run_metadata() {
  [[ -n "${TASK_NAME:-}" ]] || fail "run metadata is missing task_name"
  [[ -n "${TASK_SLUG:-}" && "$TASK_SLUG" == "$(slugify "$TASK_SLUG")" ]] || \
    fail "run metadata has an invalid task_slug"
  [[ -z "${SECTION_KEY:-}" || "$SECTION_KEY" == "$(slugify "$SECTION_KEY")" ]] || \
    fail "run metadata has an invalid section_key"
  [[ -n "${CREATED_AT_UTC:-}" ]] || fail "run metadata is missing created_at_utc"
}

load_run() {
  local run_dir_input="${1:-}"
  [[ -n "$run_dir_input" ]] || fail "run directory is required"
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
  CREATED_AT_UTC=""
  if [[ -f "$abs_run_dir/meta.json" ]]; then
    local metadata_version
    metadata_version="$(extract_json_field "$abs_run_dir/meta.json" "version")"
    [[ "$metadata_version" == "1" ]] || fail "unsupported run metadata version: $metadata_version"
    TASK_NAME="$(extract_json_field "$abs_run_dir/meta.json" "task_name")"
    TASK_SLUG="$(extract_json_field "$abs_run_dir/meta.json" "task_slug")"
    SECTION_KEY="$(extract_json_field "$abs_run_dir/meta.json" "section_key")"
    CREATED_AT_UTC="$(extract_json_field "$abs_run_dir/meta.json" "created_at_utc")"
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
    printf 'cycle_path=%s\n' "$(repo_relative_path "$pending_dir")"
    printf 'recorded_at_utc=%s\n' "$(now_iso_utc)"
  } > "$marker_tmp"
  mv "$marker_tmp" "$marker_path"
}

assert_current_done_completion() {
  local marker_path="$RUN_DIR/completion.env"
  [[ -f "$marker_path" ]] || \
    fail "section cannot be marked done without a recorded PM completion review"
  local completion_decision
  completion_decision="$(awk -F= '$1 == "decision" {print substr($0, index($0, "=") + 1); exit}' "$marker_path")"
  [[ "$completion_decision" == "DONE" ]] || \
    fail "section cannot be marked done; latest completion decision is ${completion_decision:-missing}"
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
  CREATED_AT_UTC="$(now_iso_utc)"

  printf '%s\n' "$task_brief" > "$RUN_DIR/task_brief.md"
  persist_meta "$RUN_DIR/meta.json"

  local contract_body
  contract_body="$(read_contract)"
  {
    printf '# Section run record\n\n'
    printf -- '- section_name: %s\n' "$SECTION_NAME"
    printf -- '- section_key: %s\n' "$SECTION_KEY"
    printf -- '- task_name: %s\n' "$TASK_NAME"
    printf -- '- task_slug: %s\n' "$TASK_SLUG"
    printf -- '- created_at_utc: %s\n' "$CREATED_AT_UTC"
    if [[ -n "${SECTION_KEY:-}" ]]; then
      printf -- '- rule: every role runs as a fresh process; continuity lives in this section'"'"'s files\n'
    fi
    printf '\n## Task Brief\n\n%s\n\n' "$task_brief"
    printf '## Task Contract\n\n%s\n\n' "$contract_body"
  } > "$RUN_DIR/transcript.md"

  if [[ "$update_project_pointer" == "1" ]]; then
    write_current_run_file "$RUN_DIR"
  fi
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

[[ -f "$SCRIPT_DIR/driver.zsh" ]] || fail "missing driver: $SCRIPT_DIR/driver.zsh"
source "$SCRIPT_DIR/driver.zsh"

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
    tick)
      shift || true
      cmd_tick "$@"
      ;;
    run)
      shift || true
      cmd_run "$@"
      ;;
    status)
      shift || true
      cmd_status "$@"
      ;;
    role-prompt)
      shift || true
      cmd_role_prompt "$@"
      ;;
    consult-panel)
      shift || true
      cmd_consult_panel "$@"
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
    -h|--help|help|"")
      usage
      ;;
    *)
      fail "unknown command: $cmd"
      ;;
  esac
}

main "$@"
