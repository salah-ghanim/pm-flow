#!/bin/zsh -f
# schema_migration: a store written by the committed version-1 store.py opens
# under this engine's store.py at version 2, backed up first, with every id kept.
# Run by tests/knowledge_state_test.sh, which exports REPO_ROOT, FLOW, TEST_ROOT.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
: "${REPO_ROOT:?}" "${FLOW:?}" "${TEST_ROOT:?}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  [[ "$actual" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$actual'"
}

# sql <db> <query>: rows, tab-separated. Read-only, so inspecting a file cannot
# be what changes it.
sql() {
  python3 - "$1" "$2" <<'PY'
import sqlite3, sys
from pathlib import Path
connection = sqlite3.connect(f"{Path(sys.argv[1]).resolve().as_uri()}?mode=ro", uri=True)
for row in connection.execute(sys.argv[2]):
    print("\t".join("" if value is None else str(value) for value in row))
connection.close()
PY
}

mtime() {
  python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"
}

sha256() {
  python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

NEW_TABLES=(principals timelines state_transactions state_changes jobs
  checkpoints timeline_sources experiment_arms experiment_replicates
  task_revisions task_assignments executions environment_revisions human_gates)

# ---------------------------------------------------------- version-1 engine
#
# The version-1 store.py comes from history, never retyped. Walk back from HEAD
# to the newest committed store.py still at version 1: HEAD itself until this
# migration is committed, the commit before it afterwards.
STORE_REL="template/.agentic/pm_flow/store.py"
V1_ENGINE="$TEST_ROOT/engine-v1"
mkdir -p "$V1_ENGINE"
v1_commit=""
for commit in ${(f)"$(git -C "$REPO_ROOT" rev-list HEAD -- "$STORE_REL")"}; do
  git -C "$REPO_ROOT" show "$commit:$STORE_REL" > "$V1_ENGINE/store.py"
  if grep -qx 'SCHEMA_VERSION = 1' "$V1_ENGINE/store.py"; then
    v1_commit="$commit"
    break
  fi
done
[[ -n "$v1_commit" ]] || fail "no committed store.py at schema version 1"

# make_v1_store <db>: one project, one task and one attempt written by the
# version-1 engine; prints their ids. Each table's first row is deleted, so the
# kept ids are 2 and a renumbering rebuild cannot pass by coincidence.
make_v1_store() {
  python3 - "$V1_ENGINE" "$1" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import store
assert Path(store.__file__).resolve().parent == Path(sys.argv[1]).resolve(), store.__file__
assert store.SCHEMA_VERSION == 1, store.SCHEMA_VERSION
connection = store.connect(sys.argv[2])
now = store.now()
with connection:
    connection.execute(
        "INSERT INTO projects (key, created_at) VALUES ('discarded', ?)", (now,))
    connection.execute("DELETE FROM projects WHERE key = 'discarded'")
    project = connection.execute(
        "INSERT INTO projects (key, name, created_at) VALUES ('ledger', 'Ledger', ?)",
        (now,)).lastrowid
    connection.execute(
        "INSERT INTO tasks (project_id, key, created_at) VALUES (?, 'discarded', ?)",
        (project, now))
    connection.execute("DELETE FROM tasks WHERE key = 'discarded'")
    task = connection.execute(
        "INSERT INTO tasks (project_id, key, title, status, created_at)"
        " VALUES (?, 'alpha', 'Alpha', 'in_progress', ?)", (project, now)).lastrowid
    connection.execute(
        "INSERT INTO attempts (project_id, task_id, role_key, label)"
        " VALUES (?, ?, 'developer', 'discarded')", (project, task))
    connection.execute("DELETE FROM attempts WHERE label = 'discarded'")
    attempt = connection.execute(
        "INSERT INTO attempts (project_id, task_id, role_key, label, cost_usd)"
        " VALUES (?, ?, 'developer', 'first', 0.25)", (project, task)).lastrowid
connection.close()
print(project, task, attempt)
PY
}

# open_store <db>: store.connect through the engine under test, nothing else.
open_store() {
  python3 - "$FLOW" "$1" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import store
assert Path(store.__file__).resolve().parent == Path(sys.argv[1]).resolve(), store.__file__
store.connect(sys.argv[2]).close()
PY
}

DB="$TEST_ROOT/project/runs/pm_flow.db"
BACKUP="$DB.v1.bak"
ids="$(make_v1_store "$DB")"
assert_eq "$ids" "2 2 2" "version-1 fixture ids"
TAB=$'\t'
IDS_ROW="${ids// /$TAB}"
assert_eq "$(sql "$DB" 'SELECT version FROM schema_version')" "1" \
  "fixture store is at version 1"
[[ ! -e "$BACKUP" ]] || fail "a backup exists before any migration"

# ------------------------------------------------------------ dry run is read-only
before_hash="$(sha256 "$DB")"
plan="$(python3 "$FLOW/state_service/cli.py" migrate --db "$DB" --dry-run)"
plan_summary="$(python3 -c '
import json, sys
plan = json.loads(sys.argv[1])
print(plan["current_version"], plan["target_version"], len(plan["steps"]))
for step in plan["steps"]:
    tables = "tables-match" if sorted(step["adds_tables"]) == sorted(sys.argv[2].split()) \
        else "tables=" + ",".join(step["adds_tables"])
    print(step["version"], step["backup"], tables)
' "$plan" "${NEW_TABLES[*]}")"
assert_eq "$plan_summary" "1 2 1"$'\n'"2 $BACKUP tables-match" "dry-run plan"
assert_eq "$(sha256 "$DB")" "$before_hash" "dry run leaves the store file unchanged"
assert_eq "$(sql "$DB" 'SELECT version FROM schema_version')" "1" \
  "dry run leaves schema_version at 1"
[[ ! -e "$BACKUP" ]] || fail "dry run wrote a backup"

missing_status=0
missing_output="$(python3 "$FLOW/state_service/cli.py" migrate \
  --db "$TEST_ROOT/absent/pm_flow.db" --dry-run)" || missing_status=$?
[[ "$missing_status" -ne 0 ]] || fail "dry run on a missing store exited 0"
[[ "$missing_output" == *'"error": "migration_failed"'* ]] || \
  fail "dry run on a missing store printed no error: $missing_output"
[[ ! -e "$TEST_ROOT/absent" ]] || fail "dry run created a missing store"

# ------------------------------------------------------ migration on open
open_store "$DB"
[[ -f "$BACKUP" ]] || fail "opening a version-1 store left no $BACKUP"
backup_mtime="$(mtime "$BACKUP")"

assert_eq "$(sql "$DB" 'SELECT version FROM schema_version')" "2" \
  "migrated schema_version"
assert_eq "$(sql "$BACKUP" 'SELECT version FROM schema_version')" "1" \
  "backup opens at version 1"
assert_eq "$(sql "$BACKUP" "SELECT COUNT(*) FROM sqlite_master WHERE name = 'timelines'")" \
  "0" "backup holds no version-2 table"

ids_query="SELECT p.id, t.id, a.id FROM projects p
  JOIN tasks t ON t.project_id = p.id AND t.key = 'alpha'
  JOIN attempts a ON a.task_id = t.id AND a.label = 'first'
  WHERE p.key = 'ledger'"
counts_query="SELECT (SELECT COUNT(*) FROM projects), (SELECT COUNT(*) FROM tasks),
  (SELECT COUNT(*) FROM attempts)"
assert_eq "$(sql "$DB" "$ids_query")" "$IDS_ROW" "ids unchanged by migration"
assert_eq "$(sql "$DB" "$counts_query")" $'1\t1\t1' "row counts unchanged by migration"
assert_eq "$(sql "$BACKUP" "$ids_query")" "$IDS_ROW" "backup ids"

tables="$(sql "$DB" "SELECT name FROM sqlite_master WHERE type = 'table'")"
for table in "${NEW_TABLES[@]}"; do
  printf '%s\n' "$tables" | grep -Fx "$table" >/dev/null || \
    fail "sqlite_master has no table $table"
done

# Every required uniqueness rule, read back from the schema as table(columns)
# plus the partial-index predicate, so a misnamed or non-unique index fails.
unique_indexes="$(python3 - "$DB" <<'PY'
import sqlite3, sys
from pathlib import Path
connection = sqlite3.connect(f"{Path(sys.argv[1]).resolve().as_uri()}?mode=ro", uri=True)
tables = [row[0] for row in connection.execute(
    "SELECT name FROM sqlite_master WHERE type = 'table'")]
for table in tables:
    for _, name, unique, _, partial in connection.execute(
            "SELECT seq, name, \"unique\", origin, partial FROM pragma_index_list(?)", (table,)):
        if not unique:
            continue
        # An expression column (topologies_identity's COALESCE) has no name.
        columns = ",".join(row[0] or "<expr>" for row in connection.execute(
            "SELECT name FROM pragma_index_info(?) ORDER BY seqno", (name,)))
        line = f"{table}({columns})"
        if partial:
            ddl = connection.execute(
                "SELECT sql FROM sqlite_master WHERE name = ?", (name,)).fetchone()[0]
            line += " WHERE " + ddl.split("WHERE", 1)[1].strip()
        print(line)
connection.close()
PY
)"
for rule in \
  'timelines(project_id,key)' \
  "timelines(project_id) WHERE purpose = 'production'" \
  'timelines(experiment_arm_id,replicate)' \
  'experiment_replicates(experiment_arm_id,replicate)' \
  'state_transactions(timeline_id,seq)' \
  'state_transactions(timeline_id,idempotency_key)' \
  'state_changes(transaction_id,ordinal)' \
  'jobs(timeline_id,idempotency_key)'; do
  printf '%s\n' "$unique_indexes" | grep -Fx "$rule" >/dev/null || \
    fail "no unique index $rule"
