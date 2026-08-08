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
DRIVER_LOCK=""

usage() {
  cat <<'EOF'
Usage:
  pm_flow.sh [--project <name>] validate
  pm_flow.sh [--project <name>] config
  pm_flow.sh [--project <name>] status
  pm_flow.sh [--project <name>] next
  pm_flow.sh [--project <name>] cost
  pm_flow.sh [--project <name>] [--section <name>] tick
  pm_flow.sh [--project <name>] [--section <name>] run [--max-ticks <n>]
  pm_flow.sh [--project <name>] role-prompt <role>
  pm_flow.sh [--project <name>] init-section <section-name> [--file <markdown-file>]
  pm_flow.sh [--project <name>] list-sections
  pm_flow.sh [--project <name>] section-run <section-name>
  pm_flow.sh [--project <name>] section-dependencies <section-name> [--file <markdown-file>]
  pm_flow.sh [--project <name>] section-handoff <section-name> <status> <summary> [--file <markdown-file>]
  pm_flow.sh [--project <name>] consult-panel <section-name> [--file <markdown-file>]
  pm_flow.sh [--project <name>] portfolio-review
  pm_flow.sh [--project <name>] section-analysis <section-name> [--file <markdown-file>]
  pm_flow.sh [--project <name>] proposals <name> [--file <markdown-file>]

  How it runs:
  `run` repeats `tick` until nothing is actionable. Each tick observes the files
  on disk, derives the single next action, performs it, and exits, so an
  interrupted run resumes by being run again.
  Roles are named, not vendors. config.json binds each role to a cli, a model,
  and a difficulty, and every role is dispatched as a fresh process.
  A section that fails `failures_before_consultant` reviews in a row goes to a
  panel of independent consultants; the product officer then adopts one path,
  several in parallel, a synthesis, or abandons the section.

  On demand:
  `portfolio-review` convenes the product officer now, bypassing the governance
  thresholds, and counts as a review.
  `section-analysis` asks one section's manager where it stands, without opening
  or advancing a cycle.
  `proposals` convenes the consultant panel on a question rather than on a
  failure, then has the product officer adjudicate it.
  All three dispatch immediately and refuse while a driver holds the project.
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
PROJECT_CONFIG_FILE=""
ROLES_DIR=""
DOMAINS_DIR=""
DOMAIN=""
DOMAIN_SOURCE=""

# A flow directory hosts several projects and they are not all the same kind of
# work, so the domain belongs to the project. config.json only supplies the
# default for projects installed before domains were recorded per project.
resolve_domain() {
  DOMAIN=""
  DOMAIN_SOURCE="flow default"
  if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
    DOMAIN="$(extract_json_field "$PROJECT_CONFIG_FILE" domain)"
    [[ -z "$DOMAIN" ]] || DOMAIN_SOURCE="project.json"
  fi
  if [[ -z "$DOMAIN" && -f "$AGENT_CONFIG_FILE" ]]; then
    DOMAIN="$(extract_json_field "$AGENT_CONFIG_FILE" domain)"
  fi
  if [[ -z "$DOMAIN" ]]; then
    DOMAIN="generic"
    DOMAIN_SOURCE="built-in default"
  fi
  [[ -f "$DOMAINS_DIR/$DOMAIN.json" ]] || \
    fail "unknown domain '$DOMAIN'; no definition at $DOMAINS_DIR/$DOMAIN.json"
}

# Roles are named, never vendors. This composes a role's persona with the
# project's configured domain so prompts read as a real practitioner in the
# problem space instead of a generic assistant.
compose_role_prompt() {
  local role="$1"
  [[ -f "$AGENT_CONFIG_FILE" ]] || fail "missing agent config: $AGENT_CONFIG_FILE"
  resolve_domain
  local role_file="$ROLES_DIR/$role.md"
  [[ -f "$role_file" ]] || fail "unknown role '$role'; no persona at $role_file"
  local project_name="$PROJECT_KEY"
  if [[ -f "$CONTRACT_FILE" ]]; then
    local contract_heading
    contract_heading="$(/usr/bin/head -n 1 "$CONTRACT_FILE" | sed -E 's/^#[[:space:]]*//; s/[[:space:]]+Task Contract[[:space:]]*$//')"
    [[ -z "$contract_heading" ]] || project_name="$contract_heading"
  fi
  python3 - "$DOMAIN" "$DOMAINS_DIR" "$role_file" "$role" "$project_name" <<'PY'
import json
import sys
from pathlib import Path

domain, domains_dir, role_path, role, project_name = sys.argv[1:]
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
#
# Two things convene a panel - a section that keeps failing, and a question
# asked by hand - and they differ only in what the seats are told to read. The
# dispatch itself is shared, so a fix to seat tolerance or seat parallelism
# reaches both. Results are reported through these three globals because a
# function that also prints its answer cannot print warnings.
PANEL_SEATS=0
PANEL_PROPOSALS=0
PANEL_SEAT_FAILURE=0

run_panel_seats() {
  local panel_dir="$1"
  local persona_file="$2"
  PANEL_SEATS="$(role_seat_count consultant)"
  [[ "$PANEL_SEATS" -ge 1 ]] || fail "the consultant role has no seats"
  PANEL_PROPOSALS=0
  PANEL_SEAT_FAILURE=0

  local seat pids=()
  for seat in {1..$PANEL_SEATS}; do
    (
      "$SCRIPT_DIR/agent_exec.sh" consultant \
        --seat "$seat" \
        --prompt-file "$persona_file" \
        --output "$panel_dir/proposal_${seat}.json" \
        --heartbeat "$panel_dir/heartbeat_seat_${seat}.txt" \
        --label "consultant seat $seat" \
        > "$panel_dir/seat_${seat}.log" 2>&1
    ) &
    pids+=($!)
  done
  for seat in {1..$PANEL_SEATS}; do
    wait "${pids[$seat]}" || PANEL_SEAT_FAILURE=1
  done

  # A seat that errors, times out, or returns something unreadable must not take
  # the panel down with it. That tolerance is the reason to run a panel at all.
  for seat in {1..$PANEL_SEATS}; do
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
      PANEL_PROPOSALS=$(( PANEL_PROPOSALS + 1 ))
    else
      printf 'WARNING: consultant seat %d did not produce a usable proposal\n' "$seat" >&2
    fi
  done

  [[ "$PANEL_PROPOSALS" -ge 1 ]] || fail "no consultant seat produced a usable proposal; see $panel_dir"
  if [[ "$PANEL_PROPOSALS" -lt "$PANEL_SEATS" ]]; then
    printf 'WARNING: only %d of %d consultant seats answered; adjudicating on what arrived\n' \
      "$PANEL_PROPOSALS" "$PANEL_SEATS" >&2
  fi
}

panel_proposal_bullets() {
  local panel_dir="$1"
  local seat listing=""
  for seat in {1..$PANEL_SEATS}; do
    [[ -f "$panel_dir/proposal_${seat}.md" ]] || continue
    listing+="- Proposal ${seat}: $(repo_relative_path "$panel_dir/proposal_${seat}.md")"$'\n'
  done
  printf '%s' "$listing"
}

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

  run_panel_seats "$panel_dir" "$consultant_persona"

  local panel_files
  panel_files="$(panel_proposal_bullets "$panel_dir")"
  panel_files+="- Failure brief: $(repo_relative_path "$panel_dir/failure_brief.md")"$'\n'
  panel_files+="- Section brief: $(repo_relative_path "$section_dir/brief.md")"

  compose_role_task cpo \
    "$SCRIPT_DIR/tasks/consultant_panel_adjudication.md" \
    "PANEL_SUBJECT=Section \`$(basename "$section_dir")\` has failed repeatedly and was referred to a panel of independent consultants." \
    "PANEL_FILES=$panel_files" \
    > "$panel_dir/adjudication_prompt.md"

  printf 'panel_dir=%s\n' "$panel_dir"
  printf 'seats=%s\n' "$PANEL_SEATS"
  printf 'proposals=%s\n' "$PANEL_PROPOSALS"
  printf 'adjudication_prompt=%s\n' "$panel_dir/adjudication_prompt.md"
  [[ "$PANEL_SEAT_FAILURE" == "0" ]] || printf 'note=at least one seat failed; see the seat logs\n'
}

cmd_role_prompt() {
  local role="${1:-}"
  [[ -n "$role" ]] || fail "role-prompt requires a role name"
  compose_role_prompt "$role"
}

cmd_config() {
  [[ -f "$AGENT_CONFIG_FILE" ]] || fail "missing agent config: $AGENT_CONFIG_FILE"
  resolve_domain
  python3 - "$AGENT_CONFIG_FILE" "$DOMAINS_DIR" "$ROLES_DIR" "$DOMAIN" "$DOMAIN_SOURCE" <<'PY'
import json
import sys
from pathlib import Path

config_path, domains_dir, roles_dir, domain, domain_source = sys.argv[1:]
config = json.loads(Path(config_path).read_text())
if config.get("version") != 1:
    raise SystemExit(f"unsupported config version: {config.get('version')!r}")
domain_file = Path(domains_dir) / f"{domain}.json"
if not domain_file.is_file():
    raise SystemExit(f"unknown domain {domain!r}; no definition at {domain_file}")
titles = json.loads(domain_file.read_text()).get("titles", {})

print(f"domain={domain} ({domain_source})")
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
  # Dispatched roles resolve the same project, so they read the same domain.
  export PM_FLOW_PROJECT="$PROJECT_KEY"
  AGENT_CONFIG_FILE="$SCRIPT_DIR/config.json"
  PROJECT_CONFIG_FILE="$PROJECT_DIR/project.json"
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
        # Sections created before priorities existed read as must-have.
        priority = first_line(section_dir / "priority.txt", "must-have")
        summary = first_line(section_dir / "summary.txt", "No bounded handoff yet.")
        updated = first_line(section_dir / "updated_at.txt", "unknown")
        run_path = first_line(section_dir / "run_path.txt", "none")
        handoff_path = section_dir / "handoff.md"
        handoff_rel = os.path.relpath(handoff_path, index_path.parent)
        rows.append(
            f"| {cell(name)} | {cell(priority)} | {cell(status)} | {cell(summary)} | "
            f"[handoff]({cell(handoff_rel)}) | `{cell(run_path)}` | {cell(updated)} |"
        )

    lines = [
        "# Project sections",
        "",
        "This is a generated, bounded portfolio view for the root project coordinator.",
        "Per-section files are authoritative; run `pm_flow.sh list-sections` to refresh this index.",
        "The root coordinator should read this file and the linked handoffs, not section transcripts.",
        "",
        "| Section | Priority | Status | Summary | PM handoff | Run | Updated (UTC) |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    lines.extend(rows or ["| _none_ | - | - | Create a section with `init-section`. | - | - | - |"])
    lines.extend([
        "",
        "Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.",
        "Priority is `must-have` or `nice-to-have`; a section created before priorities existed reads as `must-have`.",
        "A handoff is capped at 500 words and 8192 bytes and carries only outcomes, decisions, interfaces, risks, what is unproven, and the next action.",
        "A handoff is a claim. Check the artifact it names before acting on it.",
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

# One driver at a time per project. Without this, two `run` invocations observe
# the same actionable section and dispatch it twice: the claim directories are
# per step, so both pay for the same call.
release_driver_lock() {
  release_lock DRIVER_LOCK
}

acquire_driver_lock() {
  mkdir -p "$PROJECT_DIR"
  zmodload zsh/system 2>/dev/null || fail "the zsh/system module is required for safe locking"
  local lock_file="$PROJECT_DIR/.driver.lock"
  [[ -e "$lock_file" ]] || : >> "$lock_file"
  # Refused immediately rather than queued: the other driver holds this for the
  # length of its whole run, so waiting behind it buys nothing and hides the
  # fact that two drivers were started.
  if ! zsystem flock -t 0 -f DRIVER_LOCK "$lock_file" 2>/dev/null; then
    fail "another pm_flow driver is already running for project '$PROJECT_KEY'"
  fi
  # Deliberately no EXIT trap. In zsh a trap installed inside a function is
  # local to that function and fires when the *function* returns, so trapping
  # here would release the lock immediately and the mutex would guard nothing.
  # The lock is held by an open descriptor and the kernel drops it when the
  # process dies, which is exactly the lifetime a run-level mutex wants.
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

# Parse a verdict section out of a role's markdown response.
#
# The response has already been paid for by the time this runs, so the parser is
# deliberately forgiving about presentation and strict only about the verdict
# token. It accepts atx headings, bare heading lines, numbered headings, bold
# headings, a verdict on the heading line itself, and value lines that arrive
# blockquoted, bulleted, numbered or emphasised. More than one section with the
# heading is no longer an error: the last one that carries a legal token wins,
# because a role that restates its verdict at the end means the last statement.
#
# Prints two lines: the verdict token, then the whole value line it came from.
markdown_verdict_parse() {
  local response="$1"
  local allowed_csv="$2"
  local heading="${3:-Decision}"
  printf '%s\n' "$response" | python3 -c '
import re
import sys

allowed = set(sys.argv[1].split(","))
heading_name = sys.argv[2]
lines = sys.stdin.read().splitlines()

heading_re = re.compile(
    r"^[\s>]*"
    r"(?:#{1,6}\s*)?"
    r"(?:\d+[.)]\s*)?"
    r"(?:\*{1,3}|_{1,3})?\s*"
    + re.escape(heading_name)
    + r"\s*(?:\*{1,3}|_{1,3})?"
    r"\s*(?:[:\-]+[ \t]*(?P<inline>.*?))?\s*$",
    re.IGNORECASE,
)
next_heading_re = re.compile(r"^[\s>]*#{1,6}\s+\S")


def clean(value):
    value = re.sub(r"^[\s>]*", "", value)
    value = re.sub(r"^(?:[-*+]|\d+[.)])\s+", "", value)
    return value.strip().strip("*_` \t")


sections = []
index = 0
while index < len(lines):
    match = heading_re.match(lines[index])
    if not match:
        index += 1
        continue
    values = []
    inline = clean(match.group("inline") or "")
    if inline:
        values.append(inline)
    index += 1
    while index < len(lines):
        line = lines[index]
        if next_heading_re.match(line) or heading_re.match(line):
            break
        candidate = clean(line)
        if candidate:
            values.append(candidate)
        index += 1
    sections.append(values)

if not sections:
    raise SystemExit(f"response has no {heading_name} section")

token_re = re.compile(r"^([A-Z][A-Z_]*)\b")
last_seen = None
for values in reversed(sections):
    if not values:
        continue
    last_seen = values[0]
    token = token_re.match(values[0])
    verdict = token.group(1) if token else values[0]
    if verdict in allowed:
        print(verdict)
        print(values[0])
        break
else:
    if last_seen is None:
        raise SystemExit(f"response {heading_name} section is empty")
    raise SystemExit(
        f"response {heading_name} must begin with one of {sorted(allowed)}, "
        f"got {last_seen!r}"
    )
' "$allowed_csv" "$heading"
}

extract_markdown_decision() {
  local parsed
  parsed="$(markdown_verdict_parse "$1" "$2" "${3:-Decision}")" || fail "content missing valid decision"
  printf '%s\n' "${parsed%%$'\n'*}"
}

# The verdict line in full, justification included. Some transitions need the
# text after the token, for instance the name of the external dependency a
# BLOCKED_EXTERNAL scope is required to state.
extract_markdown_decision_line() {
  local parsed
  parsed="$(markdown_verdict_parse "$1" "$2" "${3:-Decision}")" || return 1
  printf '%s\n' "${parsed#*$'\n'}"
}

# Pull the assignment out of a scope response. The whole response used to become
# assignment.md, editorial and all, so the developer read the manager's
# reasoning about the section as though it were part of the task.
extract_assignment_sections() {
  local response="$1"
  printf '%s\n' "$response" | python3 -c '
import re
import sys

WANTED = ["assignment", "acceptance", "rejection conditions"]
TITLES = {"assignment": "Assignment", "acceptance": "Acceptance",
          "rejection conditions": "Rejection conditions"}

atx_re = re.compile(r"^\s*#{1,6}\s*(?:\d+[.)]\s*)?\**\s*(.+?)\s*\**\s*:?\s*$")
bold_re = re.compile(r"^\s*(?:\d+[.)]\s*)?\*\*(.+?)\*\*\s*:?\s*$")


def heading_name(line):
    for pattern in (atx_re, bold_re):
        match = pattern.match(line)
        if match:
            return match.group(1).strip().lower()
    return None


blocks = {}
current = None
buffer = []
for line in sys.stdin.read().splitlines():
    name = heading_name(line)
    if name is not None:
        if current is not None:
            blocks.setdefault(current, buffer)
        current = name if name in WANTED else None
        buffer = []
        continue
    if current is not None:
        buffer.append(line)
if current is not None:
    blocks.setdefault(current, buffer)

out = []
for name in WANTED:
    body = "\n".join(blocks.get(name, [])).strip()
    if not body:
        continue
    out.extend(["## " + TITLES[name], "", body, ""])
if not out:
    raise SystemExit("no assignment sections found")
print("\n".join(out).rstrip())
'
}

validate_section_brief() {
  local brief="$1"
  assert_matches "$brief" '(?im)^#{1,6}\s+Objective\s*$' "section Objective heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Scope\s*$' "section Scope heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Priority\s*$' "section Priority heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Owned paths\s*$' "section Owned paths heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Dependencies\s*$' "section Dependencies heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Acceptance\s*$' "section Acceptance heading"
  assert_matches "$brief" '(?im)^#{1,6}\s+Rejection conditions\s*$' "section Rejection conditions heading"
}

# A section states what the product loses without it, at the moment it is cut.
# Two lines out: the token, then the loss. The token is what `status`, the
# registry and the portfolio review read; the loss is what makes a cut arguable
# instead of arbitrary.
extract_section_priority() {
  local brief="$1"
  printf '%s\n' "$brief" | python3 -c '
import re
import sys

inside = False
value = ""
for line in sys.stdin.read().splitlines():
    heading = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
    if heading:
        if inside:
            break
        inside = heading.group(1).strip().lower() == "priority"
        continue
    if not inside:
        continue
    candidate = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s*", "", line).strip().strip("`*_ ")
    if candidate:
        value = candidate
        break

if not value:
    raise SystemExit("Priority must contain one bullet naming must-have or nice-to-have")

match = re.match(r"^(must[\s-]?have|nice[\s-]?to[\s-]?have)\b[\s:,.-]*(.*)$", value, re.I)
if not match:
    raise SystemExit(
        f"Priority must begin with must-have or nice-to-have, got: {value}"
    )
token = "must-have" if match.group(1).lower().startswith("must") else "nice-to-have"
loss = match.group(2).strip().strip("`*_ ")
if not loss:
    raise SystemExit(
        "Priority must state in one line what the product loses without this "
        f"section, after the {token} token"
    )
print(token)
print(loss)
'
}

# Sections created before priorities existed read as must-have, so nothing is
# ever cut for lack of a label it was never asked for.
section_priority() {
  local section_dir="$1"
  local value
  value="$(first_line_or "$section_dir/priority.txt" "")"
  printf '%s\n' "${value:-must-have}"
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

# A dependency edit that introduces a cycle deadlocks every section on it, and
# nothing else in the flow would notice: `waiting-dependencies` is a legal
# resting state, so the run would simply report that nothing is actionable.
assert_no_dependency_cycle() {
  local section_key="$1"
  local handoffs="$2"
  local report
  if ! report="$(python3 - "$SECTIONS_DIR" "$section_key" "$handoffs" <<'PY'
from pathlib import Path
import sys

sections_dir = Path(sys.argv[1])
changed_key = sys.argv[2]
proposed = [line.strip() for line in sys.argv[3].splitlines() if line.strip()]


def keys_from(lines):
    found = []
    for line in lines:
        parts = line.strip().split("/")
        if len(parts) >= 2:
            found.append(parts[-2])
    return found


graph = {}
for section_dir in sorted(p for p in sections_dir.iterdir()
                          if p.is_dir() and not p.name.startswith(".")):
    listing = section_dir / "dependency_handoffs.txt"
    lines = listing.read_text().splitlines() if listing.is_file() else []
    graph[section_dir.name] = keys_from(lines)
graph[changed_key] = keys_from(proposed)

state = {}
trail = []


def walk(node):
    state[node] = 1
    trail.append(node)
    for neighbour in graph.get(node, []):
        if state.get(neighbour) == 1:
            cycle = trail[trail.index(neighbour):] + [neighbour]
            print("dependency cycle: " + " -> ".join(cycle))
            raise SystemExit(1)
        if state.get(neighbour, 0) == 0:
            walk(neighbour)
    trail.pop()
    state[node] = 2


for node in graph:
    if state.get(node, 0) == 0:
        walk(node)
PY
  )"; then
    fail "$report"
  fi
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
  # The heading that would have surfaced a client proven only against a fake at
  # cycle 003 instead of never. A handoff without it reports outcomes with no
  # stated distance left to run.
  assert_matches "$handoff" '(?im)^#{1,6}\s+What is unproven\s*$' "handoff What is unproven heading"
  assert_matches "$handoff" '(?im)^#{1,6}\s+Next action\s*$' "handoff Next action heading"
}

# The same checks as validate_handoff, reported instead of enforced. A handoff
# that misses the budget used to be re-requested with the identical prompt and
# no feedback, so the second attempt missed it the same way and bricked the
# cycle. The caller feeds this text back to the role.
handoff_budget_report() {
  local handoff="$1"
  printf '%s\n' "$handoff" | python3 -c '
import re
import sys

text = sys.stdin.read()
words = len(text.split())
byte_count = len(text.encode("utf-8", errors="replace"))
problems = []
if words > 500:
    problems.append(
        f"It is {words} words; the cap is 500. Cut roughly {words - 500} words."
    )
if byte_count > 8192:
    problems.append(
        f"It is {byte_count} bytes; the cap is 8192. Cut roughly "
        f"{byte_count - 8192} bytes."
    )
for heading in ("Outcome", "Decisions", "Interfaces", "Risks",
                "What is unproven", "Next action"):
    if not re.search(rf"^#{{1,6}}\s+{re.escape(heading)}\s*$", text,
                     re.MULTILINE | re.IGNORECASE):
        problems.append(f"The `## {heading}` heading is missing or misspelled.")
if problems:
    print("\n".join(f"- {problem}" for problem in problems))
'
}

# Brief-authoring checks that catch a cycle-wasting brief before any dispatch.
# These warn rather than reject: a section that creates a new file legitimately
# names a path that does not exist yet, and refusing it would be worse than
# saying so.
warn_brief_authoring() {
  local brief="$1"
  local section_key="$2"
  local warnings
  warnings="$(printf '%s\n' "$brief" | python3 -c '
import re
import sys
from pathlib import Path

project_root = Path(sys.argv[1])
warnings = []
lines = sys.stdin.read().splitlines()

section = None
owned, acceptance = [], []
for line in lines:
    heading = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
    if heading:
        section = heading.group(1).strip().lower()
        continue
    bullet = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
    if not bullet:
        continue
    if section == "owned paths":
        owned.append(bullet.group(1).strip())
    elif section == "acceptance":
        acceptance.append(bullet.group(1).strip())

for entry in owned:
    ticked = re.search(r"`([^`]+)`", entry)
    candidate = (ticked.group(1) if ticked else entry).strip()
    if re.search(r"[*?\[{]", candidate):
        continue
    if not (project_root / candidate).exists():
        warnings.append(f"owned path does not exist in the working tree: {candidate}")

bare = re.compile(r"(?:^|[\s`(])(pytest|python|python3|node|npm|go|cargo)\s", re.I)
for entry in acceptance:
    for command in re.findall(r"`([^`]+)`", entry):
        if bare.search(" " + command) and not re.search(
            r"(?:\.venv/|/bin/|venv/|\./)", command
        ):
            warnings.append(
                f"acceptance command is not pinned to an interpreter path: {command}"
            )

print("\n".join(warnings))
' "$PROJECT_ROOT")"
  [[ -n "$warnings" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf 'WARNING: section %s brief: %s\n' "$section_key" "$line" >&2
  done <<< "$warnings"
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

  local section_brief owned_paths dependency_handoffs priority
  section_brief="$(read_body_arg "$body_mode" "$body_path")"
  [[ -n "$section_brief" ]] || fail "section brief must not be empty"
  [[ -f "$CONTRACT_FILE" ]] || fail "missing task contract: $CONTRACT_FILE"
  validate_section_brief "$section_brief"
  owned_paths="$(extract_owned_paths "$section_brief")"
  # The parser prints what is wrong with it on stderr.
  priority="$(extract_section_priority "$section_brief")" || \
    fail "section brief has an unusable Priority heading"

  SECTION_NAME="$section_name"
  SECTION_KEY="$(slugify "$section_name")"
  warn_brief_authoring "$section_brief" "$SECTION_KEY"
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
  printf '%s\n' "$priority" > "$SECTION_DIR/priority.txt"
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
    printf '## What is unproven\n\n- Everything in the brief; nothing has been attempted yet.\n\n'
    printf '## Next action\n\n- Awaiting the first scoped assignment.\n'
  } > "$SECTION_DIR/handoff.md"

  create_run "$SECTION_NAME" "$section_brief" "0"
  printf '%s\n' "$(repo_relative_path "$RUN_DIR")" > "$SECTION_DIR/run_path.txt"
  mv "$staged_section_dir" "$final_section_dir"
  SECTION_DIR="$final_section_dir"
  refresh_sections_index
  release_section_create_lock

  printf 'section_key=%s\n' "$SECTION_KEY"
  printf 'section_dir=%s\n' "$SECTION_DIR"
  printf 'run_dir=%s\n' "$RUN_DIR"
  printf 'handoff=%s\n' "$SECTION_DIR/handoff.md"
}

cmd_list_sections() {
  refresh_sections_index
  /bin/cat "$SECTIONS_INDEX_FILE"
}

# The dependency graph, changed through validation rather than by hand.
#
# Hand-editing `dependency_handoffs.txt` is how a graph acquires a cycle, a
# reference to a section that does not exist, or a self-dependency, and none of
# those are visible afterwards: the sections involved simply sit in
# `waiting-dependencies` forever and the run reports that nothing is actionable.
# The product officer owns the graph, so it gets a command instead of a file.
cmd_section_dependencies() {
  local section_input="${1:-}"
  [[ -n "$section_input" ]] || fail "section-dependencies requires a section name"
  local body_mode="stdin"
  local body_path=""
  if [[ "${2:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown section-dependencies argument: ${2:-}"
  fi

  local section_dir section_key body handoffs staged
  section_dir="$(resolve_section_dir "$section_input")"
  section_key="$(basename "$section_dir")"
  body="$(read_body_arg "$body_mode" "$body_path")"
  # The same shape a brief uses, so one format states dependencies everywhere.
  assert_matches "$body" '(?im)^#{1,6}\s+Dependencies\s*$' "Dependencies heading"

  acquire_section_create_lock
  # Every named section must exist and must not be this one; that check already
  # lives in the brief path and is reused here rather than restated.
  handoffs="$(extract_dependency_handoffs "$body" "$section_key")"
  assert_no_dependency_cycle "$section_key" "$handoffs"
  if [[ -f "$section_dir/owned_paths.txt" ]]; then
    assert_no_owned_path_overlap "$section_key" "$(/bin/cat "$section_dir/owned_paths.txt")"
  fi
  staged="$section_dir/.dependency_handoffs.$$.tmp"
  printf '%s\n' "$handoffs" > "$staged"
  mv "$staged" "$section_dir/dependency_handoffs.txt"
  refresh_sections_index
  release_section_create_lock

  printf 'recorded=section-dependencies\n'
  printf 'section=%s\n' "$section_key"
  printf 'dependencies=%s\n' "${handoffs//$'\n'/,}"
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
    next)
      shift || true
      cmd_next "$@"
      ;;
    cost)
      shift || true
      cmd_cost "$@"
      ;;
    role-prompt)
      shift || true
      cmd_role_prompt "$@"
      ;;
    consult-panel)
      shift || true
      cmd_consult_panel "$@"
      ;;
    portfolio-review)
      shift || true
      cmd_portfolio_review "$@"
      ;;
    section-analysis)
      shift || true
      cmd_section_analysis "$@"
      ;;
    proposals)
      shift || true
      cmd_proposals "$@"
      ;;
    init-section)
      shift || true
      cmd_init_section "$@"
      ;;
    list-sections)
      shift || true
      cmd_list_sections "$@"
      ;;
    section-run)
      shift || true
      cmd_section_run "$@"
      ;;
    section-dependencies)
      shift || true
      cmd_section_dependencies "$@"
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
