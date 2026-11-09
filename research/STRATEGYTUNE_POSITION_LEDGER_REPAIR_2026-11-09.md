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


## Single-swing regime and exit experiments

The v2.5 regime-gate runs isolated single-swing/continuation behavior by disabling the strict family, keeping the original 0.25R single-swing TP1, enabling adaptive fallback price-delivery filtering, and setting the weak transition-band ceiling to 0.45 ATR slope. The regime gate blocks the transition band, applies the trend impulse-range cap, and retains price-delivery validation in range-like conditions.

| Period | Strict-off baseline P&L / max DD | Regime-gate P&L / max DD | Entries (baseline → gate) |
|---|---:|---:|---:|
| September 2026 | +132.36 / 42.80 | +140.65 / 31.05 | 110 → 110 |
| October 2026 | -71.11 / 119.64 | -47.90 / 78.26 | 115 → 102 |
| Combined closed P&L | +61.25 | +92.75 | 225 → 212 |

The filter routed many otherwise-eligible single-swing signals into the independent continuation family. That routing is included in the results; these are not pure single-swing-only comparisons. All entry-map records matched the saved-session rows, with no overflow, unmatched or ambiguous mappings. Session closed-row P&L reconciled to StrategyTune engine P&L in both periods.

### Single-swing TP1 threshold ablation

With the regime gate and strict-off research conditions held constant, only the single-swing first scale-out threshold was changed from 0.25R to 0.50R.

| Period / exit | Completed positions | Position win rate | Position PF | Closed P&L | Engine max DD |
|---|---:|---:|---:|---:|---:|
| September, TP1 0.25R | 109 | 89.91% | 2.369 | +140.65 | 31.05 |
| September, TP1 0.50R | 106 | 80.19% | 1.660 | +124.68 | 53.93 |
| October, TP1 0.25R | 101 | 73.27% | 0.794 | -47.90 | 78.26 |
| October, TP1 0.50R | 98 | 69.39% | 0.980 | -5.04 | 101.10 |
| Combined, TP1 0.25R | 210 | 81.90% | 1.277 | +92.75 | — |
| Combined, TP1 0.50R | 204 | 75.00% | 1.269 | +119.64 | — |

The 0.50R threshold increased average winning-position P&L from $2.49 to $3.69 and left average losing-position P&L broadly similar ($-8.82 versus $-8.72). However, position win rate fell by 6.9 percentage points, combined profit factor was slightly lower, and engine max drawdown worsened in both months. This is a trade-off, not a clean improvement. Keep 0.25R as the current research control; retain 0.50R as a separate exit experiment.

### Research decision

- The adaptive regime gate is the strongest candidate from these examined windows because it improved both monthly net P&L and monthly engine maximum drawdown relative to strict-off baseline.
- It remains **development-window evidence**, not untouched out-of-sample proof. The months were already used to diagnose and choose the filter. Do not enable it in the live EA or describe it as validated profitability.
- The 0.50R TP1 experiment is not selected because its drawdown and combined profit-factor trade-offs are unfavorable despite higher combined net P&L.
- StrategyTune data currently ends on **2026-11-06**. A future unseen data window and multiple instruments are required before any promotion decision.
- The standalone scripts `MT2 v2.6 Regime Gate Strict-Off` and `MT2 v2.7 TP1 0.50R Exit Test` preserve the two tested parameter sets. They do not alter the MT5 EA or the v2.2/v2.3 baseline scripts.
