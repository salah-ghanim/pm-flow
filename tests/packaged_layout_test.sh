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

# Order matters for an overlay: a layer that lands before the one it is meant to
# override has not overridden anything. Asserting only that both are present
# would pass on a prompt that applies them backwards.
assert_before() {
  local value="$1" first="$2" second="$3" label="$4"
  local head="${value%%"$second"*}"
  [[ "$head" != "$value" ]] || fail "$label: '$second' is not in the value"
  [[ "$head" == *"$first"* ]] || \
    fail "$label: '$first' does not appear before '$second'"
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
#
# The build is hermetic by construction rather than by luck. Earlier cycles ran
# `uv build`, which needs a package index the first time it resolves the build
# backend and, on this machine, aborts inside macOS system configuration before
# it gets that far. Neither the network nor the caller's cache is something a
# test of *this* repository should be asserting about, so both are removed: the
# build backend named in pyproject.toml is vendored as pinned, hashed,
# platform-independent wheels under tests/packaging-build-wheelhouse, and pip is
# run with the index switched off.
#
# Two virtual environments, deliberately. The build venv holds hatchling and its
# dependencies; the runtime venv holds nothing but the wheel that build
# produced. Installing into one venv would let a build-time import answer for
# something the shipped artifact is supposed to provide.

WHEELHOUSE="$REPO_ROOT/tests/packaging-build-wheelhouse"
BUILD_REQUIREMENTS="$WHEELHOUSE/build-requirements.txt"
BUILD_VENV="$TEST_ROOT/build-venv"
VENV="$TEST_ROOT/venv"
DIST="$TEST_ROOT/dist"
BUILD_LOG="$TEST_ROOT/build.log"
mkdir -p "$DIST"

[[ -f "$BUILD_REQUIREMENTS" ]] || \
  fail "no locked build requirements at $BUILD_REQUIREMENTS"

# Reports what the runtime venv actually has installed, read from the installed
# metadata rather than from anything this script arranged. Kept as a file under
# TEST_ROOT so the venv's own interpreter runs it with no PYTHONPATH games.
/bin/cat > "$TEST_ROOT/describe_install.py" <<'PY'
import json
import pathlib
import sysconfig

site = pathlib.Path(sysconfig.get_paths()["purelib"])
for info in sorted(site.glob("pm_flow-*.dist-info")):
    print(info.name)
    wheel_meta = info / "WHEEL"
    if wheel_meta.exists():
        print(wheel_meta.read_text())
    direct = info / "direct_url.json"
    if direct.exists():
        print(json.loads(direct.read_text()).get("url", ""))
PY

# Everything the build reads and writes lands under TEST_ROOT or the checked-in
# wheelhouse, so the caller prepares nothing: no `env -u`, no cache override, no
# PATH edit. An inherited VIRTUAL_ENV or PYTHONPATH would be worse than untidy -
# it would let a different interpreter, or a pm_flow already on sys.path, answer
# for the artifact this test claims to be proving. An inherited PIP_* or UV_*
# setting could point the build at an index, a config file or a cache this test
# never wrote, which is exactly the dependence it exists to remove.
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

# The caller's shell startup files, removed for the same reason. This script is
# `#!/bin/zsh -f`, but the installed entry point starts the engine as a fresh
# `zsh`, and every zsh reads `$ZDOTDIR/.zshenv` - so on a machine whose .zshenv
# prepends a toolchain directory to PATH (nvm, cargo, a version manager), that
# directory lands *ahead* of the deterministic child this test injects, and a
# real vendor binary answers a dispatch this test believes it stubbed.
export ZDOTDIR="$TEST_ROOT/zdotdir"
mkdir -p "$ZDOTDIR"

# `pip download` is never run here. --no-index means the only place a
# distribution can come from is --find-links, and --require-hashes means it must
# be byte for byte the file the lock recorded.
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

# The backend actually named by pyproject.toml, resolved out of the build venv.
# If the wheelhouse ever drifts from `[build-system] requires`, this is where it
# shows, rather than in a confusing build error further down.
"$BUILD_VENV/bin/python" -c 'import hatchling.build' >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "the build venv cannot import the declared build backend"
}

# --no-build-isolation, because isolation is what would reach for an index: the
# build venv already holds the pinned backend. --no-deps, because pm-flow
# declares no runtime dependencies and a build that started resolving some would
# be building something other than this package.
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

# The runtime venv gets the wheel and nothing else. --no-index and --no-deps
# together mean a missing piece cannot be silently fetched, and the checkout is
# never named on this command line, so nothing can be installed from it.
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

# The runtime venv is clean: it carries the wheel's contents, not the build
# toolchain that produced them. If hatchling is importable here the two
# environments were merged, and "installed from the wheel" means less than it says.
! "$VENV/bin/python" -c 'import hatchling' >/dev/null 2>&1 || \
  fail "the runtime venv contains the build backend, so it is not a clean install"

# And it holds the built artifact rather than the checkout. A source or editable
# install records the checkout path in the installed metadata; a wheel install
# records the wheel. Nothing under the runtime venv may point back at REPO_ROOT.
installed_record="$("$VENV/bin/python" "$TEST_ROOT/describe_install.py")"
assert_contains "$installed_record" "Generator: hatchling" \
  "the installed distribution was produced by the pinned build backend"
assert_contains "$installed_record" "Root-Is-Purelib: true" \
  "the installed distribution is the platform-independent wheel"
case "$installed_record" in
  *"$REPO_ROOT"*) fail "the runtime venv records the checkout as its source:"$'\n'"$installed_record" ;;
esac

