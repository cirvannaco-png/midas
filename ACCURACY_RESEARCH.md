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


## Fresh matched Gold M15 diagnostic — 2026-11-08

A new StrategyTune research batch used **Gold / IC Markets / M15**, USD 1,500 starting balance, requested window **2026-07-01 00:00 UTC through 2026-11-01 00:00 UTC**. These are saved StrategyTune research validators, not runs of the compiled MT5 EA. The feed is quote-driven; the optional RVOL check measures quote-update activity, not exchange-traded volume. Historical bid/ask is used, but the platform has no commission or slippage model.

### Results

| Causal v2.1 test | Closed trade records | Record win rate | Closed position groups | Position win rate | Net P&L | Net R | Max DD | Entries/day |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| No optional filter | 500* | 85.4%* | Not returned* | Not returned* | -$72.00* | Not returned* | $80.25* | Not reliable* |
| Quote-activity confirmation only (RVOL 1.5) | 25 | 84.0% | 14 | 71.4% | -$5.26 | -4.17R | $9.58 | 0.159 |
| Fibonacci zone only (50–61.8%) | 40 | 80.0% | 24 | 66.7% | -$13.78 | -4.25R | $15.37 | 0.273 |
| Both filters enabled | 0 | N/A | 0 | N/A | $0.00 | 0R | $0.00 | 0.000 |

`*` The no-filter run stopped at 1,000 order operations on **2026-10-29 19:05 UTC**, before the requested end date. It is an incomplete partial result: 500 closed trade records, 427 winners / 73 losers, -$72 P&L, $80.25 maximum drawdown, and one remaining open position. Its 85.4% is a close-record win rate, not a completed-position win rate.

The Strict Tier D v9 research script was also run on the same requested instrument, dates, timeframe and balance. It stopped at the same 1,000-operation cap on **2026-10-29 20:16 UTC** with 500 closed records, 447 wins / 53 losses (89.4% by close records), +$9.55 P&L and $10.46 maximum drawdown. Do not rank it against Causal v2.1 as a controlled one-variable ablation: the saved source implementations differ in more than the `minQuality` default (62 vs 101), and the cut-off timestamps are not identical.

The three filtered Causal v2.1 runs processed the complete available market-update stream to **2026-10-30 20:57 UTC** without the 1,000-operation stop warning. Their custom position counters provide a better unit than partial-close records:

- RVOL only: 14 completed position groups, 10 winners / 4 losers, 71.4% position win rate, -4.165 position R. It observed 88 days, met the configured 3-entry daily diagnostic on 0 days, and its busiest day had 2 entries.
- Fibonacci only: 24 completed position groups, 16 winners / 8 losers, 66.7% position win rate, -4.255 position R. It also met the 3-entry diagnostic on 0 of 88 days; busiest day had 2 entries.
- Both filters: no entries on any of the 88 observed days. The combination over-filters the strategy rather than improving its economics.

### Interpretation

1. The headline close-record win rate overstates trade-level quality when partial exits produce multiple records. Judge the full position group and R-multiple as well.
2. Neither one-filter variant has positive expectancy in this sample: both have negative total P&L and negative aggregate position R despite majority winning positions. This points to an adverse win/loss payoff distribution, not simply a lack of winning records.
3. Quote-activity confirmation sharply reduces frequency and drawdown, but did not make expectancy positive or meet the three-entry/day diagnostic. Fibonacci filtering was worse on P&L and position win rate. The combined filter blocks all participation.
4. Do not enable either filter as a live default, and do not lower thresholds to force the daily target. The next analysis should attribute average winning R, average losing R, tail losses, partial-exit contribution, and costs per complete position group; then test one exit change at a time on a matched training range and untouched OOS range.
5. These runs are strategy-validator diagnostics only. No profitability claim, broker execution claim, or live approval follows from them.


## Preserved findings from the earlier position-attribution research branch

The retired research branch contained a separate 500-close-record audit that is not the same experiment as either the 2025 benchmark table above or the fresh 2026 ablations:

- StrategyTune script: `Midas Touch 2 Gold Profit Research — Strict Tier Disabled`.
- Run ID: `66f36e9d-938a-46b3-b816-7d699df89eb9`; saved record: `f468ly941x0ymssig6z3vstb`.
- Gold / IC Markets / M15; engine P&L **-$58.74 USD**, maximum drawdown **$120.53**.
- The engine reported 500 closing records: 442 positive and 58 negative (**88.4% record win rate**).
- Those records traced to 260 opening fills: 202 net-positive and 58 net-negative (**77.7% position win rate**); grouped profit factor was **0.894**.
- The run was incomplete and stopped at the order-operation limit during March 2025, before its requested 2025-12-31 endpoint. It is a separate script, not a substitute for the three benchmark variants.
- In that sample, profitable market-close rows totalled +$400.17 while stop-loss/take-profit rows totalled -$458.91. This is a clue to investigate, not proof that exits alone caused the loss; the complete position paths, cost allocation, MFE/MAE and partial-exit sequence must be reconstructed.

This audit is the clearest existing evidence that a close-record win rate can materially overstate position-level accuracy. Position/decision-level outcomes must remain the primary metric.

## Current MT5 staging defaults and audit implications

