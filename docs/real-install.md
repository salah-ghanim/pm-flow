# Real-install operator runbook

Extract the script below from a pm-flow checkout and run it from that checkout.
Replace `GOLDEN_GRID_PROJECT_KEY` with the workspace selected for the migration;
all reported golden-grid values remain placeholders until the operator transcript
is captured in the next task.

```zsh
cd /path/to/pm-flow-checkout
RUNBOOK="$(mktemp "${TMPDIR:-/tmp}/pm-flow-real-install-runbook.XXXXXX")"
sed -n '/^<!-- runbook:begin -->/,/^<!-- runbook:end -->/p' docs/real-install.md | sed '1d;$d;/^```/d' > "$RUNBOOK"
chmod +x "$RUNBOOK"
"$RUNBOOK" all \
  --repo /Users/salah/code/personal/golden-grid \
  --project-key GOLDEN_GRID_PROJECT_KEY \
  --name "Golden Grid"
```

Keep the printed backup path and transcript path. Do not run `migrate` by itself:
the script refuses it until the same output directory contains the manifest from
a verified `backup` phase.

<!-- runbook:begin -->
```zsh
#!/bin/zsh -f
set -uo pipefail

usage() {
  print -u2 'usage: real-install-runbook.zsh <survey|backup|migrate|verify|all> --repo <path> [--project-key <key>] [--name <name>] [--install-sh <path>] [--pm-flow <path>] [--backup-root <path>] [--out <path>]'
  return 2
}

fail() {
  print -u2 -r -- "ERROR: $*"
  return 1
}

print_command() {
  print -n -r -- '$'
  printf ' %q' "$@"
  print
}

run_logged() {
  print_command "$@"
  "$@"
  local code=$?
  print -r -- "exit=$code"
  return "$code"
}

run_captured() {
  print_command "$@"
  REPLY="$("$@" 2>&1)"
  local code=$?
  [[ -z "$REPLY" ]] || print -r -- "$REPLY"
  print -r -- "exit=$code"
  return "$code"
}

check_result() {
  local description="$1" result="$2" detail="${3:-}"
  print -r -- '$ check' "$description"
  if [[ "$result" == yes ]]; then
    print 'exit=0'
    return 0
  fi
  [[ -z "$detail" ]] || print -u2 -r -- "ERROR: $detail"
  print 'exit=1'
  return 1
}

install_array_names() {
  local array_name="$1"
  sed -n "/^${array_name}=(/,/^)/p" "$install_sh" | \
    sed '1d;$d;s/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d'
}