# The build used the redirected cache rather than the caller's: if PIP_CACHE_DIR
# still pointed outside TEST_ROOT the exports above stopped working, and this run
# is quietly reading and writing whatever cache the caller had configured.
case "$PIP_CACHE_DIR" in
  "$TEST_ROOT"/*) ;;
  *) fail "the build cache escaped the test workspace: $PIP_CACHE_DIR" ;;
esac
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
  "isolation": { "worktrees": 0 },
  "roles": {
    "cpo": { "cli": "codex", "difficulty": "xhigh" },
    "pm": { "cli": "claude", "model": "fixture-pm-model", "difficulty": "high" },
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

# A second project in the same flow directory, and the one the dispatch below
# runs against. It exists to be *unlike* the first: it records a domain that the
# package actually ships a role overlay for, and it carries a persona layer of
# its own. Those are the two things a single-project fixture cannot show - that
# the packaged domain layer is applied rather than replaced, and that a layer
# the package has never heard of is applied on top of it.
DISPATCH_KEY="salvage-desk"
DISPATCH_WORKSPACE="$FLOW/$DISPATCH_KEY"
DISPATCH_SECTION_KEY="asset-recovery"
DISPATCH_SECTION="$DISPATCH_WORKSPACE/sections/$DISPATCH_SECTION_KEY"
mkdir -p "$DISPATCH_SECTION" "$DISPATCH_WORKSPACE/runs" \
         "$DISPATCH_WORKSPACE/project_state" "$DISPATCH_WORKSPACE/roles"
printf '{\n  "version": 1,\n  "domain": "distressed-tech"\n}\n' \
  > "$DISPATCH_WORKSPACE/project.json"
printf '# Salvage Desk Task Contract\n\nOne bounded assignment at a time.\n' \
  > "$DISPATCH_WORKSPACE/task_contract.md"
printf 'Asset recovery\n' > "$DISPATCH_SECTION/name.txt"
printf 'active\n' > "$DISPATCH_SECTION/status.txt"
printf 'must-have\n' > "$DISPATCH_SECTION/priority.txt"
printf 'Nothing handed off yet.\n' > "$DISPATCH_SECTION/summary.txt"
printf '2026-01-01T00:00:00Z\n' > "$DISPATCH_SECTION/updated_at.txt"
/bin/cat > "$DISPATCH_SECTION/brief.md" <<'BRIEF'
## Objective

- Recover the assets the registry cannot currently account for.

## Priority

- must-have
BRIEF

# The repository's own layer. Written here, inside the project workspace, never
# into the package: this is the whole claim - customising a role is adding a
# file to your own repository, so upgrading the package cannot touch it and
# there is nothing to merge.
LOCAL_LAYER_MARKER="Salvage desk house rule: every record names the document it came from."
/bin/cat > "$DISPATCH_WORKSPACE/roles/pm.md" <<LOCAL
## House rules for {{PROJECT_NAME}}

$LOCAL_LAYER_MARKER
LOCAL

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
assert_equals "$flow_entries" ".project-key config.json $DISPATCH_KEY $PROJECT_KEY " \
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

# --- an installed dispatch, and the stack it was composed from ---------------
#
# Everything above reads. This dispatches: `pm-flow tick` advances a fixture
# section through the installed entry point, using the fixture's own config to
# decide which backend runs the role, and the prompt that reaches the child is
# the packaged base persona plus the packaged domain overlay plus the layer this
# repository wrote - in that order.
#
# The child is a local script, not a vendor CLI. That is deliberate and it is
# the limit of what this proves: the routing of an installed dispatch and the
# provenance recorded against it. It says nothing about live vendor
# compatibility, which needs a credentialed `pm-flow tick` to observe.

ENGINE="$engine_line"
PACKAGED_BASE="$ENGINE/roles/pm.md"
PACKAGED_DOMAIN="$ENGINE/domains/distressed-tech/roles/pm.md"
LOCAL_LAYER="$DISPATCH_WORKSPACE/roles/pm.md"
[[ -f "$PACKAGED_BASE" ]] || fail "the package ships no base pm persona at $PACKAGED_BASE"
[[ -f "$PACKAGED_DOMAIN" ]] || fail "the package ships no domain pm overlay at $PACKAGED_DOMAIN"

# What the package holds before the run, so "unchanged" is measured rather than
# assumed. Every persona in the package, not only the three this dispatch uses.
packaged_persona_digests() {
  find "$ENGINE/roles" "$ENGINE/domains" -type f -name '*.md' | sort | \
    xargs shasum -a 256
}
personas_before="$(packaged_persona_digests)"

# A marker per layer, taken from the shipped text rather than invented, so a
# layer that stopped being applied cannot still match.
BASE_MARKER="Keeping durable detail in your section's"
DOMAIN_MARKER="Nothing enters the registry on an analyst's say-so."
assert_contains "$(/bin/cat "$PACKAGED_BASE")" "$BASE_MARKER" \
  "the packaged base persona still carries its marker"
assert_contains "$(/bin/cat "$PACKAGED_DOMAIN")" "$DOMAIN_MARKER" \
  "the packaged domain overlay still carries its marker"

# The child. It records the prompt it was handed and answers with a scope
# verdict the driver can act on - deterministic, offline, and unable to reach
# anything. `${@[-1]}` is the prompt: every backend takes it last.
mkdir -p "$TEST_ROOT/agent-bin"
CAPTURED_PROMPT="$TEST_ROOT/dispatched_prompt.txt"
/bin/cat > "$TEST_ROOT/agent-bin/claude" <<'STUB'
#!/bin/zsh -f
printf '%s' "${@[-1]}" > "$PM_FLOW_CAPTURED_PROMPT"
python3 -c 'import json, sys; print(json.dumps(
    {"is_error": False, "result": sys.argv[1], "session_id": ""}))' \
'## Where the section stands

The registry has unaccounted assets and nothing has been scoped yet.

## Assignment

Reconcile the registry against the source documents.

## Acceptance

Every registry row cites a document.

## Rejection conditions

Scope drift.

## Decision

ASSIGN - first piece'
STUB
chmod +x "$TEST_ROOT/agent-bin/claude"

tick_output="$(cd "$FIXTURE" && \
  PM_FLOW_CAPTURED_PROMPT="$CAPTURED_PROMPT" \
  PATH="$TEST_ROOT/agent-bin:$PATH" \
  "$PM_FLOW" --project "$DISPATCH_KEY" --section "$DISPATCH_SECTION_KEY" tick 2>&1)" || \
  fail "the installed dispatch failed:"$'\n'"$tick_output"
assert_contains "$tick_output" "section=$DISPATCH_SECTION_KEY" \
  "the tick acted on the fixture section"
assert_contains "$tick_output" "action=scope" "the tick scoped the section"
assert_contains "$tick_output" "-> ASSIGN" "the dispatched child's verdict was acted on"
[[ -f "$DISPATCH_SECTION/cycles/001/assignment.md" ]] || \
  fail "the dispatch produced no assignment:"$'\n'"$tick_output"

# The dispatch read the fixture's binding, not a packaged one. `pm` is bound to
# claude here and to codex nowhere the package could have supplied.
[[ -f "$CAPTURED_PROMPT" ]] || \
  fail "no child was dispatched; nothing captured the prompt"
dispatched_prompt="$(/bin/cat "$CAPTURED_PROMPT")"

# The three layers, in order.
assert_contains "$dispatched_prompt" "$BASE_MARKER" \
  "the prompt carries the packaged base persona"
assert_contains "$dispatched_prompt" "$DOMAIN_MARKER" \
  "the prompt carries the packaged domain layer"
assert_contains "$dispatched_prompt" "$LOCAL_LAYER_MARKER" \
  "the prompt carries the project-local overlay"
assert_before "$dispatched_prompt" "$BASE_MARKER" "$DOMAIN_MARKER" \
  "base persona precedes the domain layer"
assert_before "$dispatched_prompt" "$DOMAIN_MARKER" "$LOCAL_LAYER_MARKER" \
  "domain layer precedes the project-local overlay"
assert_contains "$dispatched_prompt" "Salvage Desk" \
  "the prompt names the invoked repository's project, not the package's"
assert_not_contains "$dispatched_prompt" "{{" "the composed prompt leaves no unrendered macro"

# What the store recorded against the attempt that dispatch produced. Read from
# the fixture's own store, and only from a completed attempt: provenance
# attached to a row that never ran would prove nothing.
STORE="$DISPATCH_WORKSPACE/runs/pm_flow.db"
[[ -f "$STORE" ]] || fail "the dispatch recorded no store at $STORE"
recorded="$(python3 - "$STORE" "$PACKAGED_BASE" "$PACKAGED_DOMAIN" "$LOCAL_LAYER" <<'PY'
import hashlib
import json
import sqlite3
import sys

store, *layer_files = sys.argv[1:]
connection = sqlite3.connect(store)
connection.row_factory = sqlite3.Row

rows = connection.execute(
    "SELECT * FROM attempts WHERE role_key = 'pm' AND status = 'ok'"
    " AND ended_at IS NOT NULL ORDER BY id"
).fetchall()
if len(rows) != 1:
    raise SystemExit(f"expected exactly one completed pm attempt, found {len(rows)}")
attempt = rows[0]

# The digest the catalogue content-addresses a persona by: its key, its layer
# and its exact words. Recomputed here from the files on disk rather than read
# back out of the same table being checked.
def digest(key, layer, path):
    running = hashlib.sha256()
    for part in (key, layer, open(path, encoding="utf-8").read()):
        running.update(b"\x00")
        running.update(part.encode("utf-8", "replace"))
    return running.hexdigest()

expected = [
    {"key": "pm", "layer": "base", "content_hash": digest("pm", "base", layer_files[0])},
    {"key": "distressed-tech/pm", "layer": "domain",
     "content_hash": digest("distressed-tech/pm", "domain", layer_files[1])},
    {"key": "salvage-desk/pm", "layer": "style",
     "content_hash": digest("salvage-desk/pm", "style", layer_files[2])},
]
stack = json.loads(attempt["persona_stack"])
if stack != expected:
    raise SystemExit("persona_stack does not name the three layers in order:\n"
                     f"  recorded: {json.dumps(stack, indent=2)}\n"
                     f"  expected: {json.dumps(expected, indent=2)}")

top = connection.execute(
    "SELECT key, layer, content_hash FROM personas WHERE id = ?",
    (attempt["persona_id"],)
).fetchone()
if top is None:
    raise SystemExit("the attempt records no persona_id")
if dict(top) != expected[-1]:
    raise SystemExit(f"persona_id is not the effective top layer: {dict(top)}")

binding = connection.execute(
    "SELECT key, cli, model, thinking_level FROM bindings WHERE id = ?",
    (attempt["binding_id"],)
).fetchone()
if binding is None:
    raise SystemExit("the attempt records no binding_id")

print(f"persona_stack={' -> '.join(entry['key'] for entry in stack)}")
print(f"persona_id={top['key']} ({top['layer']})")
print(f"binding={binding['key']} cli={binding['cli']} model={binding['model']} "
      f"thinking={binding['thinking_level']}")
PY
)" || fail "the recorded provenance did not match the composed stack"

assert_contains "$recorded" \
  "persona_stack=pm -> distressed-tech/pm -> salvage-desk/pm" \
  "the attempt records the three layers in application order"
assert_contains "$recorded" "persona_id=salvage-desk/pm (style)" \
  "the attempt's persona is the effective top layer"
assert_contains "$recorded" \
  "binding=pm.1 cli=claude model=fixture-pm-model thinking=high" \
  "the attempt's binding is the fixture's, not a packaged default"

# The package was read and not written. Nothing was copied into the fixture
# either: the flow directory still holds project data, and the only persona
# inside the repository is the one this test wrote.
assert_equals "$(packaged_persona_digests)" "$personas_before" \
  "the dispatch left every packaged persona byte for byte unchanged"
for engine_file in pm_flow.sh driver.zsh agent_exec.sh catalog.py telemetry.py store.py; do
  [[ ! -e "$FLOW/$engine_file" ]] || \
    fail "the dispatch copied an engine file into the fixture: $engine_file"
  [[ ! -e "$DISPATCH_WORKSPACE/$engine_file" ]] || \
    fail "the dispatch copied an engine file into the project workspace: $engine_file"
done
for engine_dir in roles domains tasks project; do
  [[ ! -e "$FLOW/$engine_dir" ]] || \
    fail "the dispatch copied a packaged resource directory into the fixture: $engine_dir"
done
local_persona_entries="$(/bin/ls -A "$DISPATCH_WORKSPACE/roles" | sort | tr '\n' ' ')"
assert_equals "$local_persona_entries" "pm.md " \
  "no packaged persona was copied beside the project-local overlay"

printf 'PASS: an installed dispatch composes base, domain and local layers and records them\n'

# --- running changed nothing inside the flow directory -----------------------

after_entries="$(/bin/ls -A "$FLOW" | sort | tr '\n' ' ')"
assert_equals "$after_entries" "$flow_entries" \
  "running the installed command added no engine file to the flow directory"

printf 'PASS: packaged layout, engine from the venv and data from the repository\n'

# --- what a repository is allowed to contain ---------------------------------
#
# The names an old install copied into a repository. They are listed here rather
# than derived from the package, so a file that stops being shipped is still
# checked for in repositories that already received it.

COPIED_ENGINE_FILES=(
  pm_flow.sh net_exec.sh agent_exec.sh access_hook.sh fetch.sh heartbeat.sh
  driver.zsh catalog.py cost.py store.py telemetry.py trace_export.py watch.py
  upgrade.py requirements-telemetry.txt README.md
)
COPIED_ENGINE_DIRS=(roles domains tasks project tests .pm-flow)

# A flow directory holds project data and nothing else. Checked by name for the
# things an install used to write, and by search for the copy-version lifecycle,
# which could be left anywhere under the repository rather than only at the top.
assert_data_only() {
  local flow="$1" label="$2" name
  for name in "${COPIED_ENGINE_FILES[@]}"; do
    [[ ! -e "$flow/$name" ]] || fail "$label: a copied engine file survives: $name"
  done
  for name in "${COPIED_ENGINE_DIRS[@]}"; do
    [[ ! -e "$flow/$name" ]] || fail "$label: a packaged resource directory survives: $name"
  done
  local stray
  stray="$(find "$flow/.." \( -name MANIFEST -o -name upgrade.py \) -print 2>/dev/null)"
  [[ -z "$stray" ]] || \
    fail "$label: an install record or copy-version file survives:"$'\n'"$stray"
}

# What the installed package holds, so "the install was not written to" is
# measured rather than assumed. Bytecode caches are excluded by default: they
# are the interpreter's, not the distribution's, and they are not what an
# upgrade or a migration would be accused of rewriting.
#
# `--complete` is the other question, asked of a repository rather than of an
# installation: not "did anything the distribution ships change" but "is this
# tree byte for byte what it was". It omits nothing - hidden paths, empty
# directories, bytecode and symlinks are all reported, and a symlink is reported
# by its target rather than by the bytes it happens to point at, because
# repointing one is a change to the tree that hashing through it would hide.
/bin/cat > "$TEST_ROOT/digest_tree.py" <<'DIGEST'
import hashlib
import os
import sys
from pathlib import Path

argv = sys.argv[1:]
complete = bool(argv) and argv[0] == "--complete"
if complete:
    argv = argv[1:]

base = Path(argv[0])
for root in sorted(argv[1:]):
    target = Path(root)
    paths = sorted(target.rglob("*")) if target.is_dir() else [target]
    for path in paths:
        try:
            shown = path.relative_to(base)
        except ValueError:
            shown = path
        if not complete:
            if not path.is_file() or path.suffix == ".pyc" or "__pycache__" in path.parts:
                continue
            print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {shown}")
            continue
        if path.is_symlink():
            print(f"symlink:{os.readlink(path)}  {shown}")
        elif path.is_dir():
            print(f"dir  {shown}")
        elif path.is_file():
            print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {shown}")
        else:
            print(f"other  {shown}")
DIGEST

engine_digests() {
  python3 "$TEST_ROOT/digest_tree.py" "$ENGINE" "$ENGINE"
}
engine_before="$(engine_digests)"

# The deterministic child for the runs below: the same offline stub the full
# suite drives its sections with. It answers every step of a cycle, so a tick
# after migration can carry the project forward rather than only re-scoping it.
mkdir -p "$TEST_ROOT/flow-bin"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_success.zsh" "$TEST_ROOT/flow-bin/claude"
chmod +x "$TEST_ROOT/flow-bin/claude"

bind_local_roles() {
  python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
config["roles"]["consultant"] = [{"cli": "claude", "model": "", "difficulty": "low"}]
config["isolation"] = {"worktrees": 0}
config["supervision"] = {
    "heartbeat_stall_seconds": 30, "max_attempts": 1,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PY
}

section_brief() {
  printf '## Objective\n\n- %s\n\n' "$1"
  printf '## Scope\n\n- That work only.\n\n'
  printf '## Priority\n\n- must-have: the product cannot ship without it\n\n'
  printf '## Owned paths\n\n- `src/%s/**`\n\n' "$2"
  printf '## Dependencies\n\n- None.\n\n'
  printf '## Acceptance\n\n- The bounded result is validated.\n\n'
  printf '## Rejection conditions\n\n- Scope drift.\n'
}

# Project-level governance preempts section work, so a tick that lands on a due
# review spends itself there. `status` is side-effect free, so the queue is
# drained before anything asserts on a single section's tick.
#
# The command is a parameter rather than the ambient `$PM_FLOW`: later blocks
# drive repositories through their own separately versioned installs, and a
# drain that reached for one repository's executable while ticking another's
# would be the exact sharing those blocks exist to rule out.
drain_project_work() {
  local repo="$1" done_flag="$2" command="${3:-$PM_FLOW}" guard=0
  while [[ "$(cd "$repo" && "$command" status)" == *"portfolio review due"* ]]; do
    (( guard += 1 ))
    (( guard <= 8 )) || fail "the portfolio review queue would not drain"
    ( cd "$repo" && PM_DONE_FLAG="$done_flag" PATH="$TEST_ROOT/flow-bin:$PATH" \
      "$command" tick ) > /dev/null 2>&1
  done
}

# --- initialising a fresh repository -----------------------------------------
#
# install.sh no longer ships an engine. What it writes is the half that was
# always the repository's own, and the assertion is stated positively: the flow
# directory is exactly these entries, so a file nobody thought to list here
# still fails.

INIT_REPO="$TEST_ROOT/init repo"
mkdir -p "$INIT_REPO"
git -C "$INIT_REPO" init --quiet
INIT_FLOW="$INIT_REPO/.agentic/pm_flow"
INIT_KEY="init-repo"
INIT_SECTION_KEY="cutover"
"$REPO_ROOT/install.sh" "$INIT_REPO" --name "Init Project" --domain distressed-tech \
  > "$TEST_ROOT/init-install.out" 2>&1 || \
  fail "install.sh failed:"$'\n'"$(/bin/cat "$TEST_ROOT/init-install.out")"

assert_equals "$(/bin/ls -A "$INIT_REPO/.agentic" | LC_ALL=C sort | tr '\n' ' ')" \
  "pm_flow " "installing puts nothing beside the flow directory"
assert_equals "$(/bin/ls -A "$INIT_FLOW" | LC_ALL=C sort | tr '\n' ' ')" \
  ".gitignore .project-key config.json $INIT_KEY local_env.sh.example projects.md " \
  "a fresh install writes project data only"
assert_data_only "$INIT_FLOW" "a fresh install"
assert_equals "$(/bin/ls -A "$INIT_FLOW/$INIT_KEY" | LC_ALL=C sort | tr '\n' ' ')" \
  "project.json project_state runs sections task_contract.md " \
  "the project workspace is the project's own files"

# And the repository it wrote is one the installed command can actually drive.
bind_local_roles "$INIT_FLOW/config.json"
( cd "$INIT_REPO" && "$PM_FLOW" init-section "$INIT_SECTION_KEY" \
  <<< "$(section_brief 'Cut the ledger over.' cutover)" ) > "$TEST_ROOT/init-section.out"

INIT_SECTION="$INIT_FLOW/$INIT_KEY/sections/$INIT_SECTION_KEY"
drain_project_work "$INIT_REPO" "$TEST_ROOT/init.flag"
init_tick="$(cd "$INIT_REPO" && PM_DONE_FLAG="$TEST_ROOT/init.flag" \
  PATH="$TEST_ROOT/flow-bin:$PATH" "$PM_FLOW" tick 2>&1)" || \
  fail "the installed tick failed on a freshly initialised repository:"$'\n'"$init_tick"
assert_contains "$init_tick" "section=$INIT_SECTION_KEY" "the tick acted on the new section"
assert_contains "$init_tick" "-> ASSIGN" "the deterministic child's verdict was acted on"
[[ -f "$INIT_SECTION/cycles/001/assignment.md" ]] || \
  fail "the tick produced no assignment:"$'\n'"$init_tick"

# Driving it wrote records, and no engine.
assert_data_only "$INIT_FLOW" "a fresh install after a tick"
[[ -f "$INIT_FLOW/$INIT_KEY/runs/pm_flow.db" ]] || \
  fail "the tick recorded no store under the project workspace"

printf 'PASS: a fresh repository holds project data only, and the installed command drives it\n'

# --- migrating a repository that still holds a copied engine ------------------
#
# The fixture is a copied install as the old installer produced one: every file
# the template ships, copied into the repository and made executable, plus the
# install record and the copy-version module that managed those copies. It is
# then *run* through its own copied engine, so the project it carries into
# migration has real run history rather than hand-written files.

LEGACY_REPO="$TEST_ROOT/legacy repo"
LEGACY_FLOW="$LEGACY_REPO/.agentic/pm_flow"
LEGACY_KEY="salvage-legacy"
LEGACY_WS="$LEGACY_FLOW/$LEGACY_KEY"
LEGACY_SECTION_KEY="ledger-reconstruction"
LEGACY_SECTION="$LEGACY_WS/sections/$LEGACY_SECTION_KEY"
mkdir -p "$LEGACY_FLOW"
git -C "$LEGACY_REPO" init --quiet

/bin/cp -R "$REPO_ROOT/template/.agentic/pm_flow/." "$LEGACY_FLOW/"
rm -rf "$LEGACY_FLOW/__pycache__"
for candidate in "$LEGACY_FLOW"/*(.N); do
  [[ "$(/usr/bin/head -c 2 "$candidate" 2>/dev/null)" == "#!" ]] || continue
  chmod +x "$candidate"
done
[[ -x "$LEGACY_FLOW/pm_flow.sh" ]] || fail "the legacy fixture has no copied engine to migrate"

# The two things this section exists to delete, as an old install left them.
mkdir -p "$LEGACY_FLOW/.pm-flow"
printf 'version 0.2.0\nroot template\nengine x deadbeef .agentic/pm_flow/pm_flow.sh\n' \
  > "$LEGACY_FLOW/.pm-flow/MANIFEST"
printf '# the copy-version lifecycle this install was managed by\n' \
  > "$LEGACY_FLOW/upgrade.py"

printf '%s\n' "$LEGACY_KEY" > "$LEGACY_FLOW/.project-key"
python3 - "$REPO_ROOT/template/.agentic/pm_flow/config.json" "$LEGACY_FLOW/config.json" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text().replace("{{DOMAIN}}", "generic"))
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
config["roles"]["consultant"] = [{"cli": "claude", "model": "", "difficulty": "low"}]
config["isolation"] = {"worktrees": 0}
config["supervision"] = {
    "heartbeat_stall_seconds": 30, "max_attempts": 1,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
# An operator's own edit. Nothing in the flow reads it, which is the point: a
# migration that rewrote config.json rather than leaving it alone would lose it.
config["operator_note"] = "hand-tuned before the package existed"
Path(sys.argv[2]).write_text(json.dumps(config, indent=2) + "\n")
PY

mkdir -p "$LEGACY_WS/project_state" "$LEGACY_WS/runs" "$LEGACY_SECTION" "$LEGACY_WS/roles"
printf '{\n  "version": 1,\n  "domain": "distressed-tech"\n}\n' > "$LEGACY_WS/project.json"
printf '# Salvage Legacy Task Contract\n\nOne bounded assignment at a time.\n' \
  > "$LEGACY_WS/task_contract.md"
LEGACY_PLAN_MARKER="The ledger predates the registry and only the documents reconcile them."
printf '# Project plan\n\n%s\n' "$LEGACY_PLAN_MARKER" > "$LEGACY_WS/project_state/plan.md"
printf '# Sections\n\n| section | priority | status | summary |\n' \
  > "$LEGACY_WS/project_state/sections.md"
printf 'Ledger reconstruction\n' > "$LEGACY_SECTION/name.txt"
printf 'active\n' > "$LEGACY_SECTION/status.txt"
printf 'must-have\n' > "$LEGACY_SECTION/priority.txt"
printf 'Nothing handed off yet.\n' > "$LEGACY_SECTION/summary.txt"
printf '2026-01-01T00:00:00Z\n' > "$LEGACY_SECTION/updated_at.txt"
section_brief 'Reconstruct the ledger from the source documents.' ledger \
  > "$LEGACY_SECTION/brief.md"
LEGACY_OVERLAY_MARKER="Legacy desk house rule: cite the document behind every row."
printf '## House rules\n\n%s\n' "$LEGACY_OVERLAY_MARKER" > "$LEGACY_WS/roles/pm.md"

# Run it through its own copied engine, so the migration is handed a project
# with recorded attempts rather than a directory of files.
legacy_tick="$(cd "$LEGACY_REPO" && PM_DONE_FLAG="$TEST_ROOT/legacy.flag" \
  PATH="$TEST_ROOT/flow-bin:$PATH" zsh -f "$LEGACY_FLOW/pm_flow.sh" tick 2>&1)" || \
  fail "the copied engine could not drive its own repository:"$'\n'"$legacy_tick"
assert_contains "$legacy_tick" "section=$LEGACY_SECTION_KEY" \
  "the legacy fixture ran its own section"
[[ -f "$LEGACY_SECTION/cycles/001/assignment.md" ]] || \
  fail "the legacy fixture produced no cycle to carry through migration"
LEGACY_STORE="$LEGACY_WS/runs/pm_flow.db"
[[ -f "$LEGACY_STORE" ]] || fail "the legacy fixture recorded no store"

# What the copied engine reports, before anything is removed.
legacy_engine() {
  ( cd "$LEGACY_REPO" && zsh -f "$LEGACY_FLOW/pm_flow.sh" "$@" )
}
status_before="$(legacy_engine status)"
sections_before="$(legacy_engine list-sections)"
config_before="$(legacy_engine config)"
cost_before="$(legacy_engine cost)"

# And what it recorded. Read from the attempts table by their own identity, so a
# store that was replaced with a fresh one cannot match.
query_attempts() {
  python3 - "$1" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
rows = connection.execute(
    "SELECT role_key, step, cycle, label, status FROM attempts ORDER BY id"
).fetchall()
if not rows:
    raise SystemExit("no attempts were recorded")
for row in rows:
    print("|".join("" if value is None else str(value) for value in row))
PY
}
attempts_before="$(query_attempts "$LEGACY_STORE")" || \
  fail "the legacy fixture recorded no queryable attempt"

# The project data that must survive byte for byte. task_contract.md, the
# coordinator prompts and the flow-level scaffolding are deliberately absent:
# install.sh refreshes those on every run and always has.
preserved_digests() {
  python3 "$TEST_ROOT/digest_tree.py" "$LEGACY_FLOW" \
    "$LEGACY_WS/project_state/plan.md" "$LEGACY_WS/project_state/sections.md" \
    "$LEGACY_WS/project.json" "$LEGACY_WS/roles" "$LEGACY_WS/sections" \
    "$LEGACY_WS/runs" "$LEGACY_FLOW/config.json"
}
preserved_before="$(preserved_digests)"

# --- migrate ------------------------------------------------------------------

"$REPO_ROOT/install.sh" "$LEGACY_REPO" --name "Salvage Legacy" \
  > "$TEST_ROOT/legacy-migrate.out" 2>&1 || \
  fail "migrating the copied install failed:"$'\n'"$(/bin/cat "$TEST_ROOT/legacy-migrate.out")"

assert_data_only "$LEGACY_FLOW" "the migrated repository"
assert_equals "$(/bin/ls -A "$LEGACY_FLOW" | LC_ALL=C sort | tr '\n' ' ')" \
  ".gitignore .project-key config.json local_env.sh.example projects.md $LEGACY_KEY " \
  "the migrated flow directory holds project data only"

# Nothing was lost. The digests cover the plan, the registry, the recorded
# domain, every section file, the run records, the store, the operator's config
# and the project-local persona overlay.
# Stated as "every file that was there is still there, with the same bytes"
# rather than as string equality, because install.sh legitimately *adds* to a
# workspace - the .gitkeep markers that keep an empty runs/ and sections/ in
# git. Losing or rewriting one of the files below is what this forbids, and the
# failure names the file rather than printing two hundred digests.
#
# One direction of a digest-listing comparison, so the failure names the entry
# rather than printing two hundred digests. Both directions are wanted in
# different places, so the direction and its complaint are parameters.
assert_digest_lines_present() {
  local haystack="$1" needles="$2" label="$3" complaint="$4" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$haystack" == *"$line"* ]] || fail "$label: $complaint: ${line#* }"
  done <<< "$needles"
}
assert_preserved() {
  assert_digest_lines_present "$1" "$2" "$3" "this file was lost or rewritten"
}

# Equality, not survival: nothing changed, nothing removed, and nothing added.
# Used where the claim is that a tree was not touched at all, rather than that
# an operation which legitimately adds files did not destroy anything.
assert_tree_unchanged() {
  local after="$1" before="$2" label="$3"
  assert_digest_lines_present "$after" "$before" "$label" \
    "this entry was changed or removed"
  assert_digest_lines_present "$before" "$after" "$label" \
    "this entry appeared"
}
assert_preserved "$(preserved_digests)" "$preserved_before" \
  "migration left the project's own files byte for byte unchanged"
assert_file_marker() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" ]] || fail "$label: $path is gone"
  assert_contains "$(/bin/cat "$path")" "$expected" "$label"
}
assert_file_marker "$LEGACY_WS/project_state/plan.md" "$LEGACY_PLAN_MARKER" \
  "the project plan survived migration"
assert_file_marker "$LEGACY_WS/roles/pm.md" "$LEGACY_OVERLAY_MARKER" \
  "the project-local persona overlay survived migration"
assert_file_marker "$LEGACY_WS/project.json" '"domain": "distressed-tech"' \
  "the recorded domain survived migration"
assert_file_marker "$LEGACY_FLOW/config.json" "hand-tuned before the package existed" \
  "the operator's configuration survived migration"

# The same four observations, now produced by the wheel-installed command
# against a repository with no engine in it at all.
installed() {
  ( cd "$LEGACY_REPO" && "$PM_FLOW" "$@" )
}
assert_equals "$(installed status)" "$status_before" \
  "status reports the same project after migration"
assert_equals "$(installed list-sections)" "$sections_before" \
  "list-sections reports the same registry after migration"
assert_equals "$(installed config)" "$config_before" \
  "config resolves the same bindings and domain after migration"
assert_equals "$(installed cost)" "$cost_before" \
  "cost reports the same spend after migration"

assert_equals "$(query_attempts "$LEGACY_STORE")" "$attempts_before" \
  "previously recorded attempts remain queryable after migration"

# The obsolete command is gone rather than merely unused.
retired_upgrade="$(expect_failure "the retired upgrade command" \
  zsh -c 'cd "$1" && "$2" upgrade --source "$3"' zsh "$LEGACY_REPO" "$PM_FLOW" "$REPO_ROOT")"
assert_contains "$retired_upgrade" "unknown command: upgrade" \
  "the runtime upgrade command is no longer accepted"

# And the project carries on: the next step of the cycle the copied engine
# opened is taken by the installed command.
drain_project_work "$LEGACY_REPO" "$TEST_ROOT/legacy.flag"
migrated_tick="$(cd "$LEGACY_REPO" && PM_DONE_FLAG="$TEST_ROOT/legacy.flag" \
  PATH="$TEST_ROOT/flow-bin:$PATH" "$PM_FLOW" tick 2>&1)" || \
  fail "the installed command could not continue the migrated project:"$'\n'"$migrated_tick"
assert_contains "$migrated_tick" "section=$LEGACY_SECTION_KEY" \
  "the migrated project's own section was advanced"
assert_contains "$migrated_tick" "develop 001 -> result" \
  "the installed tick took the next step of the cycle the copied engine opened"
[[ -f "$LEGACY_SECTION/cycles/001/result.md" ]] || \
  fail "the continued cycle produced no result:"$'\n'"$migrated_tick"
assert_data_only "$LEGACY_FLOW" "the migrated repository after a tick"

printf 'PASS: a copied-engine repository migrates losslessly and keeps running\n'

# --- the installed package was never written to ------------------------------

assert_equals "$(engine_digests)" "$engine_before" \
  "neither initialisation nor migration changed a file inside the installed package"

printf 'PASS: initialisation and migration leave the installed package untouched\n'

# --- two repositories pinned to different versions ---------------------------
#
# The claim the copy-versioning machinery existed to make, now made by the
# package manager instead: two repositories run different engine versions at the
# same time, and upgrading one is `pip install --upgrade` with nothing to merge.
#
# Two *real* wheels, built the same offline way as the one above, from
# disposable copies of the checkout with a different VERSION stamped into each.
# The checkout's own VERSION is never touched - a test that edited the tree it
# is testing would be proving something about a tree nobody ships.
#
# Version evidence is only ever taken from `pm-flow version` run inside a
# repository. A wheel filename, a dist-info directory or a metadata field would
# say what was installed; only the command says what actually runs.

PINNED_OLD="0.7.1"
PINNED_NEW="0.7.2"

build_pinned_wheel() {
  local version="$1" source_copy="$2" wheel_dir="$3" item
  mkdir -p "$source_copy" "$wheel_dir"
  # Everything the wheel is built from: the build backend's configuration, the
  # version it reads, the package, and the engine it force-includes.
  for item in pyproject.toml README.md VERSION src template; do
    /bin/cp -R "$REPO_ROOT/$item" "$source_copy/$item"
  done
  printf '%s\n' "$version" > "$source_copy/VERSION"
  find "$source_copy" -name '__pycache__' -type d -prune -exec rm -rf {} +
  "$BUILD_VENV/bin/python" -m pip wheel \
    --no-index --no-build-isolation --no-deps \
    --disable-pip-version-check --no-input \
    --wheel-dir "$wheel_dir" "$source_copy" >> "$BUILD_LOG" 2>&1 || {
    /bin/cat "$BUILD_LOG" >&2
    fail "the offline build of pm-flow $version failed"
  }
  local built
  built="$(find "$wheel_dir" -maxdepth 1 -type f -name "pm_flow-${version}-*.whl")"
  [[ -f "$built" ]] || fail "no wheel for version $version was built in $wheel_dir"
  printf '%s\n' "$built"
}

install_pinned_venv() {
  local venv="$1" wheel="$2"
  python3 -m venv "$venv" >> "$BUILD_LOG" 2>&1 || {
    /bin/cat "$BUILD_LOG" >&2
    fail "creating the venv at $venv failed"
  }
  "$venv/bin/python" -m pip install \
    --quiet --no-index --no-deps \
    --disable-pip-version-check --no-input \
    "$wheel" >> "$BUILD_LOG" 2>&1 || {
    /bin/cat "$BUILD_LOG" >&2
    fail "installing $wheel into $venv failed"
  }
  [[ -x "$venv/bin/pm-flow" ]] || fail "$venv produced no pm-flow entry point"
}

# A repository holding project data only, driven by its own installed command.
# install.sh writes the data; the engine only ever arrives through the venv.
prepare_pinned_repo() {
  local repo="$1" key="$2" name="$3" section_key="$4" objective="$5" command="$6"
  mkdir -p "$repo"
  git -C "$repo" init --quiet
  "$REPO_ROOT/install.sh" "$repo" --name "$name" --project-key "$key" \
    --domain distressed-tech > "$TEST_ROOT/$key-install.out" 2>&1 || \
    fail "install.sh failed for $key:"$'\n'"$(/bin/cat "$TEST_ROOT/$key-install.out")"
  assert_data_only "$repo/.agentic/pm_flow" "the $key repository"
  bind_local_roles "$repo/.agentic/pm_flow/config.json"
  ( cd "$repo" && "$command" init-section "$section_key" \
    <<< "$(section_brief "$objective" "$key")" ) > "$TEST_ROOT/$key-section.out" 2>&1 || \
    fail "init-section failed for $key:"$'\n'"$(/bin/cat "$TEST_ROOT/$key-section.out")"
}

# One tick through the repository's own installed command, with the project-level
# queue drained first so the tick lands on the section rather than on a review.
advance_pinned_repo() {
  local repo="$1" key="$2" section_key="$3" command="$4" flag="$5" output
  drain_project_work "$repo" "$flag" "$command"
  output="$(cd "$repo" && PM_DONE_FLAG="$flag" PATH="$TEST_ROOT/flow-bin:$PATH" \
    "$command" tick 2>&1)" || \
    fail "the installed tick failed in $key:"$'\n'"$output"
  printf '%s\n' "$output"
}

WHEEL_OLD="$(build_pinned_wheel "$PINNED_OLD" "$TEST_ROOT/source-$PINNED_OLD" \
  "$TEST_ROOT/dist-$PINNED_OLD")" || exit 1
WHEEL_NEW="$(build_pinned_wheel "$PINNED_NEW" "$TEST_ROOT/source-$PINNED_NEW" \
  "$TEST_ROOT/dist-$PINNED_NEW")" || exit 1
[[ "$WHEEL_OLD" != "$WHEEL_NEW" ]] || \
  fail "both pinned versions built the same wheel: $WHEEL_OLD"

ALPHA_REPO="$TEST_ROOT/alpha repo"
ALPHA_VENV="$TEST_ROOT/alpha-venv"
ALPHA_PM="$ALPHA_VENV/bin/pm-flow"
ALPHA_KEY="alpha-ledger"
ALPHA_SECTION_KEY="alpha-cutover"
ALPHA_FLOW="$ALPHA_REPO/.agentic/pm_flow"
ALPHA_SECTION="$ALPHA_FLOW/$ALPHA_KEY/sections/$ALPHA_SECTION_KEY"
ALPHA_STORE="$ALPHA_FLOW/$ALPHA_KEY/runs/pm_flow.db"
ALPHA_FLAG="$TEST_ROOT/alpha.flag"

BETA_REPO="$TEST_ROOT/beta repo"
BETA_VENV="$TEST_ROOT/beta-venv"
BETA_PM="$BETA_VENV/bin/pm-flow"
BETA_KEY="beta-ledger"
BETA_SECTION_KEY="beta-cutover"
BETA_FLOW="$BETA_REPO/.agentic/pm_flow"
BETA_SECTION="$BETA_FLOW/$BETA_KEY/sections/$BETA_SECTION_KEY"
BETA_FLAG="$TEST_ROOT/beta.flag"

install_pinned_venv "$ALPHA_VENV" "$WHEEL_OLD"
install_pinned_venv "$BETA_VENV" "$WHEEL_NEW"

prepare_pinned_repo "$ALPHA_REPO" "$ALPHA_KEY" "Alpha Ledger" "$ALPHA_SECTION_KEY" \
  'Reconcile the alpha ledger against its documents.' "$ALPHA_PM"
prepare_pinned_repo "$BETA_REPO" "$BETA_KEY" "Beta Ledger" "$BETA_SECTION_KEY" \
  'Reconcile the beta ledger against its documents.' "$BETA_PM"

# Both installations exist at once, and both are asked in turn. Reading them
# back to back is the point: this is two live installs disagreeing about the
# version, not one install observed twice at different times.
alpha_version="$(cd "$ALPHA_REPO" && "$ALPHA_PM" version)" || \
  fail "the alpha repository's installed command could not report a version"
beta_version="$(cd "$BETA_REPO" && "$BETA_PM" version)" || \
  fail "the beta repository's installed command could not report a version"
alpha_version_line="$(printf '%s\n' "$alpha_version" | /usr/bin/head -n 1)"
beta_version_line="$(printf '%s\n' "$beta_version" | /usr/bin/head -n 1)"

# The independent-version claim, asserted before either version is checked
# against its pin: two repositories sharing one installation would still answer
# both commands, and would differ from the expected pins in only one of them.
[[ "$alpha_version_line" != "$beta_version_line" ]] || \
  fail "both repositories report the same running version: $alpha_version_line"
assert_equals "$alpha_version_line" "pm-flow $PINNED_OLD" \
  "the alpha repository runs the version its own venv was pinned to"
assert_equals "$beta_version_line" "pm-flow $PINNED_NEW" \
  "the beta repository runs the version its own venv was pinned to"

# And each runs out of its own venv rather than the other's or the checkout's.
pinned_engine_line() {
  printf '%s\n' "$1" | awk '/^ *engine:/ {sub(/^ *engine: */, ""); print; exit}'
}
assert_engine_beneath_venv() {
  local engine_path="$1" venv_path="$2" label="$3" venv_real
  venv_real="$(cd -P "$venv_path" && pwd -P)"
  case "$engine_path" in
    "$venv_real"/*|"$venv_path"/*) ;;
    *) fail "the $label repository's engine is not beneath its own venv: $engine_path" ;;
  esac
  assert_not_contains "$engine_path" "$REPO_ROOT" \
    "the $label repository's engine resolves outside the checkout"
}
alpha_engine="$(pinned_engine_line "$alpha_version")"
beta_engine="$(pinned_engine_line "$beta_version")"
assert_engine_beneath_venv "$alpha_engine" "$ALPHA_VENV" alpha
assert_engine_beneath_venv "$beta_engine" "$BETA_VENV" beta
[[ "$alpha_engine" != "$beta_engine" ]] || \
  fail "both repositories resolved the same engine directory: $alpha_engine"

# Reporting a version is not running one. Each repository advances its own
# section through its own installed command.
alpha_tick="$(advance_pinned_repo "$ALPHA_REPO" "$ALPHA_KEY" "$ALPHA_SECTION_KEY" \
  "$ALPHA_PM" "$ALPHA_FLAG")"
assert_contains "$alpha_tick" "section=$ALPHA_SECTION_KEY" \
  "the alpha repository advanced its own section"
assert_contains "$alpha_tick" "-> ASSIGN" \
  "the alpha repository's dispatch was acted on"
[[ -f "$ALPHA_SECTION/cycles/001/assignment.md" ]] || \
  fail "the alpha repository produced no assignment:"$'\n'"$alpha_tick"

beta_tick="$(advance_pinned_repo "$BETA_REPO" "$BETA_KEY" "$BETA_SECTION_KEY" \
  "$BETA_PM" "$BETA_FLAG")"
assert_contains "$beta_tick" "section=$BETA_SECTION_KEY" \
  "the beta repository advanced its own section"
assert_contains "$beta_tick" "-> ASSIGN" \
  "the beta repository's dispatch was acted on"
[[ -f "$BETA_SECTION/cycles/001/assignment.md" ]] || \
  fail "the beta repository produced no assignment:"$'\n'"$beta_tick"

# Neither repository acquired an engine by being driven, and neither section
# leaked into the other's repository.
assert_data_only "$ALPHA_FLOW" "the alpha repository after a tick"
assert_data_only "$BETA_FLOW" "the beta repository after a tick"
[[ ! -e "$ALPHA_FLOW/$BETA_KEY" && ! -e "$BETA_FLOW/$ALPHA_KEY" ]] || \
  fail "one repository's project appeared inside the other"

printf 'PASS: two repositories run independently pinned versions and drive their own projects\n'

# --- upgrading one repository -------------------------------------------------
#
# The upgrade is `pip install --upgrade` against the existing venv: the same
# installation, the same repository, the same `.agentic/` tree. Nothing is
# recreated, because recreating any of them would test a fresh install and call
# it an upgrade.

complete_tree_digest() {
  python3 "$TEST_ROOT/digest_tree.py" --complete "$1" "$1"
}
installed_tree_digest() {
  python3 "$TEST_ROOT/digest_tree.py" "$1" "$1/lib"
}

alpha_status_before="$(cd "$ALPHA_REPO" && "$ALPHA_PM" status)"
alpha_attempts_before="$(query_attempts "$ALPHA_STORE")" || \
  fail "the alpha repository recorded no queryable attempt before the upgrade"
beta_status_before="$(cd "$BETA_REPO" && "$BETA_PM" status)"
beta_installed_before="$(installed_tree_digest "$BETA_VENV")"
beta_tree_before="$(complete_tree_digest "$BETA_REPO/.agentic")"

# Captured last, so nothing this test does afterwards is mistaken for the
# upgrade's doing.
alpha_tree_before="$(complete_tree_digest "$ALPHA_REPO/.agentic")"
[[ -n "$alpha_tree_before" ]] || fail "the alpha repository has no .agentic tree to compare"

"$ALPHA_VENV/bin/python" -m pip install --upgrade \
  --no-index --no-deps --disable-pip-version-check --no-input \
  "$WHEEL_NEW" > "$TEST_ROOT/alpha-upgrade.log" 2>&1 || {
  /bin/cat "$TEST_ROOT/alpha-upgrade.log" >&2
  fail "pip install --upgrade failed in the alpha repository's venv"
}

alpha_version_after="$(cd "$ALPHA_REPO" && "$ALPHA_PM" version)" || \
  fail "the alpha repository's command stopped working after the upgrade"
alpha_line_after="$(printf '%s\n' "$alpha_version_after" | /usr/bin/head -n 1)"
[[ "$alpha_line_after" != "$alpha_version_line" ]] || \
  fail "the upgrade did not change the version the installed command runs: $alpha_line_after"
assert_equals "$alpha_line_after" "pm-flow $PINNED_NEW" \
  "the upgraded repository runs the newer package"

# Immediately, before anything else runs against this repository: an upgrade
# that touched project data would be doing exactly what the copy-versioning
# machinery had to be built to avoid.
assert_tree_unchanged "$(complete_tree_digest "$ALPHA_REPO/.agentic")" \
  "$alpha_tree_before" \
  "the package upgrade changed the repository's .agentic tree"

# The same project, still readable by the new version.
assert_equals "$(cd "$ALPHA_REPO" && "$ALPHA_PM" status)" "$alpha_status_before" \
  "the upgraded command reports the project it had before the upgrade"
assert_equals "$(query_attempts "$ALPHA_STORE")" "$alpha_attempts_before" \
  "the upgraded command reads the records the previous version wrote"

# And carries it forward: the next step of the cycle the older version opened.
upgraded_tick="$(advance_pinned_repo "$ALPHA_REPO" "$ALPHA_KEY" "$ALPHA_SECTION_KEY" \
  "$ALPHA_PM" "$ALPHA_FLAG")"
assert_contains "$upgraded_tick" "section=$ALPHA_SECTION_KEY" \
  "the upgraded command advanced the same section"
assert_contains "$upgraded_tick" "develop 001 -> result" \
  "the upgraded command took the next step of the cycle the older version opened"
[[ -f "$ALPHA_SECTION/cycles/001/result.md" ]] || \
  fail "the continued cycle produced no result:"$'\n'"$upgraded_tick"
assert_data_only "$ALPHA_FLOW" "the upgraded repository after a tick"

# The other repository was not part of any of this: not its version, not its
# installation, not its project data.
beta_version_after="$(cd "$BETA_REPO" && "$BETA_PM" version)" || \
  fail "the beta repository's command stopped working after the other was upgraded"
assert_equals "$(printf '%s\n' "$beta_version_after" | /usr/bin/head -n 1)" \
  "$beta_version_line" "upgrading one repository changed the other's running version"
assert_equals "$(installed_tree_digest "$BETA_VENV")" "$beta_installed_before" \
  "upgrading one repository rewrote a file in the other's installation"
assert_tree_unchanged "$(complete_tree_digest "$BETA_REPO/.agentic")" \
  "$beta_tree_before" "upgrading one repository changed the other's project data"
assert_equals "$(cd "$BETA_REPO" && "$BETA_PM" status)" "$beta_status_before" \
  "upgrading one repository changed the other's reported project state"

printf 'PASS: upgrading one repository changes its version, not its data and not the other repository\n'

# --- the documented workflow, run rather than read ---------------------------
#
# The last thing a checkout can be wrong about is what it tells a reader to do.
# Everything above proves the packaged layout works; this proves the README
# describes *that* layout and no longer describes the copy-versioning machinery
# that has been deleted.
#
# The documented commands are extracted and then executed against the artifacts
# the blocks above already built, rather than only matched as text: a README that
# names a command nobody can run is as wrong as one that names a deleted file.

README="$REPO_ROOT/README.md"
[[ -f "$README" ]] || fail "the checkout has no README.md"

# Instructions, not prose. A sentence may legitimately mention a retired name
# while explaining what replaced it; a line inside a shell block is something a
# reader is being told to type.
readme_commands="$(python3 - "$README" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
for block in re.findall(r"```(?:bash|sh|zsh|console)\n(.*?)```", text, re.S):
    for line in block.splitlines():
        # A trailing comment is annotation, not part of the command, and would
        # otherwise be word-split into the arguments this test runs.
        line = re.sub(r"\s+#.*$", "", line).strip()
        if line and not line.startswith("#"):
            print(line)
PY
)"
[[ -n "$readme_commands" ]] || fail "the README documents no commands at all"

# Whitespace-flattened, so an assertion about a sentence is not really an
# assertion about where the paragraph happened to wrap.
readme_flat="$(python3 -c \
  'import re, sys; print(re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8").read()))' \
  "$README")"

# Nothing a reader is told to type may reach for the machinery this section
# removed: a copied engine script, the retired runtime upgrade command, a root
# install record, or the generator that used to write one.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  case "$line" in
    *".agentic/pm_flow/pm_flow.sh"*|*"pm_flow.sh "*)
      fail "a README instruction invokes a copied engine script: $line" ;;
    *"tools/manifest.py"*|*"manifest.py"*)
      fail "a README instruction runs the retired manifest generator: $line" ;;
    *MANIFEST*|*manifest.json*)
      fail "a README instruction names a root install manifest: $line" ;;
  esac
  # `--upgrade pm-flow` is the package manager and is what the README should
  # say; `pm-flow upgrade` is the retired runtime command, which no longer
  # exists at all - the migrated repository above proved it is refused.
  case "$line" in
    *"pm-flow upgrade"*|*"upgrade --source"*)
      fail "a README instruction uses the retired upgrade command: $line" ;;
  esac
done <<< "$readme_commands"
assert_not_contains "$readme_flat" "tools/manifest.py" \
  "the README no longer describes the manifest generator"
assert_not_contains "$readme_flat" "MANIFEST" \
  "the README no longer describes a root install manifest"
assert_not_contains "$readme_flat" "manifest.json" \
  "the README no longer describes a generated manifest file"

# The boundary, stated where a reader will meet it.
assert_contains "$readme_flat" "the engine is the installed package" \
  "the README calls the package the engine"
assert_contains "$readme_flat" "\`.agentic/\` holds your project's own mutable data" \
  "the README calls .agentic/ the project's mutable data"
assert_contains "$readme_flat" "changes no file inside \`.agentic/\`" \
  "the README says an upgrade does not rewrite project data"

# Run what it documents. The executable path a README writes is a venv-relative
# one; the command and its arguments are what this executes, through the venv
# built at the top of this file.
documented_args() {
  local -a words
  words=( ${(z)${1#*pm-flow}} )
  printf '%s\n' "${words[@]}"
}

run_documented() {
  local line="$1" repo="$2"
  local -a words
  words=( ${(z)${line#*pm-flow}} )
  ( cd "$repo" && "$PM_FLOW" "${words[@]}" )
}

# The first documented line matching a command shape, or empty. `|| true`
# because a README that documents nothing of the sort is a failure this block
# reports itself, not a pipeline error that aborts the run before it can.
documented() {
  printf '%s\n' "$readme_commands" | grep -E "$1" | /usr/bin/head -n 1 || true
}

# Version reporting, through the installed command.
documented_version="$(documented '(^|/)pm-flow version$')"
[[ -n "$documented_version" ]] || \
  fail "the README documents no way to report the running version"
documented_version_output="$(run_documented "$documented_version" "$FIXTURE")" || \
  fail "the version command the README documents does not run: $documented_version"
assert_contains "$documented_version_output" "pm-flow " \
  "the documented version command reports the installed package"
documented_engine="$(printf '%s\n' "$documented_version_output" | \
  awk '/^ *engine:/ {sub(/^ *engine: */, ""); print; exit}')"
