#!/bin/zsh -f
# Cycle 003 review probe: does the published runbook's `verify` phase actually
# fail when project data is lost, when a copied engine survives, and does
# `survey` really leave --repo untouched?
set -uo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-runbook-probe.XXXXXX")"
print -r -- "probe_root=$TMP"

RUNBOOK="$TMP/runbook.zsh"
sed -n '/^<!-- runbook:begin -->/,/^<!-- runbook:end -->/p' "$WT/docs/real-install.md" \
  | sed '1d;$d;/^```/d' > "$RUNBOOK"
chmod +x "$RUNBOOK"
print -r -- "runbook_lines=$(wc -l < "$RUNBOOK" | tr -d ' ')"

digest_repo() {
  python3 - "$1" <<'PY'
import hashlib, sys
from pathlib import Path
base = Path(sys.argv[1])
for p in sorted(base.rglob("*")):
    if p.is_file():
        print(hashlib.sha256(p.read_bytes()).hexdigest(), p.relative_to(base))
PY
}

print '--- CASE 1: survey is read-only, then data loss is caught by verify ---'
A="$TMP/repoA"
"$WT/tests/fixtures/real_install/build_fixture.sh" "$WT" "$A" > "$TMP/buildA.log" 2>&1 \
  || { print -u2 'build_fixture failed'; /bin/cat "$TMP/buildA.log"; exit 1 }

digest_repo "$A" > "$TMP/A.before"
"$RUNBOOK" survey --repo "$A" --install-sh "$WT/install.sh" --out "$TMP/outA" \
  > "$TMP/A.survey.log" 2>&1
print -r -- "survey_exit=$?"
digest_repo "$A" > "$TMP/A.after"
if cmp -s "$TMP/A.before" "$TMP/A.after"; then
  print 'survey_read_only=yes'
else
  print 'survey_read_only=NO'
  diff "$TMP/A.before" "$TMP/A.after" | head -n 20
fi
grep -E '^(git_worktree|agentic_tracked|flow_dir|workspace_count|workspaces|collision|copied_engine_present|pm_flow_version)=' "$TMP/A.survey.log"

"$RUNBOOK" backup --repo "$A" --install-sh "$WT/install.sh" --out "$TMP/outA" \
  --backup-root "$TMP/backupsA" > "$TMP/A.backup.log" 2>&1
print -r -- "backup_exit=$?"
grep -E '^(backup_files|backup_verified)=' "$TMP/A.backup.log"

# MUTATION: silently rewrite one surveyed, non-selected workspace file.
print -r -- 'CORRUPTED BY PROBE' > "$A/agentic/pm_flow/alpha/project_state/plan.md"

"$RUNBOOK" migrate --repo "$A" --project-key beta --install-sh "$WT/install.sh" \
  --out "$TMP/outA" > "$TMP/A.migrate.log" 2>&1
print -r -- "migrate_exit=$?"
grep -E '^(removed_copied_engine|migrated)=' "$TMP/A.migrate.log"

"$RUNBOOK" verify --repo "$A" --project-key beta --install-sh "$WT/install.sh" \
  --out "$TMP/outA" > "$TMP/A.verify.log" 2>&1
print -r -- "verify_exit_after_data_loss=$?"
grep -E 'surveyed project data was lost|digests match|verify=ok' "$TMP/A.verify.log"

print '--- CASE 2: a copied engine replanted after migration is caught by verify ---'
B="$TMP/repoB"
"$WT/tests/fixtures/real_install/build_fixture.sh" "$WT" "$B" > "$TMP/buildB.log" 2>&1 \
  || { print -u2 'build_fixture failed'; /bin/cat "$TMP/buildB.log"; exit 1 }
"$RUNBOOK" survey --repo "$B" --install-sh "$WT/install.sh" --out "$TMP/outB" \
  > "$TMP/B.survey.log" 2>&1
"$RUNBOOK" backup --repo "$B" --install-sh "$WT/install.sh" --out "$TMP/outB" \
  --backup-root "$TMP/backupsB" > "$TMP/B.backup.log" 2>&1
"$RUNBOOK" migrate --repo "$B" --project-key beta --install-sh "$WT/install.sh" \
  --out "$TMP/outB" > "$TMP/B.migrate.log" 2>&1
print -r -- "B_migrate_exit=$?"
print -r -- '#!/bin/zsh' > "$B/.agentic/pm_flow/pm_flow.sh"
"$RUNBOOK" verify --repo "$B" --project-key beta --install-sh "$WT/install.sh" \
  --out "$TMP/outB" > "$TMP/B.verify.log" 2>&1
print -r -- "verify_exit_with_replanted_engine=$?"
grep -E '^copied_engine_remaining=|copied engine survives|verify=ok' "$TMP/B.verify.log"

print '--- CASE 3: the migrate phase refuses without the backup manifest ---'
"$RUNBOOK" migrate --repo "$B" --project-key beta --install-sh "$WT/install.sh" \
  --out "$TMP/outC" > "$TMP/C.migrate.log" 2>&1
print -r -- "migrate_exit_without_backup=$?"
grep -E 'missing verified backup manifest' "$TMP/C.migrate.log"
print -r -- "probe_root=$TMP"
