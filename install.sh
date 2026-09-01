#!/bin/zsh -f
set -euo pipefail

# install.sh - create the project data a repository needs, and nothing else.
#
# This script used to ship the engine: it copied pm_flow.sh, driver.zsh,
# agent_exec.sh, the personas, the tasks and the domains into every repository,
# recorded a manifest of what it had copied, and grew drift detection and an
# upgrade protocol to manage those copies afterwards. All of that machinery
# existed for one reason - N copies of the engine scattered across N
# repositories - and none of it is needed now that the engine is an installed
# Python package resolved through `pm-flow`.
#
# So what is left is the half that was always the repository's own: config.json,
# the project selector, one or more project workspaces, the local override hook,
# and the repository's agent instructions. Every one of those is mutable data
# that belongs to the project and is never replaced by an upgrade.
#
# Run it against a repository that still holds a copied engine and it migrates:
# the project data is kept exactly as it stands, and the copied engine, the
# packaged defaults and the install record are removed.

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
DEFAULT_MISSION="achieve meaningful progress on the active project objective with explicit validation and controlled scope"
DEFAULT_BASELINE="TBD"
TEMPLATE_CACHE_DIR=""

# Named once, so prefetching and installing can never disagree about what the
# template set contains. Only the domains are still listed: the personas and the
# task prompts ship with the package and are never written into a repository.
DOMAIN_NAMES=(generic saas prop-trading crypto-trading infrastructure migration distressed-tech)

# A domain may replace the project's contract outright rather than only
# retitling roles, for work that does not resemble building a product at all.
# Listed explicitly rather than probed for: a remote install fetches by name and
# cannot ask a URL whether it exists.
OVERLAY_DOMAINS=(distressed-tech)

# What a copied install left in the flow directory. These are the names the old
# installer wrote there, and the whole of what migration removes: everything
# else under .agentic/pm_flow is the repository's own.
#
# Listed by name rather than derived from the template, because a remote install
# cannot list a URL, and because a name that stops being shipped still has to be
# cleaned out of repositories that received it.
COPIED_ENGINE_FILES=(
  pm_flow.sh
  net_exec.sh
  agent_exec.sh
  access_hook.sh
  fetch.sh
  heartbeat.sh
  driver.zsh
  catalog.py
  compare.py
  cost.py
  store.py
  telemetry.py
  topology.py
  trace_export.py
  export.py
  prompt_quality.py
  watch.py
  upgrade.py
  requirements-telemetry.txt
  README.md
  run_detach.zsh
  artifact_quality.md
)

# Packaged defaults and the install record. `roles`, `domains` and `tasks` here
# are the *flow-level* copies of packaged files; a project workspace's own
# `roles/` directory is an overlay the repository wrote and is never touched.
COPIED_ENGINE_DIRS=(
  roles
  domains
  tasks
  topologies
  project
  tests
  __pycache__
  .pm-flow
  cards
  schemas
)