discover_workspaces() {
  local flow="$1" candidate
  [[ -d "$flow" ]] || return 0
  for candidate in "$flow"/*(/N); do
    if [[ -f "$candidate/task_contract.md" && -d "$candidate/project_state" ]]; then
      print -r -- "$(basename "$candidate")"
    fi
  done
}

write_project_manifest() {
  local flow="$1" destination="$2"
  shift 2
  python3 - "$flow" "$@" > "$destination" <<'PY_PROJECT_DIGEST'
import hashlib
import sys
from pathlib import Path

flow = Path(sys.argv[1])
for key in sorted(sys.argv[2:]):
    workspace = flow / key
    roots = [
        workspace / "project.json",
        workspace / "project_state" / "plan.md",
        workspace / "project_state" / "sections.md",
        workspace / "roles",
        workspace / "sections",
        workspace / "runs",
        workspace / "task_contract.md",
        workspace / "project_state" / "start.md",
        workspace / "project_state" / "resume.md",
        workspace / "project_state" / "start.pre-sections.md",
        workspace / "project_state" / "resume.pre-sections.md",
    ]
    paths = []
    for root in roots:
        if root.is_dir():
            paths.extend(root.rglob("*"))
        elif root.exists():
            paths.append(root)
    for path in sorted(set(paths)):
        if not path.is_file() or path.suffix == ".pyc" or "__pycache__" in path.parts:
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(f"{digest}  {path.relative_to(flow)}")
PY_PROJECT_DIGEST
}

write_full_manifest() {
  local base="$1" destination="$2"
  python3 - "$base" > "$destination" <<'PY_FULL_DIGEST'
import hashlib
import sys
from pathlib import Path

base = Path(sys.argv[1])
for path in sorted(base.rglob("*")):
    if not path.is_file():
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"{digest}  {path.relative_to(base)}")
PY_FULL_DIGEST
}

load_engine_arrays() {
  COPIED_ENGINE_FILES=("${(@f)$(install_array_names COPIED_ENGINE_FILES)}")
  COPIED_ENGINE_DIRS=("${(@f)$(install_array_names COPIED_ENGINE_DIRS)}")
  (( ${#COPIED_ENGINE_FILES[@]} > 0 )) || fail "COPIED_ENGINE_FILES could not be parsed from $install_sh"
  (( ${#COPIED_ENGINE_DIRS[@]} > 0 )) || fail "COPIED_ENGINE_DIRS could not be parsed from $install_sh"
}

engine_names_present() {
  local flow="$1"
  shift
  local -a workspace_keys=("$@") present=()
  local name
  for name in "${COPIED_ENGINE_FILES[@]}"; do
    [[ -f "$flow/$name" || -L "$flow/$name" ]] && present+=("$name")
  done
  for name in "${COPIED_ENGINE_DIRS[@]}"; do
    (( ${workspace_keys[(Ie)$name]} )) && continue
    [[ -d "$flow/$name" ]] && present+=("$name")
  done
  print -r -- "${(j: :)present}"
}

phase_header() {
  print -r -- "=== phase: $1 ==="
}

survey_phase() {
  phase_header survey
  load_engine_arrays || return 1

  run_captured git --no-optional-locks -C "$repo" rev-parse --is-inside-work-tree
  local git_code=$? git_output="$REPLY" git_worktree="$REPLY"
  [[ "$git_worktree" == true ]] || git_worktree="${git_output:-false}"
  print -r -- "git_worktree=$git_worktree"

  run_captured git --no-optional-locks -C "$repo" ls-files --error-unmatch agentic
  local tracked_code=$? agentic_tracked=no
  (( tracked_code == 0 )) && agentic_tracked=yes
  print -r -- "agentic_tracked=$agentic_tracked"

  local legacy="$repo/agentic/pm_flow" current="$repo/.agentic/pm_flow" flow
  if [[ -d "$legacy" && -d "$current" ]]; then
    print -u2 'WARNING: both agentic/ and .agentic/ exist; leaving agentic/ alone.'
    print -u2 'WARNING: move any project workspaces you still want by hand, then delete it.'
    return 1
  elif [[ -d "$legacy" ]]; then
    flow="$legacy"
    print 'flow_dir=agentic/pm_flow'
  elif [[ -d "$current" ]]; then
    flow="$current"
    print 'flow_dir=.agentic/pm_flow'
  else
    fail "no agentic/pm_flow or .agentic/pm_flow directory exists under $repo"
    return 1
  fi

  local -a workspace_keys=("${(@f)$(discover_workspaces "$flow")}")
  workspace_keys=("${(@)workspace_keys:#}")
  print -r -- "workspaces=${(j: :)workspace_keys}"
  print -r -- "workspace_count=${#workspace_keys[@]}"
  [[ -f "$flow/.project-key" ]] && print 'project_key_file=present' || print 'project_key_file=absent'
  [[ -f "$flow/projects.md" ]] && print 'projects_md=present' || print 'projects_md=absent'

  local copied collision= name key
  copied="$(engine_names_present "$flow" "${workspace_keys[@]}")"
  print -r -- "copied_engine_present=$copied"
  local -a collisions=()
  for key in "${workspace_keys[@]}"; do
    for name in "${COPIED_ENGINE_DIRS[@]}"; do
      [[ "$key" == "$name" ]] && collisions+=("$key")
    done
  done
  print -r -- "collision=${(j: :)collisions}"

  local workspace ledger stats rows total empty_rows
  for key in "${workspace_keys[@]}"; do
    workspace="$flow/$key"
    ledger="$workspace/runs/cost_ledger.tsv"
    if [[ -f "$ledger" ]]; then
      stats="$(awk -F '\t' 'NF >= 5 { count += 1; total += $5 } NF < 6 || $6 == "" { empty += 1 } END { printf "%d\t%.4f\t%d", count, total, empty }' "$ledger")"
      rows="${stats%%$'\t'*}"
      stats="${stats#*$'\t'}"
      total="${stats%%$'\t'*}"
      empty_rows="${stats#*$'\t'}"
      print -r -- "workspace=$key ledger=present rows=$rows total=$total empty_response_rows=$empty_rows"
    else
      print -r -- "workspace=$key ledger=absent rows=0 total=0.0000 empty_response_rows=0"
    fi
  done

  local pip_path="${pm_flow:h}/pip" version_output version
  if [[ -x "$pip_path" ]]; then
    run_captured "$pip_path" show pm-flow
    local pip_code=$?
    version_output="$REPLY"
    if (( pip_code == 0 )); then
      version="$(print -r -- "$version_output" | sed -n 's/^Version:[[:space:]]*//p' | head -n 1)"
      print -r -- "pm_flow_version=${version:-absent}"
    else
      print 'pm_flow_version=absent'
    fi
  else
    print 'pm_flow_version=absent'
  fi

  print_command python3 project-data-manifest "$flow" "$survey_manifest"
  write_project_manifest "$flow" "$survey_manifest" "${workspace_keys[@]}"
  local manifest_code=$?
  print -r -- "exit=$manifest_code"
  (( manifest_code == 0 )) || return "$manifest_code"
  print -rl -- "${workspace_keys[@]}" > "$survey_workspaces"
  check_result 'survey manifest is non-empty' "$([[ -s "$survey_manifest" ]] && print yes || print no)" \
    "survey manifest is empty: $survey_manifest" || return 1

  # The exit codes are evidence about whether install.sh can take its git-mv path;
  # the printed rev-parse value, not a successful command alone, is decisive.
  (( git_code == 0 )) || true
}

