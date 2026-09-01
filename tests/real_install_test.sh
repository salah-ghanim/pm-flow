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

COPIED_ENGINE_FILES=(
  pm_flow.sh net_exec.sh agent_exec.sh access_hook.sh fetch.sh heartbeat.sh
  driver.zsh catalog.py compare.py cost.py store.py telemetry.py topology.py
  trace_export.py export.py prompt_quality.py watch.py upgrade.py requirements-telemetry.txt
  README.md run_detach.zsh artifact_quality.md
)
for name in "${COPIED_ENGINE_FILES[@]}"; do
  [[ ! -e "$MIGRATED_FLOW/$name" ]] || fail "a copied engine file survives: $name"
done
for name in roles domains tasks topologies cards schemas .pm-flow; do
  [[ ! -e "$MIGRATED_FLOW/$name" ]] || \
    fail "a flow-level packaged resource survives: $name"
done

status_output="$(cd "$LEGACY_REPO" && "$PM_FLOW" status)" || \
  fail "the wheel-installed pm-flow could not read the migrated fixture"
assert_contains "$status_output" "beta-section" \
  "the installed command resolves the selected migrated workspace"
assert_not_contains "$status_output" "$REPO_ROOT/template/.agentic/pm_flow" \
  "the installed command did not reach the checkout engine"

printf 'PASS: all workspaces survive migration, are registered, and the installed command reads them\n'
