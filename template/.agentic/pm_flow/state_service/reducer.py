"""The versioned reducer: how each operation changes a timeline's projection.

`REDUCERS` maps `(operation, operation_version)` to a function

    fn(connection, context, args) -> (entity_kind, entity_id, payload)

that validates `args`, writes the projection rows and returns what the change
row records. `service.apply` calls it for a new request and `projection.replay`
calls the same function for a recorded change, so a reducer may depend only on
its arguments, `context` and the projection it is given. Anything else a change
needs to be reproduced - the row ids it allocated, the envelope values it used -
goes into `payload["bound"]`, and on replay comes back as `context.bound`.

An unknown pair raises `unknown_operation_version`. Nothing is skipped and no
version is assumed.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field
from typing import NamedTuple

import store
from state_service import extensions
from state_service.errors import (
    CONFLICT, CYCLIC_DEPENDENCY, DENIED_SCOPE, INVALID_CONTRACT,
    INVALID_REFERENCE, UNKNOWN_OPERATION_VERSION, StateError,
)


@dataclass
class Context:
    """What a reducer knows besides its arguments.

    `project_id` and `timeline_key` are the request envelope's and are read
    only by `timeline.create`; on replay they are None and the recorded bound
    values stand in. `scope` is None for every task, otherwise the task keys a
    request may touch; replay does not re-authorise, so it passes None. `at` is
    the transaction's `committed_at`, the only clock a reducer reads.
    """

    project_id: int | None
    timeline_key: str | None
    timeline_id: int | None
    transaction_id: int | None
    at: float
    scope: frozenset | None
    bound: dict = field(default_factory=dict)


class Change(NamedTuple):
    operation: str
    operation_version: int
    entity_kind: str
    entity_id: str
    payload: dict


# ------------------------------------------------------------------ helpers

def _arguments(args: dict, operation: str, required=(), optional=()) -> None:
    missing = [name for name in required if name not in args]
    unknown = sorted(set(args) - set(required) - set(optional))
    if missing or unknown:
        raise StateError(INVALID_CONTRACT, f"{operation}: "
                         + "; ".join(filter(None, [
                             missing and "missing " + ", ".join(missing),
                             unknown and "unknown " + ", ".join(unknown)])))


def _text(args: dict, name: str, operation: str) -> str | None:
    """A present argument is a non-empty string; an absent one is None."""
    if name not in args:
        return None
    value = args[name]
    if not isinstance(value, str) or not value:
        raise StateError(INVALID_CONTRACT, f"{operation}: {name} must be a non-empty string")
    return value


def _payload(args: dict, **bound) -> dict:
    return {"args": args, "bound": bound}


def _insert(connection, table: str, values: dict, conflict: str) -> int:
    columns = ", ".join(values)
    marks = ", ".join("?" for _ in values)
    try:
        cursor = connection.execute(
            f"INSERT INTO {table} ({columns}) VALUES ({marks})", tuple(values.values()))
    except sqlite3.IntegrityError as error:
        if "UNIQUE" not in str(error):
            raise
        raise StateError(CONFLICT, f"{conflict} ({error})") from error
    return cursor.lastrowid


def _in_scope(context: Context, key: str, operation: str) -> None:
    if context.scope is not None and key not in context.scope:
        raise StateError(DENIED_SCOPE, f"{operation}: task {key} is outside the request scope")


def _task(connection, context: Context, key, operation: str, name: str):
    """Resolve a task key inside the request's scope and timeline.

    Scope is checked first, so a key outside it is refused the same way
    whether or not the task exists.
    """
    if not isinstance(key, str) or not key:
        raise StateError(INVALID_CONTRACT, f"{operation}: {name} must be a task key")
    _in_scope(context, key, operation)
    row = connection.execute(
        "SELECT id, project_id, version FROM tasks WHERE timeline_id = ? AND key = ?",
        (context.timeline_id, key)).fetchone()
    if row is None:
        raise StateError(INVALID_REFERENCE,
                         f"{operation}: no task {key} on this project's timeline")
    return row


def _latest_revision(connection, context: Context, task_id: int):
    return connection.execute(
        "SELECT id, revision, title, objective, contract_json FROM task_revisions"
        " WHERE task_id = ? AND timeline_id = ? ORDER BY revision DESC LIMIT 1",
        (task_id, context.timeline_id)).fetchone()


def _contract(args: dict, operation: str) -> dict | None:
    if "contract" not in args:
        return None
    if not isinstance(args["contract"], dict):
        raise StateError(INVALID_CONTRACT, f"{operation}: contract must be an object")
    return args["contract"]


def _insert_revision(connection, context: Context, task_id: int, revision: int,
                     parent_id, title, objective, contract: dict) -> int:
    return _insert(connection, "task_revisions", {
        "id": context.bound.get("revision_id"),
        "task_id": task_id,
        "timeline_id": context.timeline_id,
        "revision": revision,
        "parent_revision_id": parent_id,
        "title": title,
        "objective": objective,
        "contract_json": store.dumps(contract),
        "content_hash": store.content_hash(title, objective, contract),
        "created_txn_id": context.transaction_id,
    }, f"task revision {revision} already exists")


# --------------------------------------------------------------- operations

def timeline_create(connection, context: Context, args: dict):
    """Create the request's timeline. Version 1 creates production timelines
    only; a second one for the project violates the partial unique index and
    is a conflict."""
    op = "timeline.create"
    _arguments(args, op, required=("purpose",), optional=("status",))
    purpose = _text(args, "purpose", op)
    if purpose != "production":
        raise StateError(INVALID_CONTRACT, f"{op} v1 creates production timelines only")
    status = _text(args, "status", op) or "active"
    project_id = context.bound.get("project_id", context.project_id)
    key = context.bound.get("key", context.timeline_key)
    timeline_id = _insert(connection, "timelines", {
        "id": context.bound.get("timeline_id"),
        "project_id": project_id,
        "key": key,
        "purpose": purpose,
        "status": status,
        "head_seq": 0,
        "version": 0,
        "created_at": context.at,
        "updated_at": context.at,
    }, f"project already has a production timeline or a timeline {key}")
    return "timeline", timeline_id, _payload(
        args, timeline_id=timeline_id, project_id=project_id, key=key)


def task_create(connection, context: Context, args: dict):
    op = "task.create"
    _arguments(args, op, required=("key",),
               optional=("title", "objective", "contract", "status"))
    key = _text(args, "key", op)
    _in_scope(context, key, op)
    title, objective = _text(args, "title", op), _text(args, "objective", op)
    status = _text(args, "status", op)
    contract = _contract(args, op) or {}
    project_id = connection.execute(
        "SELECT project_id FROM timelines WHERE id = ?", (context.timeline_id,)).fetchone()[0]
    task_id = _insert(connection, "tasks", {
        "id": context.bound.get("task_id"),
        "project_id": project_id,
        "key": key,
        "title": title,
        "status": status,
        "timeline_id": context.timeline_id,
        "version": 1,
        "created_at": context.at,
        "updated_at": context.at,
        "updated_txn_id": context.transaction_id,
    }, f"{op}: task key {key} is already used in this project")
    revision_id = _insert_revision(connection, context, task_id, 1, None,
                                   title, objective, contract)
    return "task", task_id, _payload(args, task_id=task_id, revision_id=revision_id)


def task_revise(connection, context: Context, args: dict):
    """A new immutable revision. Fields not given carry over from the latest."""
    op = "task.revise"
    _arguments(args, op, required=("task",), optional=("title", "objective", "contract"))
    if len(args) == 1:
        raise StateError(INVALID_CONTRACT, f"{op}: give at least one of title, objective, contract")
    task = _task(connection, context, args["task"], op, "task")
    latest = _latest_revision(connection, context, task["id"])
    title = _text(args, "title", op) if "title" in args else latest["title"]
    objective = _text(args, "objective", op) if "objective" in args else latest["objective"]
    contract = _contract(args, op)
    if contract is None:
        contract = store.loads(latest["contract_json"])
    revision_id = _insert_revision(connection, context, task["id"], latest["revision"] + 1,
                                   latest["id"], title, objective, contract)
    connection.execute(
        "UPDATE tasks SET title = ?, version = version + 1, updated_at = ?,"
        " updated_txn_id = ? WHERE id = ?",
        (title, context.at, context.transaction_id, task["id"]))
    return "task", task["id"], _payload(args, revision_id=revision_id)


def task_set_status(connection, context: Context, args: dict):
    """`status` is free text; the vocabulary belongs to whatever runs the task."""
    op = "task.set_status"
    _arguments(args, op, required=("task", "status"))
    task = _task(connection, context, args["task"], op, "task")
    status = _text(args, "status", op)
    connection.execute(
        "UPDATE tasks SET status = ?, version = version + 1, updated_at = ?,"
        " updated_txn_id = ? WHERE id = ?",
        (status, context.at, context.transaction_id, task["id"]))
    return "task", task["id"], _payload(args)


def task_assign(connection, context: Context, args: dict):
    """A seat on the task's current revision. Seat and relationship are free text."""
    op = "task.assign"
    _arguments(args, op, required=("task", "seat_key", "relationship"))
    task = _task(connection, context, args["task"], op, "task")
    seat_key = _text(args, "seat_key", op)
    relationship = _text(args, "relationship", op)
    assignment_id = _insert(connection, "task_assignments", {
        "id": context.bound.get("assignment_id"),
        "timeline_id": context.timeline_id,
        "task_id": task["id"],
        "task_revision_id": _latest_revision(connection, context, task["id"])["id"],
        "seat_key": seat_key,
        "relationship": relationship,
        "created_txn_id": context.transaction_id,
    }, f"{op}: assignment already exists")
    return "task_assignment", assignment_id, _payload(args, assignment_id=assignment_id)