backup_phase() {
  phase_header backup
  local repo_name="$(basename "$repo")"
  local stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  local backup="$backup_root/$repo_name-$stamp"
  [[ ! -e "$backup" ]] || { fail "backup destination already exists: $backup"; return 1; }
  mkdir -p "$backup_root"

  run_logged /bin/cp -R "$repo" "$backup" || return 1

  local source_manifest="$out/backup-source-manifest.txt"
  local copied_manifest="$out/backup-copy-manifest.txt"
  print_command python3 full-digest-manifest "$repo" "$source_manifest"
  write_full_manifest "$repo" "$source_manifest"
  local source_code=$?
  print -r -- "exit=$source_code"
  (( source_code == 0 )) || return "$source_code"
  print_command python3 full-digest-manifest "$backup" "$copied_manifest"
  write_full_manifest "$backup" "$copied_manifest"
  local copied_code=$?
  print -r -- "exit=$copied_code"
  (( copied_code == 0 )) || return "$copied_code"

  run_logged cmp -s "$source_manifest" "$copied_manifest" || {
    fail "backup digest differs from source: $backup"
    return 1
  }
  /bin/cp "$source_manifest" "$backup_manifest"
  local backup_files="$(wc -l < "$backup_manifest" | tr -d ' ')"
  print -r -- "backup=$backup"
  print -r -- "backup_files=$backup_files"
  print 'backup_verified=yes'
}

migrate_phase() {
  phase_header migrate
  check_result 'verified backup manifest exists' \
    "$([[ -s "$backup_manifest" ]] && print yes || print no)" \
    "missing verified backup manifest: $backup_manifest" || return 1
  [[ -n "$project_key" ]] || { fail 'migrate requires --project-key'; return 1; }
  local -a command=(zsh "$install_sh" "$repo" --project-key "$project_key")
  [[ -z "$project_name" ]] || command+=(--name "$project_name")
  run_logged "${command[@]}"
}

