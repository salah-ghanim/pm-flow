"""The state service's error vocabulary.

A rejected request raises `StateError(code, detail)`. The code is one of the
constants below and is the contract; the detail is for a human and may change.
The command line prints `{"error": code, "detail": detail}` and exits 1.

`IDEMPOTENT_REPLAY` is in the vocabulary but is never raised: a request whose
idempotency key already committed returns that commit's result, marked
`"idempotent_replay": true`, and succeeds.
"""

from __future__ import annotations

CONFLICT = "conflict"
INVALID_REFERENCE = "invalid_reference"
INVALID_CONTRACT = "invalid_contract"
UNMET_DEPENDENCY = "unmet_dependency"
LOST_LEASE = "lost_lease"
DENIED_SCOPE = "denied_scope"
DENIED_SIDE_EFFECT = "denied_side_effect"
NON_REPLAYABLE_CHECKPOINT = "non_replayable_checkpoint"
CONFOUNDED_COMPARISON = "confounded_comparison"
UNKNOWN_OPERATION_VERSION = "unknown_operation_version"
CYCLIC_DEPENDENCY = "cyclic_dependency"
IDEMPOTENT_REPLAY = "idempotent_replay"

CODES = frozenset({
    CONFLICT, INVALID_REFERENCE, INVALID_CONTRACT, UNMET_DEPENDENCY, LOST_LEASE,
    DENIED_SCOPE, DENIED_SIDE_EFFECT, NON_REPLAYABLE_CHECKPOINT,
    CONFOUNDED_COMPARISON, UNKNOWN_OPERATION_VERSION, CYCLIC_DEPENDENCY,
    IDEMPOTENT_REPLAY,
})


class StateError(Exception):
    """A request the state service refused. Nothing it did was committed."""

    def __init__(self, code: str, detail: str):
        if code not in CODES:
            raise ValueError(f"{code!r} is not a state-service error code")
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail

    def document(self) -> dict:
        return {"error": self.code, "detail": self.detail}
