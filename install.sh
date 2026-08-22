#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
DEFAULT_MISSION="achieve meaningful progress on the active project objective with explicit validation and controlled scope"
DEFAULT_BASELINE="TBD"
TEMPLATE_CACHE_DIR=""

# Named once, so prefetching and installing can never disagree about what the
# template set contains.
ROLE_NAMES=(cpo pm developer consultant 10x_developer)
DOMAIN_NAMES=(generic saas prop-trading crypto-trading infrastructure migration distressed-tech)
TASK_NAMES=(
  consultant_panel_adjudication
  convergence_review
  portfolio_review
  section_scope
  section_review
  section_handoff
  section_rescue
  section_analysis
  developer_assignment
  project_decomposition
)

# A domain may replace the personas, the task prompts and the contract outright
# rather than only retitling roles, for work that does not resemble building a
# product at all. Listed explicitly rather than probed for: a remote install
# fetches by name and cannot ask a URL whether it exists.
OVERLAY_DOMAINS=(distressed-tech)

usage() {
  cat <<'EOF'
Usage:
  install.sh [target-repo] [--name <project-name>] [--project-key <key>] [--domain <domain>] [--mission <text>] [--baseline <text>] [--repo-raw-base <url>] [--add-project] [--force]

Installs the generic Claude PM flow template into the target repository.

Default reinstall behavior:
- refresh generic `.agentic/pm_flow/*` scripts and docs
- refresh per-project `task_contract.md`, `start.md`, and `resume.md`
- back up pre-section start/resume prompts once with a `.pre-sections.md` suffix
- preserve the project plan, section workspaces, generated registry, and run history
- preserve config.json (cli, model, and difficulty bindings per role)
- preserve each project's recorded domain unless --domain is given
- use `--force` only when a full project-template replacement is intended

Domains: generic (default), saas, prop-trading, crypto-trading, infrastructure,
migration. The domain is recorded per project in <project>/project.json, so one
flow directory can host projects of different kinds.

Use `--add-project` with `--project-key` to create a second project alongside
the existing ones. Naming a project that already exists is a plain reinstall of
that project and needs no extra flag.

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

# zsh runs an EXIT trap registered inside a function when that *function*
# returns, not when the shell exits. Registering this at the top level is what
# keeps the prefetched cache alive for the rest of the install.
trap cleanup_template_cache EXIT HUP INT TERM

prefetch_templates() {
  local template_paths=(
    "template/.agentic/pm_flow/README.md"
    "template/.agentic/pm_flow/pm_flow.sh"
    "template/.agentic/pm_flow/net_exec.sh"
    "template/.agentic/pm_flow/agent_exec.sh"
    "template/.agentic/pm_flow/fetch.sh"
    "template/.agentic/pm_flow/heartbeat.sh"
    "template/.agentic/pm_flow/driver.zsh"
    "template/.agentic/pm_flow/cost.py"
    "template/.agentic/pm_flow/watch.py"
    "template/.agentic/pm_flow/config.json"
    "template/.agentic/pm_flow/local_env.sh.example"
    "template/.agentic/pm_flow/projects.md"
    "template/.agentic/pm_flow/project/project_state/README.md"
    "template/.agentic/pm_flow/project/project_state/plan.md"
    "template/.agentic/pm_flow/project/project_state/start.md"
    "template/.agentic/pm_flow/project/project_state/resume.md"
    "template/.agentic/pm_flow/project/project_state/sections.md"
    "template/.agentic/pm_flow/project/project.json"
    "template/.agentic/pm_flow/project/task_contract.md"
    "template/CLAUDE.md"
    "MANIFEST"
  )
  local name
  for name in "${ROLE_NAMES[@]}"; do
    template_paths+=("template/.agentic/pm_flow/roles/$name.md")
  done
  for name in "${DOMAIN_NAMES[@]}"; do
    template_paths+=("template/.agentic/pm_flow/domains/$name.json")
  done
  for name in "${TASK_NAMES[@]}"; do
    template_paths+=("template/.agentic/pm_flow/tasks/$name.md")
  done
  local overlay
  for overlay in "${OVERLAY_DOMAINS[@]}"; do
    template_paths+=("template/.agentic/pm_flow/domains/$overlay/task_contract.md")
    for name in "${ROLE_NAMES[@]}"; do
      template_paths+=("template/.agentic/pm_flow/domains/$overlay/roles/$name.md")
    done
    for name in "${TASK_NAMES[@]}"; do
      template_paths+=("template/.agentic/pm_flow/domains/$overlay/tasks/$name.md")
    done
  done

  # Everything else the manifest ships. The lists above are kept because they
  # decide what gets *rendered* and what a reinstall preserves, but they are no
  # longer the definition of what exists - the manifest is, and it is generated
  # from the template rather than maintained by hand.
  local manifest_raw
  if [[ -n "${REPO_RAW_BASE:-}" ]]; then
    manifest_raw="$(curl --fail --silent --show-error --location \
      "${REPO_RAW_BASE%/}/MANIFEST" 2>/dev/null || printf '')"
  else
    manifest_raw="$(/bin/cat "$SCRIPT_DIR/MANIFEST" 2>/dev/null || printf '')"
  fi
  if [[ -n "$manifest_raw" ]]; then
    # The manifest is line-oriented, so awk reads it directly: `root <dir>` in
    # the header, then `<class> <exec> <sha256> <path>` per file.
    local extra
    for extra in ${(f)"$(printf '%s' "$manifest_raw" | awk '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == "root" { root = $2; next }
      $1 == "version" { next }
      $1 == "engine" { print root "/" $4 }
    ' 2>/dev/null)"}; do
      [[ -n "$extra" ]] || continue
      # `:-` matters: under `set -u` a subscript search that finds nothing is an
      # unset parameter, not an empty string, and would abort the install.
      if [[ -z "${template_paths[(r)$extra]:-}" ]]; then
        template_paths+=("$extra")
      fi
    done
  fi

  TEMPLATE_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-install.XXXXXX")"
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

# Ship every `engine` file the manifest names that is not already in place or is
# out of date. Reads the manifest through fetch_template, so a remote install
# works the same way a local one does.
# pm-flow used to install to `agentic/`. It installs to `.agentic/` now, for the
# same reason `.idea` and `.vscode` are hidden: the flow is workspace machinery,
# not part of the product, and it should not be the first thing in a listing of
# somebody's repository.
#
# An existing install is moved rather than orphaned. Doing nothing would leave a
# repository with two flow directories, the old one still holding the project
# state and the new one empty - and the old one still on PATH in every persona,
# task file and permission rule that names it.
migrate_legacy_flow_dir() {
  local repo_root="$1"
  local legacy="$repo_root/agentic"
  local current="$repo_root/.agentic"

  [[ -d "$legacy/pm_flow" ]] || return 0
  if [[ -d "$current/pm_flow" ]]; then
    printf 'WARNING: both agentic/ and .agentic/ exist; leaving agentic/ alone.\n' >&2
    printf 'WARNING: move any project workspaces you still want by hand, then delete it.\n' >&2
    return 0
  fi

  mkdir -p "$(dirname "$current")"
  # `git mv` where possible, so the rename is recorded as a rename and the
  # project history survives it.
  if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
     git -C "$repo_root" ls-files --error-unmatch agentic >/dev/null 2>&1; then
    git -C "$repo_root" mv agentic .agentic >/dev/null 2>&1 || mv "$legacy" "$current"
  else
    mv "$legacy" "$current"
  fi

  [[ -d "$current/pm_flow" ]] || return 0

  # Moving the directory is not enough. Project state records repo-relative
  # paths - each section's run_path.txt, its owned paths, its dependency
  # handoffs - and every one of them still names the old location. A section
  # whose run directory cannot be found is a section the flow refuses to act on,
  # so a migration that skipped this would leave a project that looks intact and
  # will not move.
  python3 - "$current" <<'PY_MIGRATE' || true
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
# A path segment, never the word in prose and never an already-migrated path.
pattern = re.compile(r"(?<![\w.-])agentic/")
rewritten = 0
for path in root.rglob("*"):
    if not path.is_file():
        continue
    try:
        text = path.read_text()
    except (OSError, UnicodeDecodeError):
        continue
    updated = pattern.sub(".agentic/", text)
    if updated != text:
        path.write_text(updated)
        rewritten += 1
if rewritten:
    print(f"migrated_paths={rewritten}")
PY_MIGRATE

  printf 'migrated=agentic -> .agentic\n'
  printf 'NOTE: paths that name agentic/ elsewhere - CI, editor config, your own\n' >&2
  printf 'NOTE: scripts - need updating; the flow'"'"'s own files were rewritten.\n' >&2
}

sync_manifest_engine() {
  local flow_dir="$1"
  local repo_root="$2"
  local manifest_json rel manifest_root
  manifest_json="$(fetch_template "MANIFEST" 2>/dev/null || printf '')"
  [[ -n "$manifest_json" ]] || return 0
  # The manifest names the directory its paths are relative to, so this does not
  # have to assume the layout.
  manifest_root="$(printf '%s' "$manifest_json" | awk '$1 == "root" { print $2; exit }')"
  [[ -n "$manifest_root" ]] || manifest_root="template"

  local -a wanted
  wanted=(${(f)"$(printf '%s' "$manifest_json" | awk '$1 == "engine" { print $4 }')"})

  for rel in "${wanted[@]}"; do
    [[ -n "$rel" ]] || continue
    copy_template "$manifest_root/$rel" "$repo_root/$rel"
  done

  # Stamp the install so `pm_flow.sh version` and `upgrade` have a baseline to
  # compare against. Without it an upgrade cannot tell a shipped change from
  # something you edited.
  if [[ -f "$flow_dir/upgrade.py" ]]; then
    printf '%s' "$manifest_json" > "$flow_dir/.pm-flow-new-MANIFEST"
    python3 "$flow_dir/upgrade.py" record \
      --new "$flow_dir/.pm-flow-new-MANIFEST" >/dev/null 2>&1 || true
    rm -f "$flow_dir/.pm-flow-new-MANIFEST"
  fi
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
  local add_project="$5"
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
    # A flow directory hosts several projects, so naming a sibling workspace is a
    # reinstall of that sibling rather than a replacement of this one's identity.
    # Only creating a workspace that does not exist yet needs stated intent.
    if [[ -n "$persisted_key" && "$persisted_key" != "$normalized_requested" && "$force" != "1" ]]; then
      if [[ ! -d "$flow_dir/$normalized_requested" && "$add_project" != "1" ]]; then
        fail "no project '$normalized_requested' under $flow_dir; pass --add-project to create it alongside '$persisted_key', or --force to replace the install identity"
      fi
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
  local domain_explicit="0"
  local add_project="0"
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
        (( ${DOMAIN_NAMES[(Ie)$domain]} )) || \
          fail "unknown --domain '$domain'; choose ${(j:, :)DOMAIN_NAMES}"
        domain_explicit="1"
        ;;
      --repo-raw-base)
        shift || fail "--repo-raw-base requires a value"
        repo_raw_base="${1:-}"
        [[ -n "$repo_raw_base" ]] || fail "--repo-raw-base requires a value"
        ;;
      --add-project)
        add_project="1"
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

  # Before anything is resolved or written: an install that still lives at the
  # old path is moved, so the project key, domain and history below are read
  # from the workspace that already exists rather than from an empty one.
  migrate_legacy_flow_dir "$abs_target"

  local flow_dir="$abs_target/.agentic/pm_flow"
  local project_key
  project_key="$(resolve_install_project_key \
    "$flow_dir" \
    "$requested_project_key" \
    "$(slugify "$(basename "$abs_target")")" \
    "$force" \
    "$add_project")"
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
    "template/.agentic/pm_flow/README.md" \
    "$flow_dir/README.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  copy_template "template/.agentic/pm_flow/pm_flow.sh" "$flow_dir/pm_flow.sh"
  copy_template "template/.agentic/pm_flow/net_exec.sh" "$flow_dir/net_exec.sh"
  copy_template "template/.agentic/pm_flow/agent_exec.sh" "$flow_dir/agent_exec.sh"
  copy_template "template/.agentic/pm_flow/fetch.sh" "$flow_dir/fetch.sh"
  copy_template "template/.agentic/pm_flow/heartbeat.sh" "$flow_dir/heartbeat.sh"
  copy_template "template/.agentic/pm_flow/driver.zsh" "$flow_dir/driver.zsh"
  # driver.zsh calls cost.py on every dispatch and `status` reads it, so an
  # install without it reports an error where the spend should be.
  copy_template "template/.agentic/pm_flow/cost.py" "$flow_dir/cost.py"
  copy_template "template/.agentic/pm_flow/watch.py" "$flow_dir/watch.py"
  local template_name
  for template_name in "${ROLE_NAMES[@]}"; do
    copy_template "template/.agentic/pm_flow/roles/$template_name.md" "$flow_dir/roles/$template_name.md"
  done
  for template_name in "${DOMAIN_NAMES[@]}"; do
    copy_template "template/.agentic/pm_flow/domains/$template_name.json" "$flow_dir/domains/$template_name.json"
  done
  for template_name in "${TASK_NAMES[@]}"; do
    copy_template "template/.agentic/pm_flow/tasks/$template_name.md" "$flow_dir/tasks/$template_name.md"
  done
  local overlay_domain
  for overlay_domain in "${OVERLAY_DOMAINS[@]}"; do
    for template_name in "${ROLE_NAMES[@]}"; do
      copy_template \
        "template/.agentic/pm_flow/domains/$overlay_domain/roles/$template_name.md" \
        "$flow_dir/domains/$overlay_domain/roles/$template_name.md"
    done
    for template_name in "${TASK_NAMES[@]}"; do
      copy_template \
        "template/.agentic/pm_flow/domains/$overlay_domain/tasks/$template_name.md" \
        "$flow_dir/domains/$overlay_domain/tasks/$template_name.md"
    done
  done
  # config.json carries the operator's cli/model/difficulty choices, so a
  # reinstall must never overwrite it.
  if [[ ! -f "$flow_dir/config.json" || "$force" == "1" ]]; then
    fetch_template "template/.agentic/pm_flow/config.json" \
      | sed -e "s|{{DOMAIN}}|$(escape_sed_replacement "$domain")|g" > "$flow_dir/.config.json.tmp"
    mv "$flow_dir/.config.json.tmp" "$flow_dir/config.json"
  fi
  copy_template "template/.agentic/pm_flow/local_env.sh.example" "$flow_dir/local_env.sh.example"
  if [[ ! -f "$flow_dir/projects.md" || "$force" == "1" ]]; then
    render_template \
      "template/.agentic/pm_flow/projects.md" \
      "$flow_dir/projects.md" \
      "$project_name" \
      "$abs_target" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
  fi

  if [[ ! -f "$flow_dir/pm_flow.sh" || ! -f "$flow_dir/net_exec.sh" || ! -f "$flow_dir/projects.md" ]]; then
    fail ".agentic/pm_flow exists but is missing required generic files; rerun with --force to repair"
  fi

  render_template \
    "template/.agentic/pm_flow/project/project_state/README.md" \
    "$project_dir/project_state/README.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  if [[ ! -f "$project_dir/project_state/plan.md" || "$force" == "1" ]]; then
    render_template \
      "template/.agentic/pm_flow/project/project_state/plan.md" \
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
      "^# Starting "
    backup_pre_section_prompt \
      "$project_dir/project_state/resume.md" \
      "^# Resuming "
  fi
  render_template \
    "template/.agentic/pm_flow/project/project_state/start.md" \
    "$project_dir/project_state/start.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  render_template \
    "template/.agentic/pm_flow/project/project_state/resume.md" \
    "$project_dir/project_state/resume.md" \
    "$project_name" \
    "$abs_target" \
    "$primary_mission" \
    "$baseline_name" \
    "$project_key"
  if [[ ! -f "$project_dir/project_state/sections.md" || "$force" == "1" ]]; then
    copy_template \
      "template/.agentic/pm_flow/project/project_state/sections.md" \
      "$project_dir/project_state/sections.md"
  fi
  # The domain belongs to the project, not the flow directory, so one repository
  # can run an infrastructure project and a migration project side by side. An
  # existing project keeps its recorded domain unless --domain says otherwise.
  if [[ ! -f "$project_dir/project.json" || "$domain_explicit" == "1" || "$force" == "1" ]]; then
    fetch_template "template/.agentic/pm_flow/project/project.json" \
      | sed -e "s|{{DOMAIN}}|$(escape_sed_replacement "$domain")|g" > "$project_dir/.project.json.tmp"
    mv "$project_dir/.project.json.tmp" "$project_dir/project.json"
  fi

  # The contract is the project's rules, and a domain that replaces the roles
  # replaces the rules with them. Read the effective domain back off disk: a
  # reinstall without --domain keeps whatever the project recorded, and the
  # contract has to follow the project rather than this invocation's default.
  local effective_domain="$domain"
  if [[ "$domain_explicit" != "1" && -f "$project_dir/project.json" ]]; then
    local recorded_domain
    recorded_domain="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("domain", "") or "")
except Exception:
    print("")' "$project_dir/project.json")"
    [[ -z "$recorded_domain" ]] || effective_domain="$recorded_domain"
  fi
  local contract_template="template/.agentic/pm_flow/project/task_contract.md"
  if (( ${OVERLAY_DOMAINS[(Ie)$effective_domain]} )); then
    contract_template="template/.agentic/pm_flow/domains/$effective_domain/task_contract.md"
  fi

  render_template \
    "$contract_template" \
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

  # Everything the manifest ships that the hand-written lists above do not.
  #
  # Those lists were wrong the moment anything was added to the template: four
  # modules shipped, the installer did not know about them, and a stock install
  # got a driver that called files which were not there. The manifest is
  # generated from the template, so adding a file is all it takes to ship it.
  #
  # This runs after the explicit copies rather than replacing them, so the
  # careful preservation logic above still decides what a reinstall keeps. Only
  # `engine` files are synced here; `seed` and `project` files are yours.
  sync_manifest_engine "$flow_dir" "$abs_target"

  # Derived from the file rather than listed by hand. The list this replaces
  # named ten paths and had to be edited every time one was added, which is a
  # rule nobody remembers: access_hook.sh shipped unexecutable and its hook
  # silently did nothing. A file that declares an interpreter is meant to be
  # run, and that declaration is already in the file.
  local candidate
  for candidate in "$flow_dir"/*(.N); do
    [[ "$(/usr/bin/head -c 2 "$candidate" 2>/dev/null)" == "#!" ]] || continue
    chmod +x "$candidate"
  done

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
