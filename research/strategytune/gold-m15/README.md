# Gold M15 StrategyTune archive

This directory stores the exact StrategyTune research proxy code and metadata for selected Gold M15 candidates. These are research artifacts, **not the production MQL5 Expert Advisor**.

- \`v2.6/\`: control.
- \`v2.7/\`: TP1 0.50R exit experiment; rejected.
- \`v2.12/\`: regime-specialist hybrid.
- \`v2.13/\`: trend-only single-swing candidate; historical research candidate.
- \`v2.14/\`: Midas Gold v2.14 Exit Guard; session-row attribution revision 3.

## Position attribution rule

StrategyTune's in-run \`Context\` exposes only \`account.lastClosedTrade\`, the latest close. It does **not** expose the complete close-event stream. Multiple partial closes on one update therefore cannot be counted or assigned to opening positions safely from that snapshot.

The v2.14 revision 3 script now:
- exports entry-time feature telemetry only, with the StrategyTune lot ID in \`entryMap\`;
- suppresses in-run realized position P&L, win/loss, and position-attribution claims;
- marks \`sessionRowsRequired=true\` and identifies \`openingFillId\` as the outcome join key;
- reports the close-observer gap only as a diagnostic, never as an authoritative position ledger.

For authoritative post-run outcomes, save the StrategyTune session, retrieve **every page** from \`get_session_trades\`, and run:

\`\`\`bash
python scripts/strategytune_session_reconcile.py \\
  --session-json session-pages.json \\
  --engine-closed-pnl -88.92
\`\`\`

Alternatively, pass \`--summary-json run-result.json\` where the JSON contains the StrategyTune engine's \`stats.stats.totalPnl\` or \`stats.account.closedPnl\`. The tool groups partial close rows by \`openingFillId\`, excludes unrealized P&L from open residual rows, rejects incomplete pagination and duplicate close rows, and compares the sum of all realized close rows with the engine's closed P&L. Exit code 0 means reconciled; 3 means a P&L mismatch; 2 means invalid or incomplete input.

A successful reconciliation validates accounting consistency only. It does not establish strategy profitability, broker execution quality, out-of-sample robustness, or live-trading readiness.

See [the consolidated research report](../../STRATEGYTUNE_GOLD_M15_V2_13_2026-11-10.md) for earlier test windows and research limitations.
