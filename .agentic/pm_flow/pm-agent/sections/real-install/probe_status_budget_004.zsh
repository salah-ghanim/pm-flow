#!/bin/zsh
# PM review probe, cycle 004: does status_phase's write budget actually fail
# when something outside the store changes during the status run?
set -uo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-004.XXXXXX")"
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
export ZDOTDIR="$ROOT/zdotdir"
mkdir -p "$ZDOTDIR"

FIXTURE="$ROOT/fixture"
"$WT/tests/fixtures/real_install/build_fixture.sh" "$WT" "$FIXTURE" || exit 1

RUNBOOK="$ROOT/runbook.zsh"
sed -n '/^<!-- runbook:begin -->/,/^<!-- runbook:end -->/p' \
  "$WT/docs/real-install.md" | sed '1d;$d;/^```/d' > "$RUNBOOK"
chmod +x "$RUNBOOK"

print -r -- '--- pip invocations in the extracted runbook ---'
grep -n 'pip install\|pip wheel' "$RUNBOOK"

OUT="$ROOT/out"
mkdir -p "$OUT"
print -r -- '--- baseline: all (no --pm-flow, no --wheel) ---'
"$RUNBOOK" all \
  --repo "$FIXTURE" \
  --project-key beta \
  --name "Probe Fixture" \
  --install-sh "$WT/install.sh" \
  --out "$OUT" \
  --backup-root "$ROOT/backups" > "$ROOT/all.log" 2>&1
print -r -- "all_exit=$?"
grep -n 'provision=ok\|pm_flow_wheel=\|pm_flow_version=\|status_wrote=\|store=\|status_in_place=ok' "$ROOT/all.log"

print -r -- '--- control A: unmutated status re-run on the migrated tree ---'
"$RUNBOOK" status \
  --repo "$FIXTURE" \
  --project-key beta \
  --install-sh "$WT/install.sh" \
  --out "$OUT" > "$ROOT/status-clean.log" 2>&1
print -r -- "clean_status_exit=$?"
grep -n 'status_wrote=\|store=\|status_in_place=ok\|ERROR' "$ROOT/status-clean.log"

print -r -- '--- control B: identical run, one stray write injected into the status step ---'
MUTATED="$ROOT/runbook-mutated.zsh"
sed 's|(cd "$repo" \&\& "$pm_flow" status)|(cd "$repo" \&\& "$pm_flow" status \&\& touch "$repo/stray-write.txt")|' \
  "$RUNBOOK" > "$MUTATED"
chmod +x "$MUTATED"
diff "$RUNBOOK" "$MUTATED"
"$MUTATED" status \
  --repo "$FIXTURE" \
  --project-key beta \
  --install-sh "$WT/install.sh" \
  --out "$OUT" > "$ROOT/status-mutated.log" 2>&1
print -r -- "mutated_status_exit=$?"
grep -n 'status_wrote=\|status_in_place=ok\|ERROR\|FAIL' "$ROOT/status-mutated.log"
