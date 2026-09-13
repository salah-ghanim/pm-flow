"""`apply`: one versioned request, one transaction on one timeline.

A request is validated before the store is touched. It then runs under one
`BEGIN IMMEDIATE`: the log row, every change row, the projection writes, the
head and version advance and the projection hash all commit together, or a
`StateError` rolls every one of them back.

Replaying an idempotency key returns the first commit's result, recomputed from
its log row rather than stored separately: `transaction_id`, `seq` and
`projection_hash` are columns, `changes` counts its change rows, and
`timeline_version` follows from the rule that every transaction advances
`head_seq` and `version` together by one, so the timeline's version at `seq` is
`version - (head_seq - seq)`.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import store
from state_service import projection, reducer
from state_service.errors import CONFLICT, INVALID_CONTRACT, INVALID_REFERENCE, StateError

REQUEST_VERSION = 1

_ENVELOPE_KEYS = {"request_version", "project", "actor", "timeline", "scope",
                  "idempotency_key", "expected_version", "operations"}


@dataclass(frozen=True)
class Envelope:
    project: str
    actor_key: str
    actor_kind: str
    timeline: str
    scope: frozenset | None
    idempotency_key: str
    expected_version: int | None
    operations: list


def _integer(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _nonempty(request: dict, name: str) -> str:
    if name not in request:
        raise StateError(INVALID_CONTRACT, f"missing {name}")
    if not isinstance(request[name], str) or not request[name]:
        raise StateError(INVALID_CONTRACT, f"{name} must be a non-empty string")
    return request[name]


def validate(request) -> Envelope:
    """The envelope's shape, or `invalid_contract`. Operation arguments are
    validated by their reducers."""
    if not isinstance(request, dict):
        raise StateError(INVALID_CONTRACT, "request must be a JSON object")
    unknown = sorted(set(request) - _ENVELOPE_KEYS)
    if unknown:
        raise StateError(INVALID_CONTRACT, f"unknown request fields: {', '.join(unknown)}")
    version = request.get("request_version")
    if not _integer(version) or version != REQUEST_VERSION:
        raise StateError(INVALID_CONTRACT, f"request_version must be {REQUEST_VERSION}")
    project = _nonempty(request, "project")
    actor = request.get("actor")
    if (not isinstance(actor, dict) or set(actor) != {"key", "kind"}
            or not all(isinstance(actor[k], str) and actor[k] for k in ("key", "kind"))):
        raise StateError(INVALID_CONTRACT, "actor must be {\"key\", \"kind\"}, both non-empty strings")
    timeline = _nonempty(request, "timeline")
    scope = request.get("scope")
    if scope == "*":
        scope = None
    elif (isinstance(scope, dict) and set(scope) == {"tasks"}
          and isinstance(scope["tasks"], list)
          and all(isinstance(key, str) and key for key in scope["tasks"])):
        scope = frozenset(scope["tasks"])
    else:
        raise StateError(INVALID_CONTRACT, "scope must be \"*\" or {\"tasks\": [task keys]}")
    idempotency_key = _nonempty(request, "idempotency_key")
    expected_version = request.get("expected_version")
    if expected_version is not None and (not _integer(expected_version) or expected_version < 0):
        raise StateError(INVALID_CONTRACT, "expected_version must be a non-negative integer")
    operations = request.get("operations")
    if not isinstance(operations, list) or not operations:
        raise StateError(INVALID_CONTRACT, "operations must be a non-empty list")
    for ordinal, operation in enumerate(operations):
        if (not isinstance(operation, dict) or not isinstance(operation.get("op"), str)
                or not operation["op"] or not _integer(operation.get("op_version"))):
            raise StateError(INVALID_CONTRACT,
                             f"operations[{ordinal}] must be {{\"op\", \"op_version\", ...}}"
                             " with a non-empty op and an integer op_version")
    return Envelope(project, actor["key"], actor["kind"], timeline, scope,
                    idempotency_key, expected_version, operations)


def open_store(db_path):
    """Open an existing store. The state service never creates one."""
    if not db_path:
        raise StateError(INVALID_CONTRACT, "--db is required")
    if not Path(db_path).is_file():
        raise StateError(INVALID_REFERENCE, f"no store at {db_path}")
    return store.connect(db_path)


def resolve_timeline(connection, project_key: str, timeline_key: str):
    project = _project(connection, project_key)
    timeline = _timeline(connection, project["id"], timeline_key)
    if timeline is None:
        raise StateError(INVALID_REFERENCE, f"project {project_key} has no timeline {timeline_key}")
    return timeline


def apply(db_path, request) -> dict:
    envelope = validate(request)
    connection = open_store(db_path)
    try:
        connection.execute("BEGIN IMMEDIATE")
        try:
            result = _apply(connection, request, envelope)
        except BaseException:
            connection.rollback()
            raise
        connection.commit()
        return result
    finally:
        connection.close()


def _apply(connection, request: dict, envelope: Envelope) -> dict:
    at = store.now()
    project = _project(connection, envelope.project)
    timeline = _timeline(connection, project["id"], envelope.timeline)
    request_hash = store.content_hash(request)

    if timeline is not None:
        prior = connection.execute(
            "SELECT id, seq, request_hash, projection_hash FROM state_transactions"
            " WHERE timeline_id = ? AND idempotency_key = ?",
            (timeline["id"], envelope.idempotency_key)).fetchone()
        if prior is not None:
            if prior["request_hash"] != request_hash:
                raise StateError(CONFLICT, f"idempotency key {envelope.idempotency_key}"
                                           f" committed a different request at seq {prior['seq']}")
            return {**_result(connection, prior), "idempotent_replay": True}

    version = timeline["version"] if timeline is not None else 0
    if envelope.expected_version is not None and envelope.expected_version != version:
        raise StateError(CONFLICT, f"expected timeline version {envelope.expected_version},"
                                   f" found {version}")
    if timeline is None and envelope.operations[0]["op"] != "timeline.create":
        raise StateError(INVALID_REFERENCE,
                         f"project {envelope.project} has no timeline {envelope.timeline}")

    actor_id = _principal(connection, envelope.actor_key, envelope.actor_kind, at)
    context = reducer.Context(
        project_id=project["id"], timeline_key=envelope.timeline,
        timeline_id=timeline["id"] if timeline is not None else None,
        transaction_id=None, at=at, scope=envelope.scope)

    changes = []
    seq = None
    for operation in envelope.operations:
        # The log row names its timeline, so a request that creates its
        # timeline opens the row after the creating operation, not before.
        if context.transaction_id is None and context.timeline_id is not None:
            seq, context.transaction_id = _open_transaction(
                connection, context, actor_id, envelope.idempotency_key, request_hash)
        changes.append(reducer.apply_operation(connection, context, operation))
        if context.timeline_id is None:
            context.timeline_id = _timeline(connection, project["id"], envelope.timeline)["id"]
    if context.transaction_id is None:
        seq, context.transaction_id = _open_transaction(
            connection, context, actor_id, envelope.idempotency_key, request_hash)

    for ordinal, change in enumerate(changes):
        connection.execute(
            "INSERT INTO state_changes (transaction_id, ordinal, operation,"
            " operation_version, entity_kind, entity_id, payload_json)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (context.transaction_id, ordinal, change.operation, change.operation_version,
             change.entity_kind, change.entity_id, store.dumps(change.payload)))
    reducer.advance_timeline(connection, context.timeline_id, seq, at)
    connection.execute(
        "UPDATE state_transactions SET projection_hash = ? WHERE id = ?",
        (projection.hash_projection(connection, context.timeline_id), context.transaction_id))
    return _result(connection, connection.execute(
        "SELECT id, seq, projection_hash FROM state_transactions WHERE id = ?",
        (context.transaction_id,)).fetchone())


def _project(connection, key: str):
    row = connection.execute("SELECT id FROM projects WHERE key = ?", (key,)).fetchone()
    if row is None:
        raise StateError(INVALID_REFERENCE, f"no project {key}")
    return row


def _timeline(connection, project_id: int, key: str):
    return connection.execute(
        "SELECT id, head_seq, version FROM timelines WHERE project_id = ? AND key = ?",
        (project_id, key)).fetchone()


def _principal(connection, key: str, kind: str, at: float) -> int:
    """The actor's id, recording a principal the store has not seen.

    A key names one identity; the same key arriving with another kind is a
    conflict rather than a silent re-attribution of its history.
    """
    row = connection.execute("SELECT id, kind FROM principals WHERE key = ?", (key,)).fetchone()
    if row is not None:
        if row["kind"] != kind:
            raise StateError(CONFLICT, f"principal {key} is a {row['kind']}, not a {kind}")
        return row["id"]
    return connection.execute(
        "INSERT INTO principals (key, kind, created_at) VALUES (?, ?, ?)",
        (key, kind, at)).lastrowid


def _open_transaction(connection, context, actor_id: int, idempotency_key: str,
                      request_hash: str) -> tuple[int, int]:
    """The log row at `head_seq + 1`, read under this request's write lock.
    Its projection hash is filled in once every change has been applied."""
    head_seq = connection.execute(
        "SELECT head_seq FROM timelines WHERE id = ?", (context.timeline_id,)).fetchone()[0]
    seq = head_seq + 1
    transaction_id = connection.execute(
        "INSERT INTO state_transactions (timeline_id, seq, actor_id, idempotency_key,"
        " request_hash, projection_hash, committed_at) VALUES (?, ?, ?, ?, ?, '', ?)",
        (context.timeline_id, seq, actor_id, idempotency_key, request_hash, context.at)).lastrowid
    return seq, transaction_id


def _result(connection, transaction) -> dict:
    timeline = connection.execute(
        "SELECT t.head_seq, t.version FROM timelines t"
        " JOIN state_transactions s ON s.timeline_id = t.id WHERE s.id = ?",
        (transaction["id"],)).fetchone()
    changes = connection.execute(
        "SELECT COUNT(*) FROM state_changes WHERE transaction_id = ?",
        (transaction["id"],)).fetchone()[0]
    return {
        "transaction_id": transaction["id"],
        "seq": transaction["seq"],
        "timeline_version": timeline["version"] - (timeline["head_seq"] - transaction["seq"]),
        "projection_hash": transaction["projection_hash"],
        "changes": changes,
    }


def log(connection, timeline) -> dict:
    """The timeline's committed transactions in sequence order."""
    rows = connection.execute(
        "SELECT s.seq, s.id, s.idempotency_key, s.projection_hash, s.committed_at,"
        " p.key AS actor,"
        " (SELECT COUNT(*) FROM state_changes c WHERE c.transaction_id = s.id) AS changes"
        " FROM state_transactions s JOIN principals p ON p.id = s.actor_id"
        " WHERE s.timeline_id = ? ORDER BY s.seq", (timeline["id"],)).fetchall()
    return {
        "head_seq": timeline["head_seq"],
        "version": timeline["version"],
        "transactions": [
            {"seq": row["seq"], "transaction_id": row["id"],
             "idempotency_key": row["idempotency_key"],
             "projection_hash": row["projection_hash"], "actor": row["actor"],
             "committed_at": row["committed_at"], "changes": row["changes"]}
            for row in rows
        ],
    }
