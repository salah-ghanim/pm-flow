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
