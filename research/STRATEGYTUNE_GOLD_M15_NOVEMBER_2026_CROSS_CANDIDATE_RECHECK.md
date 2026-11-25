# Gold M15 cross-candidate recheck — 2026-11-25

Status: **research-only; no strategy defaults changed**. This is an addendum to `STRATEGYTUNE_GOLD_TREND_ONLY_V6_2026-11-24.md`. It records a short follow-up comparison, not a new independent out-of-sample certification.

## Test design

- Instrument/provider: IC Markets `Gold` (Gold / US Dollar).
- Timeframe: M15.
- Requested period: 2026-11-01 through 2026-11-25; the provider had data only through **2026-11-24**, and every run was clamped to that date.
- Starting balance: USD 1,500, independently reset for each candidate.
- Candidate versions: Trend-Only Research Candidate v1 v6; Fresh-Sweep Additive Router v3; Direction-Aware Dual-Lane Rank B v2.
- Shared risk inputs were the strategy defaults: `riskFraction=0.25` (0.25%), `opportunityRiskFraction=0.10` (0.10%), and `maxPortfolioRiskPercent=2.25`. This differs from the earlier matched-fold report's explicit 2.0% portfolio-risk cap; do not merge these results into that earlier aggregate.
- Each run saved a session. Partial-close rows were grouped by `openingFillId`; each opening position is counted once and its partial-close P&L is summed. All groups in these three sessions were closed by the end of the tested period.
- StrategyTune models recorded bid/ask but has no commission, slippage, or swap model. These figures are pre-cost proxies, not native MT5 EA results.

## Position-level results

| Candidate | Closed positions | Wins / losses | Position win rate | Net P&L | Profit factor |
|---|---:|---:|---:|---:|---:|
| Trend-Only v6 | 7 | 7 / 0 | 100.00% | +$4.39 | Undefined (no losses) |
| Fresh-Sweep Router v3 | 15 | 15 / 0 | 100.00% | **+$6.30** | Undefined (no losses) |
| Direction-Aware Rank B v2 | 26 | 20 / 6 | 76.92% | -$0.16 | 0.977 |

These are position-group counts, not engine close-row counts. The raw engine reports had 16, 33, and 50 closed rows respectively; counting those rows as independent entries would overstate trade frequency and distort the win rate.

## Interpretation

1. Fresh-Sweep Router v3 led this short comparison on number of closed positions and net P&L. Trend-Only v6 had fewer entries and a smaller total gain. Rank B was approximately flat but negative.
2. The apparent 100% win rates for Trend-Only and Fresh-Sweep are based on only 7 and 15 completed positions. A zero-loss sample makes profit factor undefined; it does not establish a reliable high win rate.
3. This November window overlaps the earlier October–November 21 research window. It is a recheck on overlapping market history, **not an untouched future holdout**.
4. The separate six-month Fresh-Sweep Router v3 run for 2025-07-01 through 2026-01-01 exceeded the StrategyTune 120-second job deadline and ended in error. It contributes no valid result. Use the previously documented completed monthly folds for that broader comparison.
5. The Trend-Only v6 candidate's already-grouped 2025 H2 result remains adverse: 199 completed positions, 152 wins / 47 losses, 76.38% position win rate, -$9.57 net P&L, and 0.828 profit factor. The recent November sample does not erase that regime-sensitivity warning.

## Integration decision

**No new strategy code or default changes are justified by this recheck.** The existing MQL5 `InpFreshSweepTrendOnlyContinuation` gate remains false by default, and the parent Fresh-Sweep additive router remains disabled by default. Keep the candidate research-only.

The evidence supports retaining Fresh-Sweep and Trend-Only as controlled, opt-in research candidates, not enabling either in live defaults. Before promotion, require a locked, non-overlapping OOS period; cost-inclusive native MT5 Strategy Tester ablations; position-level accounting; and broker-demo validation of fills, margin admission, protective-stop amendments, ledger persistence, and restart recovery. No live trading is authorized by this report.
