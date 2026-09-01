#!/bin/zsh -f
set -euo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-real-install.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */pm-flow-real-install.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == pm-flow-real-install.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value="$1" expected="$2" label="$3"
  [[ "$value" == *"$expected"* ]] || \
    fail "$label: expected to find '$expected' in:"$'\n'"$value"
}

assert_not_contains() {
  local value="$1" unexpected="$2" label="$3"
  [[ "$value" != *"$unexpected"* ]] || fail "$label: did not expect '$unexpected'"
}

assert_equals() {
  local value="$1" expected="$2" label="$3"
  [[ "$value" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$value'"
}

assert_digest_lines_present() {
  local haystack="$1" needles="$2" label="$3" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$haystack" == *"$line"* ]] || \
      fail "$label: this file was lost or rewritten: ${line#* }"
  done <<< "$needles"
}

expect_failure() {
  local label="$1"
  shift
  local output exit_code=0
  output="$("$@" 2>&1)" || exit_code=$?
  (( exit_code != 0 )) || fail "$label: command unexpectedly succeeded:"$'\n'"$output"
  printf '%s\n' "$output"
}

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
[[ -z "${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}${PM_FLOW_PROJECT:-}" ]] || \
  fail "a PM_FLOW_* override survived into the test environment"

# Build the current wheel offline in a build-only venv, then install that wheel
# into a clean runtime venv. The installed status probe below never reaches the
# checkout's copied engine.
WHEELHOUSE="$REPO_ROOT/tests/packaging-build-wheelhouse"
BUILD_REQUIREMENTS="$WHEELHOUSE/build-requirements.txt"
BUILD_VENV="$TEST_ROOT/build-venv"
VENV="$TEST_ROOT/venv"
DIST="$TEST_ROOT/dist"
BUILD_LOG="$TEST_ROOT/build.log"
mkdir -p "$DIST"
[[ -f "$BUILD_REQUIREMENTS" ]] || fail "no locked build requirements at $BUILD_REQUIREMENTS"

unset VIRTUAL_ENV PYTHONPATH PYTHONHOME PYTHONSTARTUP
for name in ${(k)parameters[(I)PIP_*]} ${(k)parameters[(I)UV_*]}; do
  unset "$name"
done
export PIP_CACHE_DIR="$TEST_ROOT/pip-cache"
export XDG_CACHE_HOME="$TEST_ROOT/xdg-cache"
export PIP_CONFIG_FILE="$TEST_ROOT/pip.conf"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
: > "$PIP_CONFIG_FILE"
[[ -z "${PIP_INDEX_URL:-}${PIP_EXTRA_INDEX_URL:-}${UV_CACHE_DIR:-}" ]] || \
  fail "an inherited PIP_/UV_ setting survived into the build environment"
export ZDOTDIR="$TEST_ROOT/zdotdir"
mkdir -p "$ZDOTDIR"

pip_offline() {
  local venv="$1"
  shift
  "$venv/bin/python" -m pip install \
    --no-index --find-links "$WHEELHOUSE" \
    --disable-pip-version-check --no-input "$@"
}

python3 -m venv "$BUILD_VENV" > "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "build venv creation failed"
}
pip_offline "$BUILD_VENV" --quiet --require-hashes \
  -r "$BUILD_REQUIREMENTS" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "the locked build requirements did not install offline from $WHEELHOUSE"
}
"$BUILD_VENV/bin/python" -c 'import hatchling.build' >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "the build venv cannot import the declared build backend"
}
"$BUILD_VENV/bin/python" -m pip wheel \
  --no-index --no-build-isolation --no-deps \
  --disable-pip-version-check --no-input \
  --wheel-dir "$DIST" "$REPO_ROOT" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "the offline wheel build failed"
}
built_wheels="$(find "$DIST" -maxdepth 1 -type f -name 'pm_flow-*.whl' | sort)"
wheel_count="$(printf '%s' "$built_wheels" | grep -c . || true)"
[[ "$wheel_count" == 1 ]] || \
  fail "expected exactly one built pm_flow wheel in $DIST, found $wheel_count"
