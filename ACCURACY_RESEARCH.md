# Midas Touch 2 — Accuracy Research Note

Date: 2026-11-07  
Branch: `build/single-file-staging`  
EA source baseline: `cirvannaco-png/Midas-touch2-@3622ed5a434c36f0c05ab9c9863d17b6fd743e9a`

## Executive finding

Do not promote a win-rate claim from these runs. Three StrategyTune research runs against the saved **Midas Touch 2 Causal Research v2.1 Stop Guard** script (Gold / IC Markets / M15 / USD 10,000) were cut short by the platform's 1,000 order-operation limit. They cover different partial windows and are not a valid matched full-year comparison.

| Variant | Closed trade records | Record win rate | Net P&L | Max drawdown | Last market timestamp |
|---|---:|---:|---:|---:|---|
| Existing inputs | 500 | 88.0% | -$106.48 | $209.67 | 2026-01-20 13:34 UTC |
| minQuality 68, directionalAdvantage 8, continuation fallback off | 500 | 88.4% | -$55.63 | $180.37 | 2026-01-23 08:29 UTC |
| Same strict filter + RVOL confirmation at 1.2 | 500 | 90.4% | -$6.29 | $98.85 | 2026-04-23 14:00 UTC |

Every run returned the explicit warning that it stopped at 1,000 order operations. The intended window was 2025-11-07 through 2026-11-06; none reached the end. Since the stop dates differ, the rows are exploratory diagnostics, not a clean ranking. The 500 count is the engine's closed-trade-record count; these runs did not return the strategy's completed-position custom counters. Do not call these position-level accuracy rates.

## Important LONA limitation

A LONA grid optimization was attempted on the existing Regime-Gated Dual-Lane Research Validator using the remaining free optimization entitlement, XAUUSD M15, with displacement and body-size thresholds. LONA refused the run: **intraday global data is not available on the Free plan**. The account showed zero spendable LONA credits and two free optimizations remaining. No LONA optimization result exists.

A previous LONA dry-run smoke test is not a performance backtest and does not validate the MT5 EA.

## Source-level findings in the EA

1. `CScoringEngine::CalculateConfidence()` returns a normalized raw score. It is not itself a calibrated probability.
2. The EA calculates an empirical probability using `COutcomeTrackerLive::GetCalibratedProbability()`, but `OnTick()` stores it in `chosen.calibrated_probability` and then calls `g_router.Decide(chosen)`. The decision router thresholds `setup.confidence`, not the calibrated probability. The calibration result is therefore diagnostic, not an execution gate.
3. `PopulateConfidenceDiagnostics()` calculates `env_exec_confidence`, combining environment suitability, entry quality and contradiction penalty. The source explicitly keeps this diagnostic separate from the raw confidence used by the decision router.
4. Strategy-selection diagnostics (SMC, momentum/breakout, mean reversion and key-level reaction) are populated separately and do not currently alter the entry score.
5. The live outcome tracker groups broker deal history under a decision ID and excludes ambiguous/incomplete cashflow outcomes from calibration. This is a better basis for decision-level accuracy than counting partial exit records, but it still needs real MT5 Strategy Tester evidence and sufficient samples.
6. Calibration is stored in fixed five-point buckets, requires 30 samples by default, and is symbol-specific. The source warns that a scoring-formula change invalidates old calibration data. Any future calibration gate must be version-aware, sample-gated and tested out of sample; do not use sparse buckets to block or size live trades.

## Next research steps

- Re-run the StrategyTune variants after the daily compute allowance resets, reducing trade-operation consumption (lower daily entry cap and/or less aggressive multi-tranche exits) so each run reaches the same end date. Keep the same instrument, provider, interval, balance, costs assumptions and dates across variants.
- Capture decision/group-level wins, losses, scratches, ambiguous outcomes, expectancy, profit factor, average win/loss, maximum drawdown and trades per month. Separate signal accuracy from exit-management performance.
- Compare baseline, strict quality gate, RVOL gate and environment/contradiction diagnostics on identical in-sample and untouched out-of-sample windows. Do not optimize directly on the OOS window.
- Investigate whether the high headline win rate is being purchased with small early partial profits and larger stop losses. Optimize expectancy and drawdown, not win rate alone.
- Only consider routing on calibrated probability or enabling additional hard gates after matched MT5 ablations, adequate per-bucket samples, versioned calibration and forward/demo validation.

## Release decision

**No EA source or trading parameters were changed by this accuracy investigation.** The generated single-file EA remains at the previously compiled baseline. These research results are incomplete and do not authorize live trading. Actual MT5 Strategy Tester validation, broker demo execution, and protective-stop modification/reconciliation remain mandatory.