done

assert_eq "$(sql "$DB" "SELECT authority_mode FROM projects WHERE key = 'ledger'")" \
  "legacy" "existing project authority_mode"
assert_eq "$(sql "$DB" "SELECT timeline_id IS NULL, version IS NULL, updated_at IS NULL,
  updated_txn_id IS NULL FROM tasks WHERE key = 'alpha'")" $'1\t1\t1\t1' \
  "existing task keeps NULL timeline columns"
assert_eq "$(sql "$DB" "SELECT group_concat(name, ',') FROM pragma_table_info('task_dependencies')")" \
  "task_id,depends_on_id,timeline_id,created_txn_id" "task_dependencies columns"

in_scope="'${(j:', ':)NEW_TABLES}', 'tasks', 'task_dependencies'"
assert_eq "$(sql "$DB" "SELECT m.name || '.' || c.name
  FROM sqlite_master m, pragma_table_info(m.name) c
  WHERE m.type = 'table' AND m.name IN ($in_scope)
    AND c.name LIKE '%\\_id' ESCAPE '\\'
    AND c.name NOT IN ('subject_id', 'entity_id')
    AND NOT EXISTS (SELECT 1 FROM pragma_foreign_key_list(m.name) f
                    WHERE f.\"from\" = c.name)")" "" \
  "every *_id column but the polymorphic ones has a foreign key"
