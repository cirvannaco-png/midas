# Midas Touch 2 — Accuracy Research Note

Date: 2026-11-08  
Research branch: `research/restore-90-position-accuracy`  
Parent: `build/single-file-staging`  
EA staging baseline: `MidasTouch2.mq5` (no production trading-policy changes in this research note)

## Executive position

The research objective is to recover **at least 90% position-level win rate**, while also preserving positive expectancy, acceptable drawdown, and a healthy opportunity rate. The target of three qualified winners per trading day is a measurement objective, not permission to force weak entries.

The user's 500-record benchmark is real progress in the saved StrategyTune experiment:

| Variant | Closed trade records | Record win rate | Net P&L | Max drawdown | Last market timestamp reached |
|---|---:|---:|---:|---:|---|
| Existing settings | 500 | 88.0% | -$106.48 | $209.67 | 2026-01-20 13:34 UTC |
| Stricter quality + direction | 500 | 88.4% | -$55.63 | $180.37 | 2026-01-23 08:29 UTC |
| Strict filter + RVOL confirmation (1.2) | 500 | **90.4%** | **-$6.29** | **$98.85** | 2026-04-23 14:00 UTC |

The final variant improved net P&L by $100.19 versus the existing settings and lowered reported maximum drawdown by $110.82. It is the best of these three reported variants. It is **not yet a deployable result**: it still loses money, and the runs did not reach the same end timestamp.

### Comparability and statistical limits

All three tests were intended to cover 2025-11-07 through 2026-11-06, but StrategyTune stopped each at its 1,000 order-operation limit. Equal counts of 500 closed records therefore do not imply equal market exposure. The different cutoff dates mean the table is exploratory, not a clean paired comparison.

If each record were an independent, fully resolved trade, approximate 95% Wilson intervals would be 84.9–90.6% for 88.0%, 85.3–90.9% for 88.4%, and 87.5–92.7% for 90.4%. These intervals are illustrative only: records may be dependent, partial closes may be counted separately, and this table does not establish 500 independent positions.

The next report must show both:
- **Close-record win rate** — useful for reconciling fills and partial exits.
- **Position/decision win rate** — one outcome per independently opened position or decision after aggregating every partial close, commission, swap, fee and other known cashflow.

Position-level results are the primary accuracy metric.

## Additional partial-close audit — separate StrategyTune script

A separate saved script, `Midas Touch 2 Gold Profit Research — Strict Tier Disabled`, produced a 500-close-record Gold / IC Markets / M15 session:
- Run: `66f36e9d-938a-46b3-b816-7d699df89eb9`
- Saved record: `f468ly941x0ymssig6z3vstb`
- Engine P&L: -$58.74 USD; max drawdown: $120.53
- 500 closing records: 442 positive and 58 negative = 88.4% close-record win rate
- Those records came from 260 opening fills: 202 net-positive and 58 net-negative = **77.7% position win rate**
- Profit factor after grouping (same P&L, because all partial rows for each opening fill had the same sign in this sample): 0.894

This is **not one of the three benchmark configurations above**. It is a separate research script and an incomplete run. It stopped at the order-operation limit during March 2025, long before the requested 2025-12-31 endpoint. It must not be used as a substitute for the user's benchmark. It does demonstrate why partial closes must not be reported as independent trades.

In this separate run, profitable market-close rows summed to +$400.17, while stop-loss/take-profit rows summed to -$458.91. This is a diagnostic clue only—not a conclusion that exits are the sole cause. Exit reasons are row-level and this run is truncated; the next analysis must reconstruct complete position paths and use MFE/MAE, realized R, partial-exit sequence and all costs.

## Current MT5 EA source audit

The staging EA is not identical to the StrategyTune research proxy. Do not copy StrategyTune parameters directly into the MT5 EA without an equivalent MT5 test.

### Entry quality and volume

The current staging input defaults are:
- `InpRequireVolumeConfirmation=true`
- `InpRVOLThreshold=1.5`, `InpRVOLLookback=20`
- `InpRequireFibonacciZone=true`, Fibonacci pullback zone 50.0–61.8%
- `InpMinDirectionalAdvantage=0.0`

The benchmark's last variant used RVOL 1.2 and the stricter direction filter used an advantage of 8 in the StrategyTune research proxy. Thus, the benchmark settings are not the current EA defaults.

The EA's volume gate is a real hard entry gate in `CScoringEngine::CalculateConfidence()`; it rejects when the completed BOS-context bar's `RVOL(1)` is below threshold. Shift 1 is the completed candle, which avoids evaluating a partially formed current candle. In FX/CFD feeds this is quote/tick activity, not centralized exchange-traded volume. The filter's value must be measured per broker feed and instrument.

### Direction and market regime

The EA evaluates buy and sell candidates separately. When both are active, `InpMinDirectionalAdvantage` must be exceeded before either side is selected. The current default of 0.0 does not reproduce the stricter research setting of 8.

Regime routing is already wired into candidate generation:
- Trending regime: momentum/breakout candidate
- Ranging regime: mean-reversion candidate
- Transition regime: key-level candidate
- The selected peer candidate is compared against the SMC candidate, and `BuildAuthoritativeStrategy()` constructs the selected setup.

This is more than passive telemetry. The gap is reliable performance attribution: reports must show sample size, win rate, expectancy, profit factor, drawdown and trade frequency independently for SMC, momentum/breakout, mean reversion and key-level setups in each regime. A strategy family should not be merged into the production route merely because its in-sample win rate is high.

### Decision thresholds and calibration