The checked EA source currently defaults to:
- `InpRequireVolumeConfirmation=true`, `InpRVOLThreshold=1.5`, `InpRVOLLookback=20`.
- `InpRequireFibonacciZone=true`, with a 50.0–61.8% pullback zone.
- `InpMinDirectionalAdvantage=0.0`; it does not reproduce the research proxy's earlier directional-advantage setting of 8.

The live volume gate reads RVOL from the **most recently closed BOS-context bar (shift 1)**, avoiding partial-bar confirmation. On FX/CFD feeds this is quote/tick activity, not centralized exchange-traded volume. The gate's value must be evaluated per instrument and broker data feed.

The latest StrategyTune filter combination (quote-activity confirmation plus Fibonacci zone) produced no entries over the 88-day research sample. That is **not a direct MT5 EA test**: the research script and EA have different code paths and data/runtime assumptions. It is nevertheless a material risk signal because both filters are enabled in the current EA defaults. Do not silently disable either filter or promote them as proven. The next MT5 Strategy Tester ablation should isolate baseline, volume-only, Fibonacci-only and combined behavior using identical inputs except for the one tested gate.

The EA's daily target is separate from that StrategyTune validator diagnostic: MT5 counts one outcome only after the complete position closes, only when its realized result is at least +0.25R, and only on weekdays. It is passive telemetry and does not change the router or force entries. The research validator's `minDailyTradesTarget=3` diagnostic instead measures daily entry frequency and is not equivalent to three qualified closed winners.

## Calibration and regime attribution gaps

The current calibration engine uses 20 fixed bins, each five raw-confidence points wide, and defaults to 30 resolved win/loss samples per bin. Outcomes are persisted by symbol but are not individually timestamped, and the calibration filename does not carry the decision's calibration/model version. It therefore cannot establish a chronological training/validation boundary or cleanly separate observations produced by different scoring versions.

Before calibration influences entry admission or risk sizing, redesign it to persist timestamped, resolved position outcomes scoped by symbol and model/calibration version; estimate from prior observations only; expose sample adequacy and uncertainty; and return UNKNOWN when data is insufficient. Keep sparse estimates diagnostic only.

The EA has regime and strategy-family diagnostics for SMC, momentum/breakout, mean reversion and key-level reaction. Promotion needs independent sample size, win rate, expectancy, profit factor, drawdown and frequency by strategy family and regime. Do not combine a family into the authoritative router because of a high close-record win rate alone.


## Small-account risk-profile release blocker — 2026-11-08

A source audit of the selected default `ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT` found the current inputs:
- Target stop risk per trade: **20% of equity**.
- Minimum allowed planned risk: **15% of equity**.
- Maximum daily loss: **25% of equity**.
- Maximum peak drawdown: **35% of equity**.
- Maximum portfolio open risk: **20% of equity**.
- Progressive daily loss de-risk is disabled by default. The profile's 0.75 derisk floor still leaves a 15% per-trade target.

On an account with KSh 1,500 equity, that is KSh 300 target stop risk per ordinary trade, KSh 225 minimum accepted planned risk, KSh 375 daily-loss limit and KSh 525 drawdown limit. These are very aggressive settings. They are not equivalent to a 0.5% trade-risk policy.

The lot-sizing engine does correctly round down to the broker's volume step and refuses to raise an undersized request to the broker minimum; the `InpAllowMinLotOverride` input is retained for compatibility but does not override that hard rejection. However, the current source does **not** implement a separate explicit Gold minimum-volume stop-risk ceiling of KSh 7.50. It instead sizes toward the selected account risk budget (and refuses only when the broker minimum lot exceeds that much larger configured budget).

This is a production blocker. The 20% profile and KSh 7.50 Gold-minimum-lot constraint must be made coherent using the actual broker account currency and symbol contract specifications. No currency conversion, broker symbol mapping, or user-selected account currency should be guessed. Do not trade this small-account profile live until the risk policy is explicitly reconciled and verified in broker demo. The existing 20% profile is documented, not endorsed as safe.

## Next research steps

- Re-run the StrategyTune variants after the daily compute allowance resets, reducing trade-operation consumption (lower daily entry cap and/or less aggressive multi-tranche exits) so each run reaches the same end date. Keep the same instrument, provider, interval, balance, costs assumptions and dates across variants.
- Capture decision/group-level wins, losses, scratches, ambiguous outcomes, expectancy, profit factor, average win/loss, maximum drawdown and trades per month. Separate signal accuracy from exit-management performance.
- Compare baseline, strict quality gate, RVOL gate and environment/contradiction diagnostics on identical in-sample and untouched out-of-sample windows. Do not optimize directly on the OOS window.
- Investigate whether the high headline win rate is being purchased with small early partial profits and larger stop losses. Optimize expectancy and drawdown, not win rate alone.
- Only consider routing on calibrated probability or enabling additional hard gates after matched MT5 ablations, adequate per-bucket samples, versioned calibration and forward/demo validation.

## Release decision

**No EA source or trading parameters were changed by this accuracy investigation.** The generated single-file EA remains at the previously compiled baseline. These research results are incomplete and do not authorize live trading. Actual MT5 Strategy Tester validation, broker demo execution, and protective-stop modification/reconciliation remain mandatory.