verify_phase() {
  phase_header verify
  load_engine_arrays || return 1
  local repo_before="$out/verify-repo-before.txt"
  local repo_after="$out/verify-repo-after.txt"
  print_command python3 full-digest-manifest "$repo" "$repo_before"
  write_full_manifest "$repo" "$repo_before"
  local repo_manifest_code=$?
  print -r -- "exit=$repo_manifest_code"
  (( repo_manifest_code == 0 )) || return "$repo_manifest_code"
  local legacy="$repo/agentic/pm_flow" current="$repo/.agentic/pm_flow" scan_flow
  if [[ -d "$current" ]]; then
    scan_flow="$current"
  elif [[ -d "$legacy" ]]; then
    scan_flow="$legacy"
  else
    fail "no flow directory exists under $repo"
    return 1
  fi

  local -a scan_keys=("${(@f)$(discover_workspaces "$scan_flow")}")
  scan_keys=("${(@)scan_keys:#}")
  local remaining="$(engine_names_present "$scan_flow" "${scan_keys[@]}")"
  print -r -- "copied_engine_remaining=$remaining"

  local structure_ok=yes structure_error=''
  if [[ ! -d "$current" ]]; then
    structure_ok=no
    structure_error="migrated flow directory is absent; surviving copied-engine names: $remaining"
  elif [[ -e "$repo/agentic" ]]; then
    structure_ok=no
    structure_error='legacy agentic/ directory still exists'
  elif [[ -n "$remaining" ]]; then
    structure_ok=no
    structure_error="copied engine survives migration: $remaining"
  fi
  check_result 'only migrated project data remains' "$structure_ok" "$structure_error" || return 1
  check_result 'survey manifest exists' \
    "$([[ -s "$survey_manifest" && -s "$survey_workspaces" ]] && print yes || print no)" \
    "missing survey evidence in $out" || return 1

  local -a workspace_keys=("${(@f)$(<"$survey_workspaces")}")
  workspace_keys=("${(@)workspace_keys:#}")
  local key all_workspaces=yes
  for key in "${workspace_keys[@]}"; do
    [[ -d "$current/$key" ]] || { print -u2 -r -- "ERROR: surveyed workspace is missing: $key"; all_workspaces=no; }
  done
  check_result 'every surveyed workspace is present' "$all_workspaces" || return 1

  local verify_manifest="$out/verify-manifest.txt"
  print_command python3 project-data-manifest "$current" "$verify_manifest"
  write_project_manifest "$current" "$verify_manifest" "${workspace_keys[@]}"
  local manifest_code=$?
  print -r -- "exit=$manifest_code"
  (( manifest_code == 0 )) || return "$manifest_code"

  local line digest relative expected_path expected_line preservation_ok=yes
  while IFS= read -r line; do
    digest="${line%% *}"
    relative="${line#*  }"
    [[ -n "$relative" ]] || continue
    expected_path="$relative"
    if [[ -n "$project_key" && "$relative" == "$project_key/task_contract.md" ]]; then
      continue
    elif [[ -n "$project_key" && "$relative" == "$project_key/project_state/start.md" ]]; then
      expected_path="$project_key/project_state/start.pre-sections.md"
    elif [[ -n "$project_key" && "$relative" == "$project_key/project_state/resume.md" ]]; then
      expected_path="$project_key/project_state/resume.pre-sections.md"
    fi
    expected_line="$digest  $expected_path"
    grep -Fqx -- "$expected_line" "$verify_manifest" || {
      print -u2 -r -- "ERROR: surveyed project data was lost or rewritten: $relative"
      preservation_ok=no
    }
  done < "$survey_manifest"
  check_result 'surveyed project data digests match' "$preservation_ok" || return 1

  local projects_ok=yes
  [[ -f "$current/projects.md" ]] || projects_ok=no
  if [[ "$projects_ok" == yes ]]; then
    for key in "${workspace_keys[@]}"; do
      grep -Fq -- "- \`$key\`" "$current/projects.md" || {
        print -u2 -r -- "ERROR: projects.md does not name workspace: $key"
        projects_ok=no
      }
    done
  fi
  check_result 'projects.md names every surveyed workspace' "$projects_ok" || return 1

  run_captured git --no-optional-locks -C "$repo" diff --cached -M --name-status
  local diff_code=$? cached_diff="$REPLY"
  (( diff_code == 0 )) || return "$diff_code"
  local renames_recorded="$(print -r -- "$cached_diff" | awk '/^R/ { count += 1 } END { print count + 0 }')"
  print -r -- "renames_recorded=$renames_recorded"
  check_result 'at least one migration rename is recorded' \
    "$(if (( renames_recorded > 0 )); then print yes; else print no; fi)" \
    'git has no staged migration rename' || return 1

  run_logged git --no-optional-locks -C "$repo" status --short || return 1

  # `pm-flow status` imports legacy costs into its SQLite store. Run it with the
  # real repository as cwd, but point path resolution at an exact data snapshot
  # under --out so this verification phase remains read-only under --repo.
  local status_repo="$(mktemp -d "$out/status-repository.XXXXXX")"
  mkdir -p "$status_repo/.agentic"
  run_logged /bin/cp -R "$current" "$status_repo/.agentic/pm_flow" || return 1
  print -r -- '$ cd' "${(q)repo}" '&&' "PM_FLOW_REPO_ROOT=${(q)status_repo}" "${(q)pm_flow}" status
  (cd "$repo" && PM_FLOW_REPO_ROOT="$status_repo" "$pm_flow" status)
  local status_code=$?
  print -r -- "exit=$status_code"
  (( status_code == 0 )) || return "$status_code"

  print_command python3 full-digest-manifest "$repo" "$repo_after"
  write_full_manifest "$repo" "$repo_after"
  repo_manifest_code=$?
  print -r -- "exit=$repo_manifest_code"
  (( repo_manifest_code == 0 )) || return "$repo_manifest_code"
  run_logged cmp -s "$repo_before" "$repo_after" || {
    fail 'verify changed a file under --repo'
    return 1
  }
  print 'verify=ok'
}