WHEEL="$built_wheels"
assert_contains "$WHEEL" "py3-none-any.whl" "the built wheel is platform-independent"

python3 -m venv "$VENV" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "runtime venv creation failed"
}
"$VENV/bin/python" -m pip install \
  --quiet --no-index --no-deps \
  --disable-pip-version-check --no-input \
  "$WHEEL" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "installing the built wheel into the runtime venv failed"
}
PM_FLOW="$VENV/bin/pm-flow"
[[ -x "$PM_FLOW" ]] || fail "the install produced no pm-flow entry point at $PM_FLOW"
PACKAGED_COST="$("$VENV/bin/python" - <<'PY'
from pathlib import Path
import pm_flow
print(Path(pm_flow.__file__).resolve().parent / "engine" / "cost.py")
PY
)"
[[ -f "$PACKAGED_COST" ]] || fail "the installed package has no cost command"

/bin/cat > "$TEST_ROOT/digest_tree.py" <<'DIGEST'
import hashlib
import sys
from pathlib import Path

base = Path(sys.argv[1])
for root in sorted(sys.argv[2:]):
    target = Path(root)
    paths = sorted(target.rglob("*")) if target.is_dir() else [target]
    for path in paths:
        if not path.is_file() or path.suffix == ".pyc" or "__pycache__" in path.parts:
            continue
        print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(base)}")
DIGEST

# An existing flow directory without any workspace must still take the repository
# basename as its default key. A blank key writes project data at the flow root
# and makes the next install reject its own persisted selector.
EMPTY_REPO="$TEST_ROOT/empty-workspace"
EMPTY_KEY="$(basename "$EMPTY_REPO")"
mkdir -p "$EMPTY_REPO/.agentic/pm_flow"
printf '{"version": 1}\n' > "$EMPTY_REPO/.agentic/pm_flow/config.json"
"$REPO_ROOT/install.sh" "$EMPTY_REPO" > "$TEST_ROOT/empty-first.out" 2>&1 || \
  fail "installing a workspace-less flow directory failed:"$'\n'"$(/bin/cat "$TEST_ROOT/empty-first.out")"
assert_equals "$(/usr/bin/head -n 1 "$EMPTY_REPO/.agentic/pm_flow/.project-key")" \
  "$EMPTY_KEY" "a workspace-less flow uses the repository basename as its key"
[[ -d "$EMPTY_REPO/.agentic/pm_flow/$EMPTY_KEY" ]] || \
  fail "a workspace-less flow did not create the basename workspace"
"$REPO_ROOT/install.sh" "$EMPTY_REPO" > "$TEST_ROOT/empty-second.out" 2>&1 || \
  fail "reinstalling the workspace-less flow failed:"$'\n'"$(/bin/cat "$TEST_ROOT/empty-second.out")"
printf 'PASS: workspace-less flow defaults to its repository basename and reinstalls\n'

LEGACY_REPO="$TEST_ROOT/golden grid fixture"
"$REPO_ROOT/tests/fixtures/real_install/build_fixture.sh" "$REPO_ROOT" "$LEGACY_REPO"
LEGACY_FLOW="$LEGACY_REPO/agentic/pm_flow"
WORKSPACE_KEYS=(alpha beta gamma project)
SELECTED_KEY=beta

[[ -x "$LEGACY_FLOW/pm_flow.sh" ]] || fail "the fixture has no copied engine"
[[ ! -e "$LEGACY_FLOW/.project-key" ]] || fail "the fixture unexpectedly names a selected project"
[[ ! -e "$LEGACY_FLOW/projects.md" ]] || fail "the fixture unexpectedly contains a project registry"
assert_equals "${#WORKSPACE_KEYS[@]}" "4" "the fixture has four workspaces"

workspace_digests() {
  local flow="$1" key="$2"
  local workspace="$flow/$key"
  local -a paths
  paths=(
    "$workspace/project.json"
    "$workspace/project_state/plan.md"
    "$workspace/project_state/sections.md"
    "$workspace/roles"
    "$workspace/sections"
    "$workspace/runs"
  )
  if [[ "$key" != "$SELECTED_KEY" ]]; then
    paths+=(
      "$workspace/task_contract.md"
      "$workspace/project_state/start.md"
      "$workspace/project_state/resume.md"
    )
  fi
  python3 "$TEST_ROOT/digest_tree.py" "$flow" "${paths[@]}"
}

