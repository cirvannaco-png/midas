# Midas monorepo consolidation

## Canonical repository

This repository is the canonical distributable MT5 EA repository. The backend
source is retained as a complete, pinned snapshot under `backend/source/`.

Upstream backend repository: https://github.com/cirvannaco-png/Midas-touch2-

## Synchronization

Run the **Sync Midas-touch2 source snapshot** GitHub Actions workflow on the
integration branch or a future maintenance branch. It clones upstream
`main`, copies every tracked and untracked working-tree file except the Git
object database into `backend/source/`, and records the exact upstream commit
in `backend/SOURCE_REVISION.md`.

The sync is intentionally non-destructive to the root EA and its
`development/EA/` source tree. The backend's nested workflows are preserved
for provenance but are not active root workflows.

## Integration boundary

A source snapshot is not an integration claim. Before backend capabilities
are promoted into EA runtime behavior, verify:
- a single portfolio-wide risk budget includes open positions, pending orders,
  correlated exposures, and available margin;
- regime eligibility is separately validated for trend continuation, mean
  reversion, and breakout families;
- every position carries immutable strategy, setup, and entry-regime lineage;
- partial fills and partial closes aggregate to one position-level outcome;
- chronological walk-forward folds and locked OOS data remain isolated;
- the EA remains the only broker-order authority and the backend ledger remains
  the single authoritative execution ledger.

No new regime hard gate or risk-profile change is authorized by the snapshot.
