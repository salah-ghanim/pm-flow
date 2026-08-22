#!/bin/zsh -f
set -euo pipefail

# The packaged layout, proved end to end against a real installed artifact.
#
# Everything here exists to hold one boundary in place: the engine comes from
# the installed package and nothing else, the project data comes from the
# repository the command was invoked in and nothing else. A test that ran the
# checkout's pm_flow.sh, or copied a packaged file into the fixture, would pass
# while the boundary was broken, so it does neither. The fixture is written by
# hand and contains only project data; the engine is only ever reached through
# the venv's `pm-flow`.

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-packaged.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */pm-flow-packaged.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && "$(basename "$TEST_ROOT")" == pm-flow-packaged.* ]]; then
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

# Runs a command that must fail, and prints its combined output for inspection.
# A boundary violation usually shows up as an unexpected *success* - the command
# silently falling back to a packaged file - so the assertion is on the failure
# itself as much as on the message.
expect_failure() {
  local label="$1"
  shift
  # Not named `status`: zsh reserves that name, and assigning it here aborts
  # the function before the command's output can be inspected.
  local output exit_code=0
  output="$("$@" 2>&1)" || exit_code=$?
  (( exit_code != 0 )) || fail "$label: command unexpectedly succeeded:"$'\n'"$output"
  printf '%s\n' "$output"
}

# --- no inherited override may reach the engine ------------------------------
#
# `PM_FLOW_ENGINE_ROOT` is a legitimate override, and that is exactly why this
# test must not inherit one: it would silently redirect the run back at the
# checkout and every assertion below would still pass.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
[[ -z "${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}${PM_FLOW_PROJECT:-}" ]] || \
  fail "a PM_FLOW_* override survived into the test environment"

# --- build and install the current artifact ----------------------------------

VENV="$TEST_ROOT/venv"
DIST="$TEST_ROOT/dist"
mkdir -p "$DIST"

# Everything the build writes lands under TEST_ROOT, which the trap removes, so
# the caller prepares nothing: no `env -u`, no cache override, no PATH edit. An
# inherited VIRTUAL_ENV or PYTHONPATH would be worse than untidy - it would let
# a different interpreter, or a pm_flow already on sys.path, answer for the
# artifact this test claims to be proving.
unset VIRTUAL_ENV PYTHONPATH PYTHONHOME PYTHONSTARTUP
export UV_CACHE_DIR="$TEST_ROOT/uv-cache"
export PIP_CACHE_DIR="$TEST_ROOT/pip-cache"
export XDG_CACHE_HOME="$TEST_ROOT/xdg-cache"

if command -v uv >/dev/null 2>&1; then
  uv build --wheel --out-dir "$DIST" "$REPO_ROOT" > "$TEST_ROOT/build.log" 2>&1 || {
    /bin/cat "$TEST_ROOT/build.log" >&2
    fail "uv build failed"
  }
  uv venv "$VENV" >> "$TEST_ROOT/build.log" 2>&1 || fail "uv venv failed"
  VIRTUAL_ENV="$VENV" uv pip install "$DIST"/pm_flow-*.whl \
    >> "$TEST_ROOT/build.log" 2>&1 || {
    /bin/cat "$TEST_ROOT/build.log" >&2
    fail "uv pip install failed"
  }
else
  python3 -m venv "$VENV" > "$TEST_ROOT/build.log" 2>&1 || fail "venv creation failed"
  "$VENV/bin/pip" install --quiet "$REPO_ROOT" >> "$TEST_ROOT/build.log" 2>&1 || {
    /bin/cat "$TEST_ROOT/build.log" >&2
    fail "pip install of the checkout failed"
  }
fi

PM_FLOW="$VENV/bin/pm-flow"
[[ -x "$PM_FLOW" ]] || fail "the install produced no pm-flow entry point at $PM_FLOW"

# The build actually used the redirected cache rather than the caller's: if the
# directory is missing, the exports above stopped working and this run is
# quietly writing into whatever cache the caller had configured.
[[ -d "$UV_CACHE_DIR" || -d "$PIP_CACHE_DIR" ]] || \
  fail "the build wrote no cache inside the test workspace, so it used the caller's"