mkdir -p "$TEST_ROOT/digests"
for key in "${WORKSPACE_KEYS[@]}"; do
  workspace_digests "$LEGACY_FLOW" "$key" > "$TEST_ROOT/digests/$key.before"
done
selected_start_digest="$(shasum -a 256 "$LEGACY_FLOW/$SELECTED_KEY/project_state/start.md" | awk '{print $1}')"
selected_resume_digest="$(shasum -a 256 "$LEGACY_FLOW/$SELECTED_KEY/project_state/resume.md" | awk '{print $1}')"
config_digest="$(shasum -a 256 "$LEGACY_FLOW/config.json" | awk '{print $1}')"

printf 'PASS: fixture has four unnamed legacy workspaces and copied engine data\n'

# The no-key path must diagnose the actual workspaces before an operator chooses
# one. A clone keeps this failure probe from mutating the fixture being migrated.
NO_KEY_REPO="$TEST_ROOT/no key fixture"
git clone --quiet "$LEGACY_REPO" "$NO_KEY_REPO"
no_key_output="$(expect_failure "migration without a project key" \
  "$REPO_ROOT/install.sh" "$NO_KEY_REPO")"
assert_contains "$no_key_output" "multiple pm-flow project workspaces exist" \
  "the no-key failure explains the ambiguity"
for key in "${WORKSPACE_KEYS[@]}"; do
  assert_contains "$no_key_output" "$key" "the no-key failure names workspace $key"
done
printf 'PASS: migration without a key names every discovered workspace\n'

"$REPO_ROOT/install.sh" "$LEGACY_REPO" --project-key "$SELECTED_KEY" \
  --name "Golden Grid Fixture" > "$TEST_ROOT/migrate.out" 2>&1 || \
  fail "migrating the legacy fixture failed:"$'\n'"$(/bin/cat "$TEST_ROOT/migrate.out")"

[[ ! -e "$LEGACY_REPO/agentic" ]] || fail "the legacy agentic directory survived migration"
MIGRATED_FLOW="$LEGACY_REPO/.agentic/pm_flow"
[[ -d "$MIGRATED_FLOW" ]] || fail "the hidden flow directory was not created"

cached_diff="$(git -C "$LEGACY_REPO" diff --cached -M --name-status)"
printf '%s\n' "$cached_diff" | grep -Eq '^R[0-9]+[[:space:]]+agentic/pm_flow/alpha/roles/pm.md[[:space:]]+\.agentic/pm_flow/alpha/roles/pm.md$' || \
  fail "git did not record the migration as a rename:"$'\n'"$cached_diff"
assert_not_contains "$cached_diff" $'D\tagentic/pm_flow/alpha/roles/pm.md' \
  "the preserved marker was not staged as delete plus add"

for key in "${WORKSPACE_KEYS[@]}"; do
  [[ -d "$MIGRATED_FLOW/$key" ]] || fail "workspace $key was lost during migration"
  after_digests="$(workspace_digests "$MIGRATED_FLOW" "$key")"
  before_digests="$(/bin/cat "$TEST_ROOT/digests/$key.before")"
  if [[ "$key" == "$SELECTED_KEY" ]]; then
    assert_digest_lines_present "$after_digests" "$before_digests" \
      "workspace $key preserved its project data byte for byte"
  else
    assert_equals "$after_digests" "$before_digests" \
      "workspace $key remained byte for byte unchanged"
  fi
done

selected_start_backup="$MIGRATED_FLOW/$SELECTED_KEY/project_state/start.pre-sections.md"
selected_resume_backup="$MIGRATED_FLOW/$SELECTED_KEY/project_state/resume.pre-sections.md"
[[ -f "$selected_start_backup" && -f "$selected_resume_backup" ]] || \
  fail "the selected workspace's pre-sections prompts were not backed up"