usage() {
  cat <<'EOF'
Usage:
  install.sh [target-repo] [--name <project-name>] [--project-key <key>] [--domain <domain>] [--mission <text>] [--baseline <text>] [--repo-raw-base <url>] [--add-project] [--force]

Creates the pm-flow project data in the target repository. The engine itself is
not copied: install `pm-flow` into the repository's virtual environment and run
the `pm-flow` command.

  python3 -m venv .venv && .venv/bin/pip install pm-flow
  ./install.sh . --name "My Repo"
  .venv/bin/pm-flow status

Default reinstall behavior:
- refresh per-project `task_contract.md`, `start.md`, and `resume.md`
- back up pre-section start/resume prompts once with a `.pre-sections.md` suffix
- preserve the project plan, section workspaces, generated registry, run history,
  the store, and any project-local persona overlay
- preserve config.json (cli, model, and difficulty bindings per role)
- preserve each project's recorded domain unless --domain is given
- remove any copied engine left by an older install
- use `--force` only when a full project-template replacement is intended

Domains: generic (default), saas, prop-trading, crypto-trading, infrastructure,
migration, distressed-tech. The domain is recorded per project in
<project>/project.json, so one flow directory can host projects of different
kinds.

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

# Everything is fetched before anything is written, so a template that cannot be
# reached is an install that never started rather than one that stopped halfway
# through a repository's own files.
prefetch_templates() {
  local template_paths=(
    "template/.agentic/pm_flow/.gitignore"
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
    # Both instructions files are rendered, so the manifest classes them `seed`
    # and the manifest-derived list below - which only carries `engine` - will
    # not add them. They are named here or the render cannot find them.
    "template/AGENTS.md"
    "template/CLAUDE.md"
  )
  local overlay
  for overlay in "${OVERLAY_DOMAINS[@]}"; do
    template_paths+=("template/.agentic/pm_flow/domains/$overlay/task_contract.md")
  done

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

# Take the copied engine out of a repository that received one.
#
# Only the names an old install wrote at the top of the flow directory are
# considered, and only at that level: a project workspace is never entered. That
# matters for `roles/`, which at the flow level is a copy of the packaged
# personas and inside a workspace is the repository's own overlay - the one
# thing customisation now depends on.
#
# A persisted selector or registry is authoritative when one exists. Older
# multi-workspace installs can predate both, though, so in that one case the
# structural workspace scan shared with project-key resolution is the only
# record of which directories belong to the repository.
discover_project_workspaces() {
  local flow_dir="$1"
  [[ -d "$flow_dir" ]] || return 0

  local candidate
  for candidate in "$flow_dir"/*(/N); do
    if [[ -f "$candidate/task_contract.md" && -d "$candidate/project_state" ]]; then
      printf '%s\n' "$(basename "$candidate")"
    fi
  done
}

remove_copied_engine() {
  local flow_dir="$1"
  local selected_key="$2"
  [[ -d "$flow_dir" ]] || return 0

  local -a project_keys
  local repository_named_projects=0
  project_keys=("$selected_key")
  if [[ -f "$flow_dir/.project-key" ]]; then
    local persisted
    persisted="$(/usr/bin/head -n 1 "$flow_dir/.project-key" | tr -d '\r')"
    if [[ -n "$persisted" ]]; then
      project_keys+=("$persisted")
      repository_named_projects=1
    fi
  fi
  if [[ -f "$flow_dir/projects.md" ]]; then
    local listed
    for listed in ${(f)"$(sed -n 's/^- `\([^`]*\)`.*/\1/p' "$flow_dir/projects.md")"}; do
      if [[ -n "$listed" ]]; then
        project_keys+=("$listed")
        repository_named_projects=1
      fi
    done
  fi
  if (( repository_named_projects == 0 )); then
    local discovered
    for discovered in ${(f)"$(discover_project_workspaces "$flow_dir")"}; do
      [[ -n "$discovered" ]] && project_keys+=("$discovered")
    done
  fi

  local removed=0
  local name target
  for name in "${COPIED_ENGINE_FILES[@]}"; do
    target="$flow_dir/$name"
    [[ -f "$target" || -L "$target" ]] || continue
    rm -f -- "$target"
    (( removed += 1 ))
  done
  for name in "${COPIED_ENGINE_DIRS[@]}"; do
    target="$flow_dir/$name"
    [[ -d "$target" ]] || continue
    if (( ${project_keys[(Ie)$name]} )); then
      printf 'WARNING: %s is a named project workspace; leaving it alone.\n' \
        "$target" >&2
      continue
    fi
    rm -rf -- "$target"
    (( removed += 1 ))
  done
  # Python bytecode the copied modules left behind, wherever it landed.
  find "$flow_dir" -type d -name __pycache__ -prune -exec rm -rf -- {} + 2>/dev/null || true

  (( removed == 0 )) || printf 'removed_copied_engine=%d\n' "$removed"
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
    local candidates=("${(@f)$(discover_project_workspaces "$flow_dir")}")
    candidates=("${(@)candidates:#}")
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

# Replace pm-flow's managed block inside a file the repository also owns,
# leaving everything outside the markers exactly as it was.
#
# Named for what it does rather than for the file it used to be the only caller
# of: the body was already file-neutral, and there are two instructions files
# now. A second merger would be a second set of marker rules to keep in step.
merge_managed_block() {
  local target_path="$1"
  local rendered_block_path="$2"
  command -v python3 >/dev/null 2>&1 || \
    fail "python3 is required to merge the pm-flow managed block into $target_path"
  python3 - "$target_path" "$rendered_block_path" <<'PY'
from pathlib import Path
import os
import sys

target = Path(sys.argv[1])
rendered = Path(sys.argv[2]).read_text().strip()
begin = "<!-- pm-flow:begin -->"
end = "<!-- pm-flow:end -->"
if begin not in rendered or end not in rendered:
    raise SystemExit(f"rendered block for {target.name} is missing managed-block markers")

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

# One instructions file, installed the same way whatever it is called.
#
# `AGENTS.md` is the file agents look for and carries the router and the
# invariants in full; `CLAUDE.md` is a managed pointer that imports it. Both are
# rendered from a template, both may already exist in the repository, and both
# have to survive that - so this is one procedure rather than two that drift.
#
# Surviving means: back the file up once, then merge the managed block into it
# in place. Whatever the repository already told its agents is still there,
# outside the markers, and a reinstall replaces only what pm-flow wrote.
install_instructions_file() {
  local name="$1"
  local repo_root="$2"
  local force="$3"
  local project_name="$4"
  local primary_mission="$5"
  local baseline_name="$6"
  local project_key="$7"
  local target="$repo_root/$name"
  local stem="${name%.md}"
  local rendered_block="$TEMPLATE_CACHE_DIR/rendered-instructions/$name"

  if [[ -f "$target" && "$force" != "1" ]]; then
    if [[ ! -f "$repo_root/$stem.pre-pm-flow.md" ]]; then
      atomic_copy_file "$target" "$repo_root/$stem.pre-pm-flow.md"
    fi
    render_template \
      "template/$name" \
      "$rendered_block" \
      "$project_name" \
      "$repo_root" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
    merge_managed_block \
      "$target" \
      "$rendered_block"
  else
    render_template \
      "template/$name" \
      "$target" \
      "$project_name" \
      "$repo_root" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
  fi
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

  prefetch_templates

  mkdir -p "$flow_dir"

  # The second half of the migration: the project key, the domain and the
  # history were all read above from the install as it stands, so the copied
  # engine can now go. Nothing below writes an engine file, so a fresh install
  # and a migrated one end in exactly the same shape.
  remove_copied_engine "$flow_dir" "$project_key"

  if [[ "$force" == "1" && -d "$project_dir" ]]; then
    rm -rf "$project_dir"
  fi
  mkdir -p "$project_dir"
  mkdir -p "$project_dir/runs"
  mkdir -p "$project_dir/project_state"
  mkdir -p "$project_dir/sections"

  # config.json carries the operator's cli/model/difficulty choices, so a
  # reinstall must never overwrite it.
  if [[ ! -f "$flow_dir/config.json" || "$force" == "1" ]]; then
    fetch_template "template/.agentic/pm_flow/config.json" \
      | sed -e "s|{{DOMAIN}}|$(escape_sed_replacement "$domain")|g" > "$flow_dir/.config.json.tmp"
    mv "$flow_dir/.config.json.tmp" "$flow_dir/config.json"
  fi
  # What the flow writes while working is not what you commit. Shipped into the
  # flow directory so a repository that installs pm-flow needs no edits of its
  # own to stay clean.
  copy_template "template/.agentic/pm_flow/.gitignore" "$flow_dir/.gitignore"
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

  # AGENTS.md first, because CLAUDE.md imports it and a pointer installed
  # before its target is a broken link for as long as the install takes.
  local instructions_file
  for instructions_file in AGENTS.md CLAUDE.md; do
    install_instructions_file \
      "$instructions_file" \
      "$abs_target" \
      "$force" \
      "$project_name" \
      "$primary_mission" \
      "$baseline_name" \
      "$project_key"
  done

  touch "$project_dir/runs/.gitkeep"
  touch "$project_dir/sections/.gitkeep"
  write_project_key "$flow_dir/.project-key" "$project_key"

  local -a registry_keys
  registry_keys=("$project_key" "${(@f)$(discover_project_workspaces "$flow_dir")}")
  local registry_key
  for registry_key in "${registry_keys[@]}"; do
    [[ -n "$registry_key" ]] || continue
    if ! grep -q -- "- \`$registry_key\`" "$flow_dir/projects.md"; then
      printf -- '- `%s` - installed project workspace for %s\n' \
        "$registry_key" "$project_name" >> "$flow_dir/projects.md"
    fi
  done

  printf 'installed_pm_flow=%s\n' "$flow_dir"
  printf 'project_name=%s\n' "$project_name"
  printf 'project_key=%s\n' "$project_key"
  printf 'project_dir=%s\n' "$project_dir"

  if [[ -n "$REPO_RAW_BASE" ]]; then
    printf 'install_source=remote\n'
  else
    printf 'install_source=local\n'
  fi
  cleanup_template_cache
  trap - EXIT HUP INT TERM
}

main "$@"
