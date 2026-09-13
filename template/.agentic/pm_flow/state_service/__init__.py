"""The state service: the only writer of authoritative project state.

Every authoritative mutation is a versioned request that commits one
transaction on one timeline. Nothing else in the engine writes the projection
tables this package owns; everything else reads them.

`schema.py` holds the numbered schema steps `store.py` applies when it opens a
store, `migrate.py` plans and applies them on request, and `cli.py` is the
command line over both. The published contract is `docs/database-state-api.md`.
"""
