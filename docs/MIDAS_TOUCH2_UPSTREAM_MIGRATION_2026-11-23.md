# Midas Touch 2 upstream migration — 2026-11-23

## Canonical repository

The canonical repository is `cirvannaco-png/midas`. The former companion repository
`cirvannaco-png/Midas-touch2-` is retained as historical source provenance only.

## Imported upstream revision

The imported project snapshot under `backend/source/` is refreshed through upstream
commit `6dad8a00a522e3fd507b0f2669de47bcb47e43ee` (23 November 2026). The prior
snapshot was `52d737237c08f36d668853312f643cb74d4548da`.

The complete upstream comparison from the prior snapshot to the latest source revision
contains two commits and three changed paths:

- `EA/MedisTouch_v2.8.mq5`
- `EA/README.md`
- `tools/tests/test_daily_objective_dual_direction_contract.py`

Those three files have been refreshed in `backend/source/`. The imported upstream
revision and root README now point to the latest source commit.

## Direction-policy reconciliation

The upstream change makes `InpGoldLongOnlyMode=false` by default. This restores
automated Gold BUY and SELL setup generation, evaluation, signal publication and
execution through the same existing execution pipeline. Setting the input to true
remains an explicit opt-in to suppress automated Gold SELL setup generation.

The active Midas build under `development/EA/` already generates both BUY and SELL
setups without a Gold-only long-direction gate. The active generated EA is therefore
already bidirectional; copying the upstream EA over it would replace the Midas
canonical build with a different source lineage and is intentionally not done.
A regression test now protects the active source and generated artifact from a
future accidental Gold-only suppression.

## Safety and release boundary

This is a directional-eligibility change, not a profitability claim or live-trading
approval. Existing strategy selection, broker sizing, execution-ledger admission,
portfolio limits, risk guards, stop requirements and emergency controls remain
mandatory. The migration does not force entries or authorize live trading.

The upstream source snapshot is provenance/reference material. The only active MT5
build target remains `development/EA/MedisTouch_v2.8.mq5`, generated from
`development/EA/MedisTouch_v2.8.source.mq5` and `development/EA/includes/`.