case "$documented_engine" in
  "$VENV_REAL"/*|"$VENV"/*) ;;
  *) fail "the documented version command reported an engine outside the venv: $documented_engine" ;;
esac

# Workflow execution, through the installed command, against a real repository.
documented_status="$(documented '(^|/)pm-flow status')"
documented_tick="$(documented '(^|/)pm-flow tick')"
documented_run="$(documented '(^|/)pm-flow (--project [^ ]+ )?run')"
[[ -n "$documented_status" && -n "$documented_tick" && -n "$documented_run" ]] || \
  fail "the README does not document status, tick and run through the installed command"

documented_status_output="$(run_documented "$documented_status" "$INIT_REPO")" || \
  fail "the status command the README documents does not run: $documented_status"
assert_contains "$documented_status_output" "$INIT_SECTION_KEY" \
  "the documented status command reports the repository's own section"

drain_project_work "$INIT_REPO" "$TEST_ROOT/init.flag"
documented_tick_args=( ${(f)"$(documented_args "$documented_tick")"} )
documented_tick_output="$(cd "$INIT_REPO" && PM_DONE_FLAG="$TEST_ROOT/init.flag" \
  PATH="$TEST_ROOT/flow-bin:$PATH" "$PM_FLOW" "${documented_tick_args[@]}" 2>&1)" || \
  fail "the tick command the README documents does not run:"$'\n'"$documented_tick_output"
assert_contains "$documented_tick_output" "section=$INIT_SECTION_KEY" \
  "the documented tick advanced the repository's own section"
assert_data_only "$INIT_FLOW" "the repository driven by the documented commands"

# Upgrades, through the package manager. Asserted on the documented line, and
# the mechanism itself is what the pinned-version block above already exercised.
documented_upgrade="$(documented 'pip install (--upgrade|-U)|uv (tool )?(install|upgrade)')"
[[ -n "$documented_upgrade" ]] || \
  fail "the README documents no package-manager upgrade"
assert_contains "$documented_upgrade" "pm-flow" \
  "the documented upgrade names the package"

# And the checkout has no generator left to regenerate what it stopped
# describing. Searched by name and by content, so a rename or an equivalent
# rewrite is caught rather than only the file that used to be there.
[[ ! -e "$REPO_ROOT/tools/manifest.py" ]] || \
  fail "the checkout still ships the obsolete root-MANIFEST generator at tools/manifest.py"
[[ ! -e "$REPO_ROOT/MANIFEST" && ! -e "$REPO_ROOT/manifest.json" ]] || \
  fail "the checkout still ships a root install manifest"
manifest_tooling="$(find "$REPO_ROOT" \
  \( -name .git -o -name tests -o -name .agentic -o -name '__pycache__' \) -prune -o \
  -type f \( -name 'MANIFEST' -o -name 'manifest.json' -o -name '*manifest*.py' \) -print \
  2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
assert_equals "$manifest_tooling" "" \
  "the checkout provides no obsolete root-MANIFEST generator"
manifest_writers="$(grep -rlI 'MANIFEST' "$REPO_ROOT" \
  --exclude-dir=.git --exclude-dir=tests --exclude-dir=.agentic \
  --exclude-dir=__pycache__ --exclude=.git 2>/dev/null || true)"
manifest_writers="$(printf '%s' "$manifest_writers" | LC_ALL=C sort | tr '\n' ' ')"
assert_equals "$manifest_writers" "" \
  "no file in the checkout still writes or reads a root MANIFEST"

printf 'PASS: the documented workflow runs through the installed command, and no manifest machinery remains\n'
