#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
DEFAULT_MISSION="achieve meaningful progress on the active project objective with explicit validation and controlled scope"
DEFAULT_BASELINE="TBD"
TEMPLATE_CACHE_DIR=""

usage() {
  cat <<'EOF'
Usage:
  install.sh [target-repo] [--name <project-name>] [--project-key <key>] [--domain <domain>] [--mission <text>] [--baseline <text>] [--repo-raw-base <url>] [--force]

Installs the generic Claude PM flow template into the target repository.

Default reinstall behavior:
- refresh generic `agentic/pm_flow/*` scripts and docs
- refresh per-project `task_contract.md`, `start.md`, and `resume.md`
- back up pre-section start/resume prompts once with a `.pre-sections.md` suffix
- preserve the project plan, section workspaces, generated registry, and run history
- preserve config.json (cli, model, and difficulty bindings per role)
- use `--force` only when a full project-template replacement is intended

Domains: generic (default), saas, prop-trading, crypto-trading, infrastructure.

Examples:
  ./install.sh /path/to/repo --name "My Repo"
  curl -fsSL https://raw.githubusercontent.com/salah-ghanim/pm-flow/main/install.sh | \
    zsh -s -- . --repo-raw-base https://raw.githubusercontent.com/salah-ghanim/pm-flow/main
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

slugify() {
  local input="${1:-project}"
  local slug
  slug="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$slug" ]]; then
    slug="project"
  fi
  printf '%s\n' "$slug"
}

fetch_template() {
  local rel_path="$1"
  if [[ -n "${TEMPLATE_CACHE_DIR:-}" ]]; then
    local cached_path="$TEMPLATE_CACHE_DIR/$rel_path"
    [[ -f "$cached_path" ]] || fail "prefetched template missing: $rel_path"
    /bin/cat "$cached_path"
    return
  fi
  if [[ -n "${REPO_RAW_BASE:-}" ]]; then
    curl --fail --silent --show-error --location "${REPO_RAW_BASE%/}/$rel_path"
    return
  fi

  local local_path="$SCRIPT_DIR/$rel_path"
  [[ -f "$local_path" ]] || fail "template file not found: $local_path"
  /bin/cat "$local_path"
}

cleanup_template_cache() {
  if [[ -n "${TEMPLATE_CACHE_DIR:-}" && -d "$TEMPLATE_CACHE_DIR" && \
        "$(basename "$TEMPLATE_CACHE_DIR")" == pm-flow-install.* ]]; then
    rm -rf -- "$TEMPLATE_CACHE_DIR"
  fi
  TEMPLATE_CACHE_DIR=""
}

prefetch_templates() {
  local template_paths=(
    "template/agentic/pm_flow/README.md"
    "template/agentic/pm_flow/pm_flow.sh"
    "template/agentic/pm_flow/net_exec.sh"
    "template/agentic/pm_flow/codex_pm_review.sh"
    "template/agentic/pm_flow/agent_exec.sh"
    "template/agentic/pm_flow/config.json"
    "template/agentic/pm_flow/roles/cpo.md"
    "template/agentic/pm_flow/roles/pm.md"
    "template/agentic/pm_flow/roles/developer.md"
    "template/agentic/pm_flow/roles/consultant.md"
    "template/agentic/pm_flow/roles/10x_developer.md"
    "template/agentic/pm_flow/domains/generic.json"
    "template/agentic/pm_flow/domains/saas.json"
    "template/agentic/pm_flow/domains/prop-trading.json"
    "template/agentic/pm_flow/domains/crypto-trading.json"
    "template/agentic/pm_flow/domains/infrastructure.json"
    "template/agentic/pm_flow/tasks/consultant_panel_adjudication.md"
    "template/agentic/pm_flow/local_env.sh.example"
    "template/agentic/pm_flow/projects.md"
    "template/agentic/pm_flow/project/project_state/README.md"
    "template/agentic/pm_flow/project/project_state/plan.md"
    "template/agentic/pm_flow/project/project_state/start.md"
    "template/agentic/pm_flow/project/project_state/resume.md"
    "template/agentic/pm_flow/project/project_state/current_run.txt"
    "template/agentic/pm_flow/project/project_state/sections.md"
    "template/agentic/pm_flow/project/task_contract.md"
    "template/CLAUDE.md"
  )
  TEMPLATE_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-install.XXXXXX")"
  trap cleanup_template_cache EXIT HUP INT TERM
  local rel_path source_path cached_path
  for rel_path in "${template_paths[@]}"; do
    cached_path="$TEMPLATE_CACHE_DIR/$rel_path"
    mkdir -p "$(dirname "$cached_path")"
    if [[ -n "${REPO_RAW_BASE:-}" ]]; then
      if ! curl --fail --silent --show-error --location \
          "${REPO_RAW_BASE%/}/$rel_path" > "$cached_path"; then
        fail "could not prefetch template: $rel_path"
      fi
    else
      source_path="$SCRIPT_DIR/$rel_path"
      [[ -f "$source_path" ]] || fail "template file not found: $source_path"
      if ! cp "$source_path" "$cached_path"; then
        fail "could not prefetch template: $rel_path"
      fi
    fi
  done
}

