# StrategyTune position-ledger repair — 2026-11-09

## Root cause

The in-run StrategyTune shadow tracker consumed only \`ctx.account.lastClosedTrade\`. That field exposes the latest close, not every close generated during an update. When multiple lots closed on one update, the shadow tracker missed earlier close events and invalidated its own reconstructed position P&L.

The saved StrategyTune session trade table remained complete. Its rows represent partial-close executions (or an open remainder), not whole positions. Grouping by \`openingFillId\` collapses the rows into one position and restores the authoritative P&L.

## Tooling

Added \`backend/source/tools/strategytune_position_ledger.py\`, a fail-closed post-run reconciler. It validates session pagination and v2.3 entry-map completeness, joins by entry timestamp/side/fill price, groups partial exits by openingFillId, separates open remainders, checks closed-row P&L and row count against engine totals, and reports family/regime metrics. It does not replace the MT5 DEAL_POSITION_ID ledger.

Usage from \`backend/source\` with a JSON payload containing both saved API results:

\`\`\`bash
PYTHONPATH=. python -m tools.strategytune_position_ledger session-run-bundle.json
\`\`\`

Exit code zero means full row, P&L and attribution reconciliation. Non-zero means the bundle must not be used for performance approval.

## Reconciliation results

Gold / IC Markets / M15, independent USD 10,000 StrategyTune runs:

| Period / variant | Closed rows | Entries | Completed positions | Closed P&L | Reconciled |
|---|---:|---:|---:|---:|---|
| September v2.3 baseline | 216 | 112 | 112 | -249.40 | Yes |
| September strict-off diagnostic | 223 | 110 | 110 | +132.36 | Yes |
| October v2.3 baseline | 213 | 117 | 116 | -138.12 | Yes |
| October strict-off diagnostic | 212 | 115 | 114 | -71.11 | Yes |

October variants each retained one open position with approximately -1.73 unrealized P&L. That unrealized value is not included in closed P&L.

The September and October strict-off runs are diagnostics on periods already examined. They are not untouched OOS evidence.

## Risk and family ablations

A short, fresh data window was run over **2026-11-01 to 2026-11-06**. The request to end November 7 was clamped because Gold data ended November 6.

| Variant | Entries | Completed positions | Closed P&L | Position win rate | Profit factor |
|---|---:|---:|---:|---:|---:|
| Strict on, 0.25% risk | 20 | 20 | -15.95 | 65.0% | 0.761 |
| Strict off | 17 | 17 | -37.04 | 58.8% | 0.432 |
| Strict on, strict risk 0.10% | 20 | 20 | -28.64 | 65.0% | 0.561 |

All three session exports matched every entry-map record and reconciled to StrategyTune engine P&L. The six-day sample is too small for promotion. It does not support disabling strict entries or changing risk defaults.

In the 0.10% strict-risk variant, the four strict-family positions netted +9.40, while 16 single-swing positions netted -38.04. Single-swing selection/exit expectancy is therefore the next research target. Continuation results have too few observations to promote.

## Decision and safety boundary

- The post-run whole-position accounting path is corrected; the legacy in-run shadow tracker remains diagnostic only.
- The strategy is not approved. High record win rates do not establish positive whole-position expectancy or profit factor.
- No live EA entry, exit, order admission, stop or risk setting was changed by this work.
- StrategyTune does not model commission or slippage and runs one instrument per backtest. Native MT5 Strategy Tester exports and broker-demo comparison remain separate release gates.