main() {
  (( $# >= 1 )) || { usage; return $?; }
  phase="$1"
  shift
  case "$phase" in
    survey|backup|migrate|verify|all) ;;
    *) usage; return $? ;;
  esac

  repo=''
  project_key=''
  project_name=''
  install_sh="${PWD:A}/install.sh"
  pm_flow=''
  backup_root="$HOME/pm-flow-backups"
  out=''
  while (( $# > 0 )); do
    case "$1" in
      --repo|--project-key|--name|--install-sh|--pm-flow|--backup-root|--out)
        (( $# >= 2 )) || { usage; return $?; }
        local option="$1" value="$2"
        shift 2
        case "$option" in
          --repo) repo="$value" ;;
          --project-key) project_key="$value" ;;
          --name) project_name="$value" ;;
          --install-sh) install_sh="$value" ;;
          --pm-flow) pm_flow="$value" ;;
          --backup-root) backup_root="$value" ;;
          --out) out="$value" ;;
        esac
        ;;
      *) usage; return $? ;;
    esac
  done

  [[ -n "$repo" ]] || { fail '--repo is required'; return 2; }
  [[ -d "$repo" ]] || { fail "repository does not exist: $repo"; return 1; }
  repo="${repo:A}"
  install_sh="${install_sh:A}"
  [[ -f "$install_sh" ]] || { fail "install.sh does not exist: $install_sh"; return 1; }
  [[ -n "$pm_flow" ]] || pm_flow="$repo/.venv/bin/pm-flow"
  pm_flow="${pm_flow:A}"
  backup_root="${backup_root:A}"
  [[ -n "$out" ]] || out="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-real-install.XXXXXX")"
  out="${out:A}"
  if [[ "$out" == "$repo" || "$out" == "$repo"/* ]]; then
    fail "--out must be outside --repo: $out"
    return 1
  fi
  if [[ "$backup_root" == "$repo" || "$backup_root" == "$repo"/* ]]; then
    fail "--backup-root must be outside --repo: $backup_root"
    return 1
  fi
  mkdir -p "$out"
  transcript="$out/transcript.txt"
  survey_manifest="$out/survey-manifest.txt"
  survey_workspaces="$out/survey-workspaces.txt"
  backup_manifest="$out/backup-manifest.txt"
  touch "$transcript"
  exec > >(tee -a "$transcript") 2>&1
  trap 'print -r -- "transcript=$transcript"' EXIT

  typeset -ga COPIED_ENGINE_FILES COPIED_ENGINE_DIRS
  case "$phase" in
    survey) survey_phase ;;
    backup) backup_phase ;;
    migrate) migrate_phase ;;
    verify) verify_phase ;;
    all)
      survey_phase || return $?
      backup_phase || return $?
      migrate_phase || return $?
      verify_phase
      ;;
  esac
}

main "$@"
exit $?
```
<!-- runbook:end -->

## Golden-grid evidence

The operator transcript for `/Users/salah/code/personal/golden-grid` has not yet
been captured. Until that run occurs, the workspace count, ledger figures,
package version, backup location, migration output, rename count, and status
output are all placeholders rather than observations.

```text
transcript=PLACEHOLDER
```