VENV_REAL="$(cd -P "$VENV" && pwd -P)"

# --- a fixture repository holding project data and nothing else --------------
#
# Written here rather than installed, because the installer still copies an
# engine. Every file below is project data by the definition this section is
# holding to: config, the project selector, and one project workspace.

FIXTURE="$TEST_ROOT/fixture repo"
FLOW="$FIXTURE/.agentic/pm_flow"
PROJECT_KEY="widget-shop"
WORKSPACE="$FLOW/$PROJECT_KEY"
SECTION="$WORKSPACE/sections/telemetry-cutover"
mkdir -p "$SECTION" "$WORKSPACE/runs" "$WORKSPACE/project_state"
git -C "$FIXTURE" init --quiet
printf '%s\n' "$PROJECT_KEY" > "$FLOW/.project-key"

# No "domain" key anywhere, so the run must fall through to the packaged
# built-in default. If it reports a domain, it read one this fixture never wrote.
/bin/cat > "$FLOW/config.json" <<'JSON'
{
  "version": 1,
  "roles": {
    "cpo": { "cli": "codex", "difficulty": "xhigh" },
    "pm": { "cli": "codex", "difficulty": "xhigh" },
    "developer": { "cli": "claude", "difficulty": "medium" },
    "consultant": [
      { "cli": "claude", "difficulty": "xhigh" },
      { "cli": "codex", "difficulty": "xhigh" }
    ],
    "10x_developer": { "cli": "claude", "difficulty": "max" }
  }
}
JSON
printf '{\n  "version": 1\n}\n' > "$WORKSPACE/project.json"
printf 'Telemetry cutover\n' > "$SECTION/name.txt"
printf 'active\n' > "$SECTION/status.txt"
printf 'must-have\n' > "$SECTION/priority.txt"
printf 'Nothing handed off yet.\n' > "$SECTION/summary.txt"
printf '2026-01-01T00:00:00Z\n' > "$SECTION/updated_at.txt"

# --- the fixture holds no engine and no packaged default ---------------------

for engine_file in pm_flow.sh driver.zsh agent_exec.sh heartbeat.sh cost.py \
                   telemetry.py catalog.py store.py upgrade.py trace_export.py; do
  [[ ! -e "$FLOW/$engine_file" ]] || fail "fixture contains a copied engine file: $engine_file"
done
for engine_dir in roles domains tasks project tests; do
  [[ ! -e "$FLOW/$engine_dir" ]] || \
    fail "fixture contains a copied packaged resource directory: $engine_dir"
done

# Stated positively as well, so a future engine file with a name nobody thought
# to list here still fails: the flow directory is exactly config, the selector,
# and the project workspace.
flow_entries="$(/bin/ls -A "$FLOW" | sort | tr '\n' ' ')"
assert_equals "$flow_entries" ".project-key config.json $PROJECT_KEY " \
  "the flow directory holds project data only"

printf 'PASS: a fixture repository that holds project data and no engine\n'

# --- the engine comes from the venv ------------------------------------------