render_template() {
  local rel_path="$1"
  local dst="$2"
  local project_name="$3"
  local project_root="$4"
  local primary_mission="$5"
  local baseline_name="$6"
  local project_key="${7:-$(slugify "$project_name")}"
  local escaped_project_name escaped_project_root escaped_primary_mission escaped_baseline_name escaped_project_key
  escaped_project_name="$(escape_sed_replacement "$project_name")"
  escaped_project_root="$(escape_sed_replacement "$project_root")"
  escaped_primary_mission="$(escape_sed_replacement "$primary_mission")"
  escaped_baseline_name="$(escape_sed_replacement "$baseline_name")"
  escaped_project_key="$(escape_sed_replacement "$project_key")"
  local dst_dir tmp_path
  dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir"
  tmp_path="$(mktemp "$dst_dir/.pm-flow-render.XXXXXX")"
  if ! fetch_template "$rel_path" | sed \
      -e "s|{{PROJECT_NAME}}|$escaped_project_name|g" \
      -e "s|{{PROJECT_KEY}}|$escaped_project_key|g" \
      -e "s|{{PROJECT_ROOT}}|$escaped_project_root|g" \
      -e "s|{{PRIMARY_MISSION}}|$escaped_primary_mission|g" \
      -e "s|{{CURRENT_BASELINE}}|$escaped_baseline_name|g" \
      > "$tmp_path"; then
    rm -f -- "$tmp_path"
    fail "could not render template: $rel_path"
  fi
  mv "$tmp_path" "$dst"
}

copy_template() {
  local rel_path="$1"
  local dst="$2"
  local dst_dir tmp_path
  dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir"
  tmp_path="$(mktemp "$dst_dir/.pm-flow-copy.XXXXXX")"
  if ! fetch_template "$rel_path" > "$tmp_path"; then
    rm -f -- "$tmp_path"
    fail "could not copy template: $rel_path"
  fi
  mv "$tmp_path" "$dst"
}

atomic_copy_file() {
  local source_path="$1"
  local dst="$2"
  local dst_dir tmp_path
  dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir"
  tmp_path="$(mktemp "$dst_dir/.pm-flow-copy.XXXXXX")"
  if ! cp "$source_path" "$tmp_path"; then
    rm -f -- "$tmp_path"
    fail "could not copy $source_path to $dst"
  fi
  mv "$tmp_path" "$dst"
}

write_project_key() {
  local key_path="$1"
  local project_key="$2"
  local tmp_path
  tmp_path="$(mktemp "$(dirname "$key_path")/.project-key.XXXXXX")"
  printf '%s\n' "$project_key" > "$tmp_path"
  mv "$tmp_path" "$key_path"
}

