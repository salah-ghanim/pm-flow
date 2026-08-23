# topology-compare section PM state

## Current task

- None; waiting on `store-ledger`.

## Completed tasks and evidence

- None.

## Active decisions

- One disposable checkout per arm; rows imported back under the arm's key.
- Cost comes from `store-ledger`'s `cost.py`.

## Blockers

- `store-ledger` is not done (T3 reads its totals; T1 and T2 do not).

## Next eligible task

- T1, once `store-ledger` is done.