`CScoringEngine::CalculateConfidence()` returns normalized raw confidence. The decision engine's primary execution threshold uses `setup.confidence` and environment policy. `OnTick()` attaches `GetCalibratedProbability()` to the setup for logging and downstream use; it does not replace raw confidence as the ordinary entry-admission threshold. Calibration is presently used in the multi-trade sizing/leg-selection path, subject to its own sample checks.

The current calibration engine is not yet a robust chronological model:
- 20 fixed bins, each five confidence points wide.
- Default minimum of 30 resolved win/loss outcomes per bin.
- Aggregate win/loss/scratch counters persist per symbol, without timestamps for each observation.
- The calibration file name does not include the decision's calibration/model version.
- It cannot restrict the estimate to the most recent chronological sample or audit a time-ordered train/validation boundary.

Required redesign before calibration can influence entry admission: persist timestamped, resolved position outcomes; scope them by symbol and scoring/model version; estimate from prior observations only; use a rolling or recency-aware sample; expose sample adequacy and uncertainty; treat insufficient data as UNKNOWN, not a negative signal. Any scoring-formula change must invalidate or segregate prior calibration.

### Three-winner daily target

The MT5 EA's daily target counts fully closed net winners that exceed the configured realized-R threshold (default target 3, default minimum 0.25R). It is a counter/reporting feature; it does not lower entry thresholds or force trades.

That distinction must be preserved. Three qualified opportunities/winners per day is an aspiration measured over eligible trading days, not a hard order quota. The separate StrategyTune `High-Accuracy Runner Exit Lab v1` research script contains fallback tiers that try single-swing, continuation and micro-momentum entries when the day's count is below three. That fallback behavior is not equivalent to the MT5 EA's passive daily target and should be disabled in any clean accuracy/frequency ablation unless it is explicitly the subject being tested.

## Experiment protocol

### 1. Reproduce the benchmark fairly

Re-run the three reported variants with identical provider, instrument, timeframe, date boundaries, starting balance, costs assumptions and execution model. Do not compare runs that stop at different dates. Where the 1,000 order-operation ceiling prevents a long run, divide the requested window into the same non-overlapping calendar segments for every variant, then aggregate position-level outcomes. Retain warm-up history while excluding warm-up trades from the scored segment.

Record the run ID and exact input values for every run. Report any missing bars, early-stop warning, data truncation or rejected order action. No warning-free, same-window results means no winner is declared.

### 2. Entry false-positive reduction

First keep exits and risk sizing locked. Compare:
1. Existing baseline.
2. Quality + directional-advantage filter.
3. RVOL filter alone.
4. Quality + direction + RVOL combination.

Do not stack extra filters until each independent contribution is measured. For each losing position, preserve decision ID, direction, setup family, regime, raw confidence, RVOL, sweep/BOS/displacement/FVG evidence, structure validity, spread/ATR, session, entry timing, stop distance and net realized R. Then rank loss frequency and loss expectancy by feature and interaction. Distinguish a predictive feature from a correlated description of a losing market.

### 3. Regime and strategy-family separation

Evaluate SMC, momentum/breakout, mean-reversion and key-level entries separately, first within their intended regime and then as a combined router. Reject a filter only when matched, sufficiently sampled tests show it has no reliable contribution. Keep the transition regime separate rather than forcing it into trend or range.

### 4. Exit counterfactuals

Keep entry rules fixed while comparing exit policies. For each complete position, capture:
- Maximum favourable and adverse excursion in R (MFE/MAE).
- Time and price when TP1/TP2, break-even and trailing actions occur.
- Partial-close sequence, final close reason and full net cashflow.
- Whether a profitable MFE was surrendered, a small early partial masked a losing final position, or a stop was allowed to exceed its planned risk.

A win-rate improvement that comes only from taking tiny profits while keeping large losses is rejected unless net expectancy, profit factor and drawdown also improve.

### 5. Calibration

Move from lifetime fixed bins to timestamped, versioned, per-symbol outcomes with time-ordered evaluation. Minimum sample size must be assessed per estimate; confidence/uncertainty should be reported. Training data must always precede validation data. Never fit a threshold using an untouched holdout.

### 6. Frequency without forced execution

Report eligible trading days, valid setup opportunities, entries, qualified closed winners (at or above the configured R threshold), average entries per eligible day, median, 10th/90th percentiles, and the proportion of eligible days with three qualified winners. Keep the daily target passive. Do not relax quality gates solely to meet a daily count.

## Promotion criteria

A research candidate is eligible for another validation stage only when it:
- Reaches at least 90% **position-level** win rate on the matched evaluation set.
- Has positive net expectancy and profit factor above 1 after all known costs.
- Improves or preserves drawdown within the account's risk limits.
- Maintains a healthy rate of eligible opportunities without forced entries.
- Survives a genuinely untouched, chronological out-of-sample period and then MT5 Strategy Tester / demo execution validation.

A 90% close-record win rate by itself does not pass.

## LONA limitation

The LONA Free plan showed zero spendable credits; two free optimizations remained. A prior intraday XAUUSD M15 optimization was refused because intraday global data was unavailable on that plan. A LONA dry-run smoke test completed without runtime error but is not a performance backtest. No LONA backtest or optimization result is claimed here.

## Release decision

**No EA source, entry threshold, risk parameter or live execution setting was changed by this research branch.** This branch updates the evidence and test protocol only. The last confirmed MetaEditor build remains the previous baseline; a documentation-only update does not constitute a new EA compile. Actual MT5 Strategy Tester validation, broker demo execution, protective-stop modification and execution-ledger reconciliation remain mandatory. Live trading is not approved by this research.