resolve_install_project_key() {
  local flow_dir="$1"
  local requested_key="$2"
  local default_key="$3"
  local force="$4"
  local key_file="$flow_dir/.project-key"
  local persisted_key=""

  if [[ -f "$key_file" ]]; then
    persisted_key="$(/usr/bin/head -n 1 "$key_file" | tr -d '\r')"
    [[ -n "$persisted_key" && "$persisted_key" == "$(slugify "$persisted_key")" ]] || \
      fail "invalid persisted project key in $key_file"
  fi

  if [[ -n "$requested_key" ]]; then
    local normalized_requested
    normalized_requested="$(slugify "$requested_key")"
    if [[ -n "$persisted_key" && "$persisted_key" != "$normalized_requested" && "$force" != "1" ]]; then
      fail "requested project key '$normalized_requested' differs from persisted key '$persisted_key'; use --force only for an intentional identity replacement"
    fi
    printf '%s\n' "$normalized_requested"
    return
  fi

  if [[ -n "$persisted_key" ]]; then
    printf '%s\n' "$persisted_key"
    return
  fi

  if [[ -d "$flow_dir" ]]; then
    local candidates=()
    local candidate
    for candidate in "$flow_dir"/*(/N); do
      if [[ -f "$candidate/task_contract.md" && -d "$candidate/project_state" ]]; then
        candidates+=("$(basename "$candidate")")
      fi
    done
    if [[ "${#candidates[@]}" == "1" ]]; then
      printf '%s\n' "$candidates[1]"
      return
    fi
    if [[ "${#candidates[@]}" -gt "1" ]]; then
      fail "$(printf 'multiple pm-flow project workspaces exist under %s; rerun with --project-key <key>\nFound: %s\nOnly the selected workspace has its task_contract.md, start.md, and resume.md refreshed.' \
        "$flow_dir" "${(j:, :)candidates}")"
    fi
  fi

  printf '%s\n' "$default_key"
}

backup_pre_section_prompt() {
  local prompt_path="$1"
  local coordinator_heading="$2"
  [[ -f "$prompt_path" ]] || return 0
  if grep -q -- "$coordinator_heading" "$prompt_path"; then
    return 0
  fi
  local backup_path="${prompt_path%.md}.pre-sections.md"
  if [[ ! -f "$backup_path" ]]; then
    atomic_copy_file "$prompt_path" "$backup_path"
  fi
}

merge_claude_rules() {
  local claude_path="$1"
  local rendered_rules_path="$2"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to merge pm-flow rules into CLAUDE.md"
  python3 - "$claude_path" "$rendered_rules_path" <<'PY'
from pathlib import Path
import os
import sys

target = Path(sys.argv[1])
rendered = Path(sys.argv[2]).read_text().strip()
begin = "<!-- pm-flow:begin -->"
end = "<!-- pm-flow:end -->"
if begin not in rendered or end not in rendered:
    raise SystemExit("rendered CLAUDE rules are missing managed-block markers")

current = target.read_text() if target.is_file() else ""
if begin in current or end in current:
    if current.count(begin) != 1 or current.count(end) != 1:
        raise SystemExit(f"invalid pm-flow managed block in {target}")
    before, remainder = current.split(begin, 1)
    _, after = remainder.split(end, 1)
    merged = before.rstrip() + "\n\n" + rendered + after
else:
    merged = current.rstrip()
    if merged:
        merged += "\n\n"
    merged += rendered + "\n"
temp = target.with_name(f".{target.name}.{os.getpid()}.tmp")
temp.write_text(merged)
os.replace(temp, target)
PY
}

main() {
  local target_repo="."
  if [[ $# -gt 0 && "${1:-}" != --* ]]; then
    target_repo="$1"
    shift || true
  fi

  local project_name=""
  local requested_project_key=""
  local primary_mission="$DEFAULT_MISSION"
  local baseline_name="$DEFAULT_BASELINE"
  local repo_raw_base="${PM_FLOW_REPO_RAW_BASE:-}"
  local domain="generic"
  local force="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift || fail "--name requires a value"
        project_name="${1:-}"
        [[ -n "$project_name" ]] || fail "--name requires a value"
        ;;
      --project-key)
        shift || fail "--project-key requires a value"
        requested_project_key="${1:-}"
        [[ -n "$requested_project_key" ]] || fail "--project-key requires a value"
        ;;
      --mission)
        shift || fail "--mission requires a value"
        primary_mission="${1:-}"
        [[ -n "$primary_mission" ]] || fail "--mission requires a value"
        ;;
      --baseline)
        shift || fail "--baseline requires a value"
        baseline_name="${1:-}"
        [[ -n "$baseline_name" ]] || fail "--baseline requires a value"
        ;;
      --domain)
        shift || fail "--domain requires a value"
        domain="${1:-}"
        case "$domain" in
          generic|saas|prop-trading|crypto-trading|infrastructure) ;;
          *) fail "unknown --domain '$domain'; choose generic, saas, prop-trading, crypto-trading, or infrastructure" ;;
        esac
        ;;
      --repo-raw-base)
        shift || fail "--repo-raw-base requires a value"
        repo_raw_base="${1:-}"
        [[ -n "$repo_raw_base" ]] || fail "--repo-raw-base requires a value"
        ;;
      --force)
        force="1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
    shift || true
  done

  local abs_target
  abs_target="$(cd -P "$target_repo" && pwd -P)"
  [[ -d "$abs_target" ]] || fail "target repo not found: $target_repo"

  REPO_RAW_BASE="$repo_raw_base"
  if [[ -z "$REPO_RAW_BASE" && ! -d "$TEMPLATE_DIR" ]]; then
    fail "local template directory missing; rerun with --repo-raw-base <raw-github-base>"
  fi

  if [[ -z "$project_name" ]]; then
    project_name="$(basename "$abs_target")"
  fi

  local flow_dir="$abs_target/agentic/pm_flow"
  local project_key
  project_key="$(resolve_install_project_key \
    "$flow_dir" \
    "$requested_project_key" \
    "$(slugify "$(basename "$abs_target")")" \
    "$force")"
  local project_dir="$flow_dir/$project_key"
  local flow_exists="0"
  if [[ -d "$flow_dir" ]]; then
    flow_exists="1"
  fi

  prefetch_templates

  mkdir -p "$flow_dir"
  if [[ "$force" == "1" && -d "$project_dir" ]]; then
    rm -rf "$project_dir"
  fi
  mkdir -p "$project_dir"
  mkdir -p "$project_dir/runs"
  mkdir -p "$project_dir/project_state"
  mkdir -p "$project_dir/sections"

  render_template \
    "template/agentic/pm_flow/README.md" \
    "$flow_dir/README.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  copy_template "template/agentic/pm_flow/pm_flow.sh" "$flow_dir/pm_flow.sh"
  copy_template "template/agentic/pm_flow/net_exec.sh" "$flow_dir/net_exec.sh"
  copy_template "template/agentic/pm_flow/codex_pm_review.sh" "$flow_dir/codex_pm_review.sh"
  copy_template "template/agentic/pm_flow/agent_exec.sh" "$flow_dir/agent_exec.sh"
  local role_name domain_name
  for role_name in cpo pm developer consultant 10x_developer; do
    copy_template "template/agentic/pm_flow/roles/$role_name.md" "$flow_dir/roles/$role_name.md"
  done
  for domain_name in generic saas prop-trading crypto-trading infrastructure; do
    copy_template "template/agentic/pm_flow/domains/$domain_name.json" "$flow_dir/domains/$domain_name.json"
  done
  copy_template "template/agentic/pm_flow/tasks/consultant_panel_adjudication.md" \
    "$flow_dir/tasks/consultant_panel_adjudication.md"
  # config.json carries the operator's cli/model/difficulty choices, so a
  # reinstall must never overwrite it.
  if [[ ! -f "$flow_dir/config.json" || "$force" == "1" ]]; then
    fetch_template "template/agentic/pm_flow/config.json" \
      | sed -e "s|{{DOMAIN}}|$(escape_sed_replacement "$domain")|g" > "$flow_dir/.config.json.tmp"
    mv "$flow_dir/.config.json.tmp" "$flow_dir/config.json"
  fi
  copy_template "template/agentic/pm_flow/local_env.sh.example" "$flow_dir/local_env.sh.example"
  if [[ ! -f "$flow_dir/projects.md" || "$force" == "1" ]]; then
    render_template \
      "template/agentic/pm_flow/projects.md" \
      "$flow_dir/projects.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
  fi

  if [[ ! -f "$flow_dir/pm_flow.sh" || ! -f "$flow_dir/net_exec.sh" || ! -f "$flow_dir/projects.md" ]]; then
    fail "agentic/pm_flow exists but is missing required generic files; rerun with --force to repair"
  fi

  render_template \
    "template/agentic/pm_flow/project/project_state/README.md" \
    "$project_dir/project_state/README.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  if [[ ! -f "$project_dir/project_state/plan.md" || "$force" == "1" ]]; then
    render_template \
      "template/agentic/pm_flow/project/project_state/plan.md" \
      "$project_dir/project_state/plan.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
  fi
  if [[ "$force" != "1" ]]; then
    backup_pre_section_prompt \
      "$project_dir/project_state/start.md" \
      "^# Project coordinator start prompt$"
    backup_pre_section_prompt \
      "$project_dir/project_state/resume.md" \
      "^# Project coordinator resume prompt$"
  fi
  render_template \
    "template/agentic/pm_flow/project/project_state/start.md" \
    "$project_dir/project_state/start.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  render_template \
    "template/agentic/pm_flow/project/project_state/resume.md" \
    "$project_dir/project_state/resume.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  if [[ ! -f "$project_dir/project_state/current_run.txt" || "$force" == "1" ]]; then
    copy_template \
      "template/agentic/pm_flow/project/project_state/current_run.txt" \
      "$project_dir/project_state/current_run.txt"
  fi
  if [[ ! -f "$project_dir/project_state/sections.md" || "$force" == "1" ]]; then
    copy_template \
      "template/agentic/pm_flow/project/project_state/sections.md" \
      "$project_dir/project_state/sections.md"
  fi
  render_template \
    "template/agentic/pm_flow/project/task_contract.md" \
    "$project_dir/task_contract.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"

  if [[ -f "$abs_target/CLAUDE.md" && "$force" != "1" ]]; then
    if [[ ! -f "$abs_target/CLAUDE.pre-pm-flow.md" ]]; then
      atomic_copy_file "$abs_target/CLAUDE.md" "$abs_target/CLAUDE.pre-pm-flow.md"
    fi
    render_template \
      "template/CLAUDE.md" \
      "$abs_target/CLAUDE.pm-flow.template.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
    merge_claude_rules \
      "$abs_target/CLAUDE.md" \
      "$abs_target/CLAUDE.pm-flow.template.md"
  else
    render_template \
      "template/CLAUDE.md" \
      "$abs_target/CLAUDE.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
  fi

  chmod +x "$flow_dir/pm_flow.sh"
  chmod +x "$flow_dir/net_exec.sh"
  chmod +x "$flow_dir/codex_pm_review.sh"
  chmod +x "$flow_dir/agent_exec.sh"

  touch "$project_dir/runs/.gitkeep"
  touch "$project_dir/sections/.gitkeep"
  write_project_key "$flow_dir/.project-key" "$project_key"

  if ! grep -q -- "- \`$project_key\`" "$flow_dir/projects.md"; then
    printf -- '- `%s` - installed project workspace for %s\n' "$project_key" "$project_name" >> "$flow_dir/projects.md"
  fi

  printf 'installed_pm_flow=%s\n' "$flow_dir"
  printf 'project_name=%s\n' "$project_name"
  printf 'project_key=%s\n' "$project_key"
  printf 'project_dir=%s\n' "$project_dir"

  # The shared scripts are refreshed for every workspace in this flow dir, but
  # only the selected workspace gets a refreshed contract and prompts. Say so,
  # because the others now run new code against older rules.
  local other_workspaces=()
  local candidate
  for candidate in "$flow_dir"/*(/N); do
    if [[ -f "$candidate/task_contract.md" && "$(basename "$candidate")" != "$project_key" ]]; then
      other_workspaces+=("$(basename "$candidate")")
    fi
  done
  if [[ "${#other_workspaces[@]}" -gt 0 ]]; then
    printf 'WARNING: %d other project workspace(s) share the upgraded scripts but keep their existing task_contract.md, start.md, and resume.md: %s\n' \
      "${#other_workspaces[@]}" "${(j:, :)other_workspaces}" >&2
    printf 'WARNING: rerun the installer with --project-key <key> for each one to bring its rules in line.\n' >&2
  fi
  if [[ -n "$REPO_RAW_BASE" ]]; then
    printf 'install_source=remote\n'
  else
    printf 'install_source=local\n'
  fi
  cleanup_template_cache
  trap - EXIT HUP INT TERM
}

main "$@"
