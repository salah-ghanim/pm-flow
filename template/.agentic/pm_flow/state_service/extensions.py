"""Process-local extension points of the state service.

A later section adds an operation, a job handler or a workflow decision by
registering it in the process that serves requests. Registrations are not
persisted: every process that applies or replays a timeline using an extension
operation must register it first, or the reducer lookup raises
`unknown_operation_version`.

The built-in operation vocabulary cannot be overridden. An extension that
could replace `task.create` would change what every recorded `task.create`
change means on replay.
"""

from __future__ import annotations

from state_service.errors import INVALID_CONTRACT, StateError

# (operation, operation version) -> reducer function, merged into the lookup
# in `reducer.reducer_for`.
OPERATIONS: dict[tuple[str, int], object] = {}
# Consumed by the job worker (workplan T3).
JOB_HANDLERS: dict[str, object] = {}
DECISIONS: dict[str, object] = {}


def register_operation(name: str, version: int, fn) -> None:
    """Add reducer `fn` for `(name, version)`.

    `fn(connection, context, args) -> (entity_kind, entity_id, payload)` has
    the contract of the built-in reducers in `reducer.py`.
    """
    # Imported here: the reducer imports this module for its lookup.
    from state_service.reducer import REDUCERS

    if not isinstance(name, str) or not name:
        raise StateError(INVALID_CONTRACT, "operation name must be a non-empty string")
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        raise StateError(INVALID_CONTRACT, "operation version must be a positive integer")
    if not callable(fn):
        raise StateError(INVALID_CONTRACT, f"reducer for {name} v{version} is not callable")
    if any(builtin == name for builtin, _ in REDUCERS):
        raise StateError(INVALID_CONTRACT, f"{name} is a built-in operation")
    if (name, version) in OPERATIONS:
        raise StateError(INVALID_CONTRACT, f"{name} v{version} is already registered")
    OPERATIONS[(name, version)] = fn


def register_job_handler(kind: str, fn) -> None:
    JOB_HANDLERS[kind] = fn


def register_decision(kind: str, fn) -> None:
    DECISIONS[kind] = fn