def dependency_add(connection, context: Context, args: dict):
    """`task` depends on `depends_on`. Refused if `depends_on` already reaches
    `task` through the timeline's dependencies, which includes itself."""
    op = "dependency.add"
    _arguments(args, op, required=("task", "depends_on"))
    task = _task(connection, context, args["task"], op, "task")
    depends_on = _task(connection, context, args["depends_on"], op, "depends_on")
    reaches = connection.execute(
        "WITH RECURSIVE reachable(id) AS ("
        "  SELECT ? UNION"
        "  SELECT d.depends_on_id FROM task_dependencies d"
        "  JOIN reachable r ON d.task_id = r.id WHERE d.timeline_id = ?)"
        " SELECT 1 FROM reachable WHERE id = ?",
        (depends_on["id"], context.timeline_id, task["id"])).fetchone()
    if reaches:
        raise StateError(CYCLIC_DEPENDENCY,
                         f"{op}: {args['depends_on']} already depends on {args['task']}"
                         if task["id"] != depends_on["id"]
                         else f"{op}: {args['task']} cannot depend on itself")
    _insert(connection, "task_dependencies", {
        "task_id": task["id"],
        "depends_on_id": depends_on["id"],
        "timeline_id": context.timeline_id,
        "created_txn_id": context.transaction_id,
    }, f"{op}: {args['task']} already depends on {args['depends_on']}")
    return "task_dependency", f"{task['id']}:{depends_on['id']}", _payload(args)