assert_eq "$(sql "$DB" "SELECT m.name || '.' || f.\"from\" || ' -> ' || f.\"table\"
  FROM sqlite_master m, pragma_foreign_key_list(m.name) f
  WHERE m.type = 'table'
    AND f.\"table\" NOT IN (SELECT name FROM sqlite_master WHERE type = 'table')")" "" \
  "no foreign key names a missing table"
assert_eq "$(sql "$DB" 'PRAGMA foreign_key_check')" "" "foreign_key_check"

# ------------------------------------------- a version-2 store opens unchanged
store_hash="$(sha256 "$DB")"
open_store "$DB"
assert_eq "$(sql "$DB" 'SELECT version FROM schema_version')" "2" \
  "second open keeps schema_version"
assert_eq "$(sha256 "$DB")" "$store_hash" "second open leaves the store file unchanged"
assert_eq "$(mtime "$BACKUP")" "$backup_mtime" "second open leaves the backup mtime"
assert_eq "$(sql "$BACKUP" 'SELECT version FROM schema_version')" "1" \
  "second open leaves the backup at version 1"
[[ ! -e "$DB.v2.bak" ]] || fail "second open took a backup"

# --------------------------------------- a new store is the same version 2
FRESH="$TEST_ROOT/fresh/runs/pm_flow.db"
open_store "$FRESH"
assert_eq "$(sql "$FRESH" 'SELECT version FROM schema_version')" "2" \
  "new store schema_version"
