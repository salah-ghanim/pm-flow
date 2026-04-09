#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
DEFAULT_MISSION="achieve meaningful progress on the active project objective with explicit validation and controlled scope"
DEFAULT_BASELINE="TBD"

usage() {
  cat <<'EOF'
Usage:
  install.sh [target-repo] [--name <project-name>] [--mission <text>] [--baseline <text>] [--repo-raw-base <url>] [--force]

Installs the generic Claude PM flow template into the target repository.

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
  if [[ -n "${REPO_RAW_BASE:-}" ]]; then
    curl --fail --silent --show-error --location "${REPO_RAW_BASE%/}/$rel_path"
    return
  fi

  local local_path="$SCRIPT_DIR/$rel_path"
  [[ -f "$local_path" ]] || fail "template file not found: $local_path"
  /bin/cat "$local_path"
}

render_template() {
  local rel_path="$1"
  local dst="$2"
  local project_name="$3"
  local project_root="$4"
  local primary_mission="$5"
  local baseline_name="$6"
  local escaped_project_name escaped_project_root escaped_primary_mission escaped_baseline_name
  escaped_project_name="$(escape_sed_replacement "$project_name")"
  escaped_project_root="$(escape_sed_replacement "$project_root")"
  escaped_primary_mission="$(escape_sed_replacement "$primary_mission")"
  escaped_baseline_name="$(escape_sed_replacement "$baseline_name")"
  fetch_template "$rel_path" | sed \
    -e "s|{{PROJECT_NAME}}|$escaped_project_name|g" \
    -e "s|{{PROJECT_ROOT}}|$escaped_project_root|g" \
    -e "s|{{PRIMARY_MISSION}}|$escaped_primary_mission|g" \
    -e "s|{{CURRENT_BASELINE}}|$escaped_baseline_name|g" \
    > "$dst"
}

copy_template() {
  local rel_path="$1"
  local dst="$2"
  fetch_template "$rel_path" > "$dst"
}

main() {
  local target_repo="."
  if [[ $# -gt 0 && "${1:-}" != --* ]]; then
    target_repo="$1"
    shift || true
  fi

  local project_name=""
  local primary_mission="$DEFAULT_MISSION"
  local baseline_name="$DEFAULT_BASELINE"
  local repo_raw_base="${PM_FLOW_REPO_RAW_BASE:-}"
  local force="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift || fail "--name requires a value"
        project_name="${1:-}"
        [[ -n "$project_name" ]] || fail "--name requires a value"
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
  abs_target="$(cd "$target_repo" && pwd)"
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
  project_key="$(slugify "$(basename "$abs_target")")"
  local project_dir="$flow_dir/$project_key"
  local flow_exists="0"
  if [[ -d "$flow_dir" ]]; then
    flow_exists="1"
  fi

  if [[ -e "$project_dir" && "$force" != "1" ]]; then
    fail "target already has agentic/pm_flow/$project_key; rerun with --force if replacement is intended"
  fi

  mkdir -p "$flow_dir"
  if [[ "$force" == "1" && -d "$project_dir" ]]; then
    rm -rf "$project_dir"
  fi
  mkdir -p "$project_dir"
  mkdir -p "$project_dir/runs"
  mkdir -p "$project_dir/project_state"

  if [[ "$flow_exists" != "1" || "$force" == "1" ]]; then
    render_template \
      "template/agentic/pm_flow/README.md" \
      "$flow_dir/README.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name"
    copy_template "template/agentic/pm_flow/pm_flow.sh" "$flow_dir/pm_flow.sh"
    copy_template "template/agentic/pm_flow/net_exec.sh" "$flow_dir/net_exec.sh"
    copy_template "template/agentic/pm_flow/codex_pm_review.sh" "$flow_dir/codex_pm_review.sh"
    copy_template "template/agentic/pm_flow/local_env.sh.example" "$flow_dir/local_env.sh.example"
    render_template \
      "template/agentic/pm_flow/projects.md" \
      "$flow_dir/projects.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name"
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
    "$baseline_name"
  render_template \
    "template/agentic/pm_flow/project/project_state/plan.md" \
    "$project_dir/project_state/plan.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name"
  render_template \
    "template/agentic/pm_flow/project/project_state/start.md" \
    "$project_dir/project_state/start.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name"
  render_template \
    "template/agentic/pm_flow/project/project_state/resume.md" \
    "$project_dir/project_state/resume.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name"
  copy_template \
    "template/agentic/pm_flow/project/project_state/current_run.txt" \
    "$project_dir/project_state/current_run.txt"
  render_template \
    "template/agentic/pm_flow/project/task_contract.md" \
    "$project_dir/task_contract.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name"

  if [[ -f "$abs_target/CLAUDE.md" && "$force" != "1" ]]; then
    render_template \
      "template/CLAUDE.md" \
      "$abs_target/CLAUDE.pm-flow.template.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name"
  else
    render_template \
      "template/CLAUDE.md" \
      "$abs_target/CLAUDE.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name"
  fi

  chmod +x "$flow_dir/pm_flow.sh"
  chmod +x "$flow_dir/net_exec.sh"
  chmod +x "$flow_dir/codex_pm_review.sh"

  touch "$project_dir/runs/.gitkeep"

  if ! grep -q -- "- \`$project_key\`" "$flow_dir/projects.md"; then
    printf -- '- `%s` - installed project workspace for %s\n' "$project_key" "$project_name" >> "$flow_dir/projects.md"
  fi

  printf 'installed_pm_flow=%s\n' "$flow_dir"
  printf 'project_name=%s\n' "$project_name"
  printf 'project_key=%s\n' "$project_key"
  printf 'project_dir=%s\n' "$project_dir"
  if [[ -n "$REPO_RAW_BASE" ]]; then
    printf 'install_source=remote\n'
  else
    printf 'install_source=local\n'
  fi
}

main "$@"