assert_equals "$(shasum -a 256 "$selected_start_backup" | awk '{print $1}')" \
  "$selected_start_digest" "the legacy start prompt backup is byte-identical"
assert_equals "$(shasum -a 256 "$selected_resume_backup" | awk '{print $1}')" \
  "$selected_resume_digest" "the legacy resume prompt backup is byte-identical"

assert_equals "$(shasum -a 256 "$MIGRATED_FLOW/config.json" | awk '{print $1}')" \
  "$config_digest" "the operator configuration is byte-identical"
assert_contains "$(/bin/cat "$MIGRATED_FLOW/config.json")" \
  '"operator_note": "golden-grid operator setting"' \
  "the operator-only configuration key survived"

listed_keys="$(sed -n 's/^- `\([^`]*\)` - installed project workspace.*/\1/p' \
  "$MIGRATED_FLOW/projects.md" | LC_ALL=C sort | tr '\n' ' ')"
assert_equals "$listed_keys" "alpha beta gamma project " \
  "projects.md lists every migrated workspace"

install_array_names() {
  local array_name="$1"
  sed -n "/^${array_name}=(/,/^)/p" "$REPO_ROOT/install.sh" | \
    sed '1d;$d;s/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d'
}

COPIED_ENGINE_FILES=("${(@f)$(install_array_names COPIED_ENGINE_FILES)}")
COPIED_ENGINE_DIRS=("${(@f)$(install_array_names COPIED_ENGINE_DIRS)}")
(( ${#COPIED_ENGINE_FILES[@]} > 0 )) || fail "install.sh names no copied engine files"
(( ${#COPIED_ENGINE_DIRS[@]} > 0 )) || fail "install.sh names no copied engine directories"
for name in "${COPIED_ENGINE_FILES[@]}"; do
  [[ ! -e "$MIGRATED_FLOW/$name" ]] || fail "a copied engine file survives: $name"
done
for name in "${COPIED_ENGINE_DIRS[@]}"; do
  (( ${WORKSPACE_KEYS[(Ie)$name]} )) && continue
  [[ ! -e "$MIGRATED_FLOW/$name" ]] || \
    fail "a flow-level packaged resource survives: $name"
done

# Import all legacy ledgers before dispatch. `cost.py total` also imports response
# envelopes, and `pm-flow status` reads those totals, so this must precede both.
for key in "${WORKSPACE_KEYS[@]}"; do
  workspace="$MIGRATED_FLOW/$key"
  ledger="$workspace/runs/cost_ledger.tsv"
  ledger_stats="$(awk -F '\t' \
    'NF >= 5 { count += 1; total += $5 } END { printf "%d\t%.4f", count, total }' \
    "$ledger")"
  expected_count="${ledger_stats%%$'\t'*}"
  expected_total="${ledger_stats#*$'\t'}"

  import_output="$("$VENV/bin/python" "$PACKAGED_COST" import "$workspace")" || \
    fail "cost import failed for workspace $key"
  assert_equals "$import_output" "imported=$expected_count" \
    "cost import reads every TSV row for workspace $key"
  reimport_output="$("$VENV/bin/python" "$PACKAGED_COST" import "$workspace")" || \
    fail "cost re-import failed for workspace $key"
  assert_equals "$reimport_output" "imported=0" \
    "cost re-import is idempotent for workspace $key"
  total_output="$("$VENV/bin/python" "$PACKAGED_COST" total "$workspace")" || \
    fail "cost total failed for workspace $key"
  assert_equals "$total_output" "$expected_total" \
    "stored cost matches independent TSV arithmetic for workspace $key"
  printf 'PASS: workspace=%s %s reimported=0 total=%s\n' \
    "$key" "$import_output" "$total_output"
done

status_output="$(cd "$LEGACY_REPO" && "$PM_FLOW" status)" || \
  fail "the wheel-installed pm-flow could not read the migrated fixture"
assert_contains "$status_output" "beta-section" \
  "the installed command resolves the selected migrated workspace"
assert_not_contains "$status_output" "$REPO_ROOT/template/.agentic/pm_flow" \
  "the installed command did not reach the checkout engine"

printf 'PASS: all workspaces survive migration, are registered, and the installed command reads them\n'

ledger_digests() {
  local key
  for key in "${WORKSPACE_KEYS[@]}"; do
    shasum -a 256 "$MIGRATED_FLOW/$key/runs/cost_ledger.tsv"
  done
}
ledgers_before_tick="$(ledger_digests)"

# The child records the prompt and returns a deterministic scope verdict. Its
# only write retires the scaffold marker in the workplan named by that prompt.
mkdir -p "$TEST_ROOT/agent-bin"
CAPTURED_PROMPT="$TEST_ROOT/dispatched_prompt.txt"
/bin/cat > "$TEST_ROOT/agent-bin/claude" <<'STUB'
#!/bin/zsh -f
printf '%s' "${@[-1]}" > "$PM_FLOW_CAPTURED_PROMPT"
wp="$(printf '%s\n' "${@[-1]}" | sed -n 's/^- *`\{0,1\}\([^`]*workplan\.md\)`\{0,1\} *$/\1/p' | head -n 1)"
[[ "$wp" == /* || -z "$wp" ]] || wp="${PROJECT_ROOT:-$PWD}/$wp"
[[ -z "$wp" || ! -f "$wp" ]] || { grep -v 'pm-flow-workplan-template' "$wp" > "$wp.tmp"; mv "$wp.tmp" "$wp"; }
python3 -c 'import json, sys; print(json.dumps(
    {"is_error": False, "result": sys.argv[1], "session_id": ""}))' \
'## Where the section stands

The migrated section has not been scoped yet.

## Workplan task

T1

## Assignment

Preserve the migrated project data.

## Acceptance

The migrated workspace drives an installed tick.

## Rejection conditions

Scope drift.

## Decision

ASSIGN - first piece'
STUB
chmod +x "$TEST_ROOT/agent-bin/claude"

tick_output="$(cd "$LEGACY_REPO" && \
  PM_FLOW_CAPTURED_PROMPT="$CAPTURED_PROMPT" \
  PATH="$TEST_ROOT/agent-bin:$PATH" \
  "$PM_FLOW" --project beta --section beta-section tick 2>&1)" || \
  fail "the installed dispatch failed:"$'\n'"$tick_output"
assert_contains "$tick_output" "section=beta-section" \
  "the tick acted on the migrated fixture section"
assert_contains "$tick_output" "action=scope" "the tick scoped the migrated section"
assert_contains "$tick_output" "-> ASSIGN" "the dispatched child's verdict was acted on"
[[ -f "$MIGRATED_FLOW/beta/sections/beta-section/cycles/001/assignment.md" ]] || \
  fail "the dispatch produced no assignment:"$'\n'"$tick_output"
[[ -f "$CAPTURED_PROMPT" ]] || fail "the installed dispatch captured no prompt"
captured_prompt="$(/bin/cat "$CAPTURED_PROMPT")"
assert_contains "$captured_prompt" "Beta workspace role marker" \
  "the installed engine reads the migrated workspace's pm overlay"
assert_not_contains "$captured_prompt" "$REPO_ROOT/template/.agentic/pm_flow" \
  "the installed tick did not reach the checkout engine"

assert_equals "$(ledger_digests)" "$ledgers_before_tick" \
  "the installed tick leaves every legacy TSV byte-identical"

completed_pm_attempts="$("$VENV/bin/python" - "$MIGRATED_FLOW/beta/runs/pm_flow.db" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
count = connection.execute(
    "SELECT COUNT(*) FROM attempts WHERE role_key = 'pm'"
    " AND status = 'ok' AND ended_at IS NOT NULL"
).fetchone()[0]
connection.close()
print(count)
PY
)" || fail "the tick's completed attempt could not be read from the store"
assert_equals "$completed_pm_attempts" "1" \
  "the tick records one completed pm attempt in the project store"

printf 'PASS: installed tick section=beta-section action=scope -> ASSIGN; TSVs unchanged; completed pm attempt stored\n'