def dependency_remove(connection, context: Context, args: dict):
    op = "dependency.remove"
    _arguments(args, op, required=("task", "depends_on"))
    task = _task(connection, context, args["task"], op, "task")
    depends_on = _task(connection, context, args["depends_on"], op, "depends_on")
    removed = connection.execute(
        "DELETE FROM task_dependencies"
        " WHERE task_id = ? AND depends_on_id = ? AND timeline_id = ?",
        (task["id"], depends_on["id"], context.timeline_id)).rowcount
    if not removed:
        raise StateError(INVALID_REFERENCE,
                         f"{op}: {args['task']} does not depend on {args['depends_on']}")
    return "task_dependency", f"{task['id']}:{depends_on['id']}", _payload(args)


REDUCERS = {
    ("timeline.create", 1): timeline_create,
    ("task.create", 1): task_create,
    ("task.revise", 1): task_revise,
    ("task.set_status", 1): task_set_status,
    ("task.assign", 1): task_assign,
    ("dependency.add", 1): dependency_add,
    ("dependency.remove", 1): dependency_remove,
}


# ------------------------------------------------------------------- lookup

def reducer_for(operation: str, version: int):
    fn = REDUCERS.get((operation, version)) or extensions.OPERATIONS.get((operation, version))
    if fn is None:
        raise StateError(UNKNOWN_OPERATION_VERSION, f"no reducer for {operation} v{version}")
    return fn


def apply_operation(connection, context: Context, operation: dict) -> Change:
    """Apply one request operation, `{"op", "op_version", ...args}`."""
    args = {key: value for key, value in operation.items() if key not in ("op", "op_version")}
    context.bound = {}
    return _run(connection, context, operation["op"], operation["op_version"], args)


def replay_change(connection, context: Context, operation: str, version: int,
                  payload) -> Change:
    """Apply one recorded change, with the values it bound when first applied."""
    if (not isinstance(payload, dict) or set(payload) != {"args", "bound"}
            or not isinstance(payload["args"], dict)
            or not isinstance(payload["bound"], dict)):
        raise StateError(INVALID_CONTRACT,
                         f"recorded {operation} v{version} payload is not {{args, bound}}")
    context.bound = payload["bound"]
    return _run(connection, context, operation, version, payload["args"])


def _run(connection, context: Context, operation: str, version: int, args: dict) -> Change:
    entity_kind, entity_id, payload = reducer_for(operation, version)(connection, context, args)
    if (not isinstance(payload, dict) or set(payload) != {"args", "bound"}
            or store.dumps(payload) == "{}"):
        # store.dumps answers "{}" only when it could not serialise the payload,
        # and a change that cannot be recorded cannot be replayed.
        raise StateError(INVALID_CONTRACT,
                         f"reducer for {operation} v{version} returned an unrecordable payload")
    return Change(operation, version, entity_kind, str(entity_id), payload)


def advance_timeline(connection, timeline_id: int, seq: int, at: float) -> None:
    """Every committed transaction moves its timeline's head and version by one."""
    connection.execute(
        "UPDATE timelines SET head_seq = ?, version = version + 1, updated_at = ?"
        " WHERE id = ?", (seq, at, timeline_id))
