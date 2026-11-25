# Midas entry-family parity audit — 2026-11-25

**Status:** Source audit only. No strategy settings, production MQL5 defaults, risk limits, or live execution behavior changed.

## Executive finding

The current StrategyTune Gold M15 research strategy is **not a faithful proxy for the production EA's default entry routing**. Results from the recent StrategyTune filter/quality ablations are useful for understanding that research script's single-swing fallback, but must not be described as production-EA evidence or as tests of the default native router.

This distinction is material:

- StrategyTune v2.14 defaults to `enableStrictFamily=false`, `enableSingleSwingFallback=true`, `enableContinuationFallback=false`, and `enableMicroMomentumFallback=false`. Its normal default path is therefore single-swing, not the native production continuation router.
- The active MQL5 `CFreshSweepAdditiveRouter` defaults to `m_enabled=false` and `m_enable_single_swing=false`. The integration plan also explicitly keeps `InpEnableFreshSweepAdditiveRouter=false` and `InpFreshSweepEnableSingleSwingFallback=false` in production.
- When enabled with single-swing disabled, the native router evaluates the continuation candidate only. It is called only after both existing native directional setup builders return inactive; the selected setup then passes through the existing validator, risk engine, ledger, sizing, broker order manager and position manager.
- Native router lane selection is continuation-first by default. Its optional dual-lane Rank B mode is a separate configuration and is not enabled by the default constructor/configuration. StrategyTune v2.14, by contrast, evaluates both fallback families and ranks them together when both are enabled.

## Source-level gate map

There is also a direct continuation-formula mismatch. Native MQL5 `BuildContinuation` uses body ratio >= 0.35, signal range/ATR >= 0.45, an EMA pullback touch within eight bars, and quality floor 48. StrategyTune v2.14's `continuationChain` uses body ratio >= 0.40, range/ATR >= 0.60, a pullback touch within bars 1–5, and the configurable `fallbackQualityFloor` (default 55). Thus even an isolated StrategyTune continuation run would not be an exact native continuation replay without first aligning those conditions and proving completed-bar/indexing parity. Do not port its continuation metrics into production claims.

| Entry family | StrategyTune research gate | Native MQL5 boundary |
|---|---|---|
| Strict SMC | `minQuality`, reward/risk floor, shared optional RVOL/Fibonacci checks | Existing native setup builders and shared scoring/decision validation; not the additive router's default route |
| Single-swing | `singleSwingMinQuality`, reward/risk floor, shared optional RVOL/Fibonacci checks, adaptive regime/PD checks | `InpFreshSweepEnableSingleSwingFallback=false` by default; router must be explicitly enabled and single-swing separately enabled |
| Continuation | `fallbackQualityFloor`, reward/risk floor, shared optional RVOL/Fibonacci checks | Native `BuildContinuation` uses its own quality floor (48) and the shared scoring validator applies configured mandatory RVOL/Fibonacci checks downstream |
| Micro-momentum | `microMomentumMinQuality`, reward/risk floor, shared optional RVOL/Fibonacci checks | No evidence in the reviewed additive-router path that this research-only fallback is a production lane |

The StrategyTune helper `optionalFiltersOK` is called by all four research signal generators. The quality floors are not interchangeable: `minQuality` is checked only in `chain()`; single-swing, continuation and micro-momentum each check their own family-specific threshold.

## Implications for recent experiments

1. The volume-confirmation and Fibonacci ablations establish that those optional gates sharply reduced entries in the StrategyTune research path. They do not establish the impact of native MQL5 mandatory scoring checks.
2. The `minQuality=68` no-change run was a wrong-gate experiment for the active fallback family. The follow-up `singleSwingMinQuality=68` experiment tested the actual StrategyTune single-swing gate and degraded the tested Aug–Sep 2025 fold (86 positions, 77.91% wins, +$14.62, PF 1.080) versus baseline (96 positions, 79.17%, +$25.85, PF 1.139). Reject the higher floor for that research configuration; do not infer a production EA parameter change.
3. The existing StrategyTune v2.14 entry attribution flag is deliberately false and position-outcome metrics are suppressed. Its `entryMap` records are entry-time lineage only. Authoritative outcomes must continue to be reconstructed from persisted session trade rows grouped by `openingFillId`; partial-close rows must not be counted as independent entries.
4. A StrategyTune run that has a clean result still omits broker commission, swaps and independent slippage. It cannot replace the matched native MT5 real-tick pair or broker-demo checks.

## Required next validation

- Keep the production additive router and single-swing fallback disabled by default.
- Treat StrategyTune family experiments as research-only unless the tested inputs and route exactly match the stated hypothesis.
- For native validation, execute the already documented matched baseline/router-enabled MT5 Strategy Tester pair with the same EA build, broker symbol contract, real-tick dataset, dates, account, costs and every non-router setting identical. The only allowed preset difference is the router-enable flag; keep single-swing fallback disabled in both.
- Preserve the locked-OOS reservation and do not run or tune on its reserved interval. Development testing must end before the reserved start, using the documented broker-server timezone evidence.
- Require complete tester metadata, deal export, commissions/swaps/fees, position identity, entry-family attribution, tick-level equity drawdown and cost-stress results. Then run broker-demo fault injection for stop changes, partial closes, timeouts, reconnects, duplicate events and restart recovery.
- Repair or independently validate StrategyTune's close observer only if the platform exposes a complete close-event stream. Until then, keep its position attribution marked invalid and use persisted session rows for realized outcomes.

## Files reviewed

- `research/strategytune/gold-m15/v2.14/strategy.ts` — StrategyTune research-only script, not MQL5.
- `development/EA/includes/Trading/FreshSweepAdditiveRouter.mqh` — native continuation/single-swing candidate builders and lane selection.
- `backend/source/docs/CONTINUATION_ROUTER_MATCHED_MT5_TEST_PLAN_2026-11-19.md` — native matched-pair protocol and production-default constraints.
- `research/STRATEGYTUNE_GOLD_M15_ENTRY_FILTER_ABLATION_2026-11-25.md` — recent research-only filter results.

**Decision:** no new strategy setting is promoted. No production source or risk control is changed. The next decisive evidence must come from the native matched MT5 experiment, not another unaligned StrategyTune parameter sweep.
