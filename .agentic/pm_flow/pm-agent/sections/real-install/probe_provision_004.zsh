#!/bin/zsh
# PM review probe, cycle 004: (a) every runbook pip call is offline;
# (b) the provision version assertion has an exit-code consequence.
set -uo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-004b.XXXXXX")"
print -r -- "probe_root=$ROOT"

for name in ${(k)parameters[(I)PM_FLOW_*]}; do unset "$name"; done
unset VIRTUAL_ENV PYTHONPATH PYTHONHOME PYTHONSTARTUP
for name in ${(k)parameters[(I)PIP_*]} ${(k)parameters[(I)UV_*]}; do unset "$name"; done
export PIP_CACHE_DIR="$ROOT/pip-cache"
export XDG_CACHE_HOME="$ROOT/xdg-cache"
export PIP_CONFIG_FILE="$ROOT/pip.conf"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
: > "$PIP_CONFIG_FILE"

RUNBOOK="$ROOT/runbook.zsh"
sed -n '/^<!-- runbook:begin -->/,/^<!-- runbook:end -->/p' \
  "$WT/docs/real-install.md" | sed '1d;$d;/^```/d' > "$RUNBOOK"
chmod +x "$RUNBOOK"

print -r -- '--- check_result definition ---'
sed -n '/^check_result()/,/^}/p' "$RUNBOOK"

print -r -- '--- every pip invocation with its continuation lines ---'
grep -A3 -n 'm pip install\|m pip wheel' "$RUNBOOK"

print -r -- '--- mutation: expected version forced to 9.9.9, nothing else changed ---'
MUTATED="$ROOT/runbook-mutated.zsh"
sed 's|^  wheel_version="${wheel_version%%-\*}"$|  wheel_version="${wheel_version%%-*}"\n  wheel_version=9.9.9|' \
  "$RUNBOOK" > "$MUTATED"
chmod +x "$MUTATED"
diff "$RUNBOOK" "$MUTATED"

FIXTURE="$ROOT/fixture"
"$WT/tests/fixtures/real_install/build_fixture.sh" "$WT" "$FIXTURE" || exit 1

"$MUTATED" provision \
  --repo "$FIXTURE" \
  --install-sh "$WT/install.sh" \
  --out "$ROOT/out" > "$ROOT/provision-mutated.log" 2>&1
print -r -- "mutated_provision_exit=$?"
grep -n 'pm_flow_wheel=\|pm_flow_version=\|provision=ok\|ERROR' "$ROOT/provision-mutated.log"
