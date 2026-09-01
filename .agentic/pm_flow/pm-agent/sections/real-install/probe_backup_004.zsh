#!/bin/zsh
# PM review probe, cycle 004: transcript markers and the .venv backup exclusion,
# read out of the completed default-path `all` run.
set -uo pipefail
ROOT=/var/folders/9x/9xzxgmhn75q66kr2x3n691hw0000gn/T/pm-review-004.ZaBVuv

print -r -- '--- phase headers and migration markers from the all run ---'
grep -n '=== phase:\|^backup=\|backup_verified=\|removed_copied_engine=\|^migrated=\|renames_recorded=\|^verify=ok' "$ROOT/all.log"

print -r -- '--- .venv present in the repo, absent from the backup ---'
BACKUP="$(sed -n 's/^backup=//p' "$ROOT/all.log" | tail -n 1)"
print -r -- "backup=$BACKUP"
print -r -- "repo_venv_pm_flow=$([[ -x "$ROOT/fixture/.venv/bin/pm-flow" ]] && print present || print absent)"
print -r -- "backup_venv=$([[ -e "$BACKUP/.venv" ]] && print present || print absent)"
print -r -- "backup_git=$([[ -d "$BACKUP/.git" ]] && print present || print absent)"
print -r -- "backup_flow=$([[ -d "$BACKUP/agentic/pm_flow" ]] && print present || print absent)"
grep -c . "$ROOT/out/backup-source-manifest.txt"
grep -c '\.venv' "$ROOT/out/backup-source-manifest.txt"

print -r -- '--- survey manifest digests unchanged after the in-place status ---'
grep -c . "$ROOT/out/survey-manifest.txt"
grep -n 'surveyed project data' "$ROOT/status-clean.log"
print -r -- "clean_rerun_tail=$(tail -n 2 "$ROOT/status-clean.log")"

print -r -- '--- git state of the migrated fixture after status ---'
git --no-optional-locks -C "$ROOT/fixture" status --short