version_output="$(cd "$FIXTURE" && "$PM_FLOW" version)"
engine_line="$(printf '%s\n' "$version_output" | awk '/^ *engine:/ {sub(/^ *engine: */, ""); print; exit}')"
[[ -n "$engine_line" ]] || fail "version did not report an engine path:"$'\n'"$version_output"
case "$engine_line" in
  "$VENV_REAL"/*|"$VENV"/*) ;;
  *) fail "engine is not beneath the temporary venv: $engine_line" ;;
esac
assert_not_contains "$engine_line" "$REPO_ROOT" "engine resolves outside the checkout"
assert_not_contains "$engine_line" "$FIXTURE" "engine resolves outside the fixture repository"
assert_contains "$engine_line" "pm_flow/engine" "engine is the package's engine directory"
[[ -f "$engine_line/pm_flow.sh" ]] || fail "reported engine has no pm_flow.sh: $engine_line"

printf 'PASS: the installed command runs the packaged engine\n'

# --- project data comes from the invoked repository --------------------------

status_output="$(cd "$FIXTURE" && "$PM_FLOW" status)"
assert_contains "$status_output" "telemetry-cutover" "status reports the fixture section"
assert_contains "$status_output" "must-have" "status reports the fixture section priority"
assert_contains "$status_output" "active" "status reports the fixture section status"
assert_not_contains "$status_output" "site-packages" "status reads no project data from the package"

# From a subdirectory too, the way every other repo-scoped tool behaves.
mkdir -p "$FIXTURE/src/deep"
nested_status="$(cd "$FIXTURE/src/deep" && "$PM_FLOW" status)"
assert_contains "$nested_status" "telemetry-cutover" "status works from a subdirectory"

printf 'PASS: project data is read from the invoked repository\n'

# --- the default persona and domain come from the package --------------------

prompt_output="$(cd "$FIXTURE" && "$PM_FLOW" role-prompt pm)"
assert_contains "$prompt_output" "Project Manager" "role-prompt applies the packaged generic title"
# The persona wraps, so the label lands at the start of its own line.
assert_contains "$prompt_output" "software. You own that section end to end." \
  "role-prompt applies the packaged generic label"
assert_contains "$prompt_output" \
  "The domain has not been specified, so do not assume one." \
  "role-prompt applies the packaged generic domain context"
assert_contains "$prompt_output" "$PROJECT_KEY" "role-prompt names the fixture project"
assert_not_contains "$prompt_output" "{{" "role-prompt leaves no unrendered macro"

config_output="$(cd "$FIXTURE" && "$PM_FLOW" config)"
assert_contains "$config_output" "domain=generic (built-in default)" \
  "config resolves the packaged built-in default domain"
assert_contains "$config_output" "pm: seats=1 title='Project Manager'" \
  "config validates the fixture roles against packaged personas"

printf 'PASS: the default persona and domain come from the installed package\n'

# --- failure cases -----------------------------------------------------------
#
# The boundary only holds if it fails in the right direction. A missing piece of
# project data must be an error about the fixture, never a silent fallback to
# the identically named file that ships inside the package.

mv "$FLOW/config.json" "$TEST_ROOT/config.json.aside"
missing_config="$(expect_failure "role-prompt without the fixture config" \
  zsh -c 'cd "$1" && "$2" role-prompt pm' zsh "$FIXTURE" "$PM_FLOW")"
assert_contains "$missing_config" "missing agent config" \
  "role-prompt names the missing config rather than falling back"
assert_contains "$missing_config" "$FLOW/config.json" \
  "the missing config is the fixture's, not the package's"
assert_not_contains "$missing_config" "site-packages" \
  "no packaged config.json is consulted"
mv "$TEST_ROOT/config.json.aside" "$FLOW/config.json"

no_flow="$TEST_ROOT/not a pm-flow repo"
mkdir -p "$no_flow"
git -C "$no_flow" init --quiet
outside="$(expect_failure "status outside any pm-flow repository" \
  zsh -c 'cd "$1" && "$2" status' zsh "$no_flow" "$PM_FLOW")"
assert_contains "$outside" "could not resolve project" \
  "status refuses a repository with no project data"
assert_contains "$outside" "$no_flow" \
  "the refusal names the invoked repository, not the package"
assert_not_contains "$outside" "site-packages" \
  "no packaged project workspace is offered as a fallback"

unknown_role="$(expect_failure "role-prompt for a role with no persona" \
  zsh -c 'cd "$1" && "$2" role-prompt archivist' zsh "$FIXTURE" "$PM_FLOW")"
assert_contains "$unknown_role" "unknown role 'archivist'" \
  "an unknown role is refused"

printf 'PASS: missing project data fails against the repository, not the package\n'

# --- running changed nothing inside the flow directory -----------------------

after_entries="$(/bin/ls -A "$FLOW" | sort | tr '\n' ' ')"
assert_equals "$after_entries" "$flow_entries" \
  "running the installed command added no engine file to the flow directory"

printf 'PASS: packaged layout, engine from the venv and data from the repository\n'