assert_eq "$(sql "$FRESH" 'SELECT COUNT(*) FROM schema_version')" "1" \
  "new store has one version row"
[[ -z "$(print -l "${FRESH:h}"/*.bak(N))" ]] || fail "new store took a backup"
shape_query="SELECT m.type || ' ' || m.name || ' ' || COALESCE((
    SELECT group_concat(c.name || ':' || c.type || ':' || c.\"notnull\" || ':'
                        || COALESCE(c.dflt_value, ''), ',')
    FROM pragma_table_info(m.name) c), '')
  FROM sqlite_master m WHERE m.name NOT LIKE 'sqlite_%' ORDER BY m.type, m.name"
assert_eq "$(sql "$FRESH" "$shape_query")" "$(sql "$DB" "$shape_query")" \
  "new and migrated stores have the same schema"

# ------------------------------------------------ a failed backup aborts
#
# A directory where the backup must land means the copy cannot be put in
# place. The open must fail before any DDL, leaving a whole version-1 store.
BLOCKED="$TEST_ROOT/blocked/runs/pm_flow.db"
make_v1_store "$BLOCKED" >/dev/null
mkdir -p "$BLOCKED.v1.bak"
blocked_status=0
open_store "$BLOCKED" 2> "$TEST_ROOT/blocked.stderr" || blocked_status=$?
[[ "$blocked_status" -ne 0 ]] || fail "open succeeded without a backup"
grep -F "could not back up store to $BLOCKED.v1.bak" "$TEST_ROOT/blocked.stderr" \
  >/dev/null || fail "failed backup was not reported: $(<"$TEST_ROOT/blocked.stderr")"
assert_eq "$(sql "$BLOCKED" 'SELECT version FROM schema_version')" "1" \
  "failed backup leaves schema_version at 1"
assert_eq "$(sql "$BLOCKED" "SELECT COUNT(*) FROM sqlite_master WHERE name IN ('principals', 'timelines', 'jobs')")" \
  "0" "failed backup ran no DDL"
assert_eq "$(sql "$BLOCKED" "SELECT COUNT(*) FROM pragma_table_info('projects') WHERE name = 'authority_mode'")" \
  "0" "failed backup altered no existing table"
[[ -z "$(print -l "$BLOCKED".v1.bak?*(N))" ]] || \
  fail "failed backup left a partial copy: $(print -l "$BLOCKED".v1.bak?*(N))"
rmdir "$BLOCKED.v1.bak"
open_store "$BLOCKED"
assert_eq "$(sql "$BLOCKED" 'SELECT version FROM schema_version')" "2" \
  "store migrates once the backup can be written"
[[ -f "$BLOCKED.v1.bak" ]] || fail "retried migration left no backup"

# ------------------------------------------------------------ apply on request
APPLY_DB="$TEST_ROOT/apply/runs/pm_flow.db"
make_v1_store "$APPLY_DB" >/dev/null
applied="$(python3 "$FLOW/state_service/cli.py" migrate --db "$APPLY_DB" --apply)"
assert_eq "$(python3 -c '
import json, sys
result = json.loads(sys.argv[1])
print(result["previous_version"], result["version"], *result["backups"])
' "$applied")" "1 2 $APPLY_DB.v1.bak" "apply result"
[[ -f "$APPLY_DB.v1.bak" ]] || fail "apply reported a backup that does not exist"
assert_eq "$(sql "$APPLY_DB" 'SELECT version FROM schema_version')" "2" \
  "apply schema_version"
assert_eq "$(sql "$APPLY_DB" "$ids_query")" "$IDS_ROW" "apply keeps ids"
