# MidasTouch2 — Independent Family and Portfolio Walk-Forward Research

**Status:** Research only. No production EA code or live risk settings changed.  
**Research script v1.1:** `a15gl2vswagiiobrul4z58uc` (compiled version 9)  
**Current research candidate:** `y8hhgudv0ojp8mf4dcmlrqdh` (version 4; compiled successfully)  
**Instrument / timeframe:** IC Markets, M15  
**Report date:** 2026-11-08

## Executive conclusion

The initial family isolation and cross-asset study does **not** validate a 90% full-position win rate or a profitable three-instrument portfolio.

The liquidity-sweep/reclaim (mean-reversion) and trend-continuation families can both generate enough opportunities across Gold, EURUSD and Nasdaq 100 to exceed three winning positions on several days. However, both three-symbol baskets lost money in the May 1–14, 2026 test window. The trend-continuation basket reached at least three winning positions on all 10 active days, yet had only a 77.91% full-position win rate, a 0.63 profit factor and an estimated marked loss of $75.59 on $30,000 combined starting capital.

This is a clear rejection of optimizing for daily winner count or close-record win rate at the expense of payoff asymmetry.

A material risk defect also emerged: multiple Friday positions were held through the weekend and closed at the Sunday reopening price, materially beyond their recorded stops. This was responsible for most of the two baskets' negative result in the May window. A research-only weekend guard has now been added as a separate compiled StrategyTune script, but it has not yet been backtested.

## Scope and interpretation

StrategyTune runs one instrument per backtest. The multi-instrument result below is therefore an external portfolio proxy assembled from the three independently saved sessions and their timestamps, not a simultaneous StrategyTune portfolio backtest.

Each instrument run used a $10,000 USD simulated account. The portfolio proxy sums three equal $10,000 sleeves. Each new position used 0.10% simulated balance risk ($10 nominal stop risk per $10,000 sleeve), with a six-entry daily ceiling **per instrument run**, maximum nine concurrent lots per run, and 2.25% maximum open-risk check per run. These are research settings, not a statement of the user's live account allocation.

The three-position daily target was diagnostic only. It did not cause or authorize trades. No missing opportunities were filled artificially.

StrategyTune models recorded bid/ask movement but has no commission or independent slippage model. The backtests are not proof of broker execution, gap fills or live profitability.

## Entry families isolated

- **Liquidity-sweep/reclaim:** the existing `singleSwingChain` path, which looks for a prior swing level sweep/reclaim and a microstructure break. It is treated as the mean-reversion/reversal family for this study; it is not a pure statistical mean-reversion model.
- **Trend continuation:** the existing `continuationChain` path, which requires aligned 20/50-bar means, a pullback toward the fast mean and a subsequent short-term break.
- Strict SMC chain and micro-momentum fallback were disabled in both family-isolation runs. This prevents those routes from contaminating the separate family results.

These are existing research functions gated independently. This study did not rewrite or change the production MQL5 EA.

## Fold 1 — Gold training window

**Training:** 2026-04-01 through 2026-04-30, Gold M15, IC Markets.

| Measure | Liquidity-sweep / reclaim | Trend continuation |
|---|---:|---:|
| Completed opening-fill positions | 52 | 64 |
| Winning positions | 38 | 52 |
| Losing positions | 14 | 12 |
| Full-position win rate | 73.08% | 81.25% |
| Position-level net P&L | -$49.16 | +$12.51 |
| Profit factor | 0.62 | 1.12 |
| Average winning-position P&L | +$2.09 | +$2.29 |
| Average losing-position P&L | -$9.18 | -$8.87 |
| Active days with at least 3 winning positions | 6 / 20 | 11 / 21 |
| Average winning positions per active day | 1.90 | 2.48 |

The continuation family was the better training candidate, but its PF of 1.12 was weak and did not cover the average-loss/average-win asymmetry by a comfortable margin. The mean-reversion family failed on both P&L and profit factor.

The family settings were a baseline isolation, not the result of a broad parameter search. No 90% candidate was selected or promoted.

## Fold 1 holdout / cross-asset extension

**Observed holdout:** 2026-05-01 through 2026-05-14, M15, IC Markets.  
**Symbols:** Gold, EURUSD and Nasdaq 100.

### Per-instrument full-position results

| Family | Instrument | Completed positions | Wins / losses | Full-position WR | P&L of completed positions | PF |
|---|---|---:|---:|---:|---:|---:|
| Mean-reversion | Gold | 22 | 17 / 5 | 77.27% | -$3.43 | 0.92 |
| Mean-reversion | EURUSD | 26 | 21 / 5 | 80.77% | -$34.45 | 0.50 |
| Mean-reversion | Nasdaq 100 | 13 | 9 / 4 | 69.23% | -$16.38 | 0.40 |
| Trend continuation | Gold | 31 | 24 / 7 | 77.42% | -$4.63 | 0.93 |
| Trend continuation | EURUSD | 39 | 29 / 10 | 74.36% | -$78.69 | 0.40 |
| Trend continuation | Nasdaq 100 | 16 | 14 / 2 | 87.50% | +$4.72 | 1.29 |

A few positions remained open at the end of the window. Their realized partial P&L is included in engine realized totals; their unrealized P&L is stated separately below. Position win rates exclude unfinished positions.

### Portfolio opportunity proxy

| Measure | Mean-reversion basket | Trend-continuation basket |
|---|---:|---:|
| Instruments | 3 | 3 |
| Completed positions | 61 | 86 |
| Wins / losses | 47 / 14 | 67 / 19 |
| Full-position win rate | 77.05% | 77.91% |
| Gross winning P&L | $83.90 | $133.96 |
| Gross losing P&L | $138.16 | $212.56 |
| Profit factor | 0.61 | 0.63 |
| Average win | +$1.78 | +$2.00 |
| Average loss | -$9.87 | -$11.19 |
| Partial-exit positions | 48 / 61 | 68 / 86 |
| Active days | 10 | 10 |
| Days with at least 3 winning full positions | 8 / 10 | 10 / 10 |
| Average winners per active day | 4.70 | 6.70 |
| Peak concurrent open positions (timestamp proxy) | 4 | 6 |
| Approx. peak nominal initial stop risk | $40 | $60 |
| Marked basket P&L (including open P&L) | -$56.97 | -$75.59 |
| Combined starting capital | $30,000 | $30,000 |
| Marked return on combined starting capital | -0.190% | -0.252% |

The portfolio proxy proves only that multiple instruments can increase the number of daily winning positions. It does not validate the shared risk allocator: the per-symbol daily cap and open-risk cap ran independently. A real portfolio allocator must enforce a single portfolio-wide limit, account for correlated USD exposures and synchronize risk across symbols.

The 0.10% per-position figures are initial nominal risk estimates. Peak exposure above is calculated from the maximum timestamp overlap multiplied by $10 per open position. It is not a broker margin or stressed-gap risk measure.

### Daily opportunity is not profitability

The continuation basket produced at least three winning positions on all ten active days, averaging 6.7 winners per active day. It still lost money. On May 8 alone it recorded six winners and six losers but lost approximately $91.25. The mean-reversion basket also recorded five winners and five losers that day and lost approximately $58.22.

A minimum winner count is therefore a poor primary objective. It can reward strategies that generate many small wins while retaining occasional full-size losses.

## Win-rate accounting and partial exits

A closed row is not necessarily a separate position. Several close rows can share one `openingFillId` when TP1/TP2 or another partial exit closes part of the same lot.

| May 1–14 basket measure | Mean-reversion | Trend continuation |
|---|---:|---:|
| Closed rows | 115 | 166 |
| Positive closed rows | 101 | 147 |
| Close-row win rate | 87.83% | 88.55% |
| Completed original positions | 61 | 86 |
| Winning original positions | 47 | 67 |
| Correct full-position win rate | 77.05% | 77.91% |

Counting close rows as separate wins overstates position win rate by approximately 10.8 and 10.6 percentage points, respectively. Close-row win rate must not be used as a strategy-selection metric.

Current research exits are: TP1 at 0.25R closing 40%, stop moved to +0.1R, TP2 at 1R closing another 20% of original quantity, then a 1.2 ATR trailing runner. Important implementation detail: the input named `beOffsetATR` is multiplied by the initial stop distance (`st.risk`), so its current value 0.1 means +0.1R, not +0.1 ATR. The name and unit should be corrected before this code is treated as a stable parameter interface.

On April Gold:
- Mean-reversion reached TP1 on 73.08% of completed positions and TP2 on 9.62%.
- Continuation reached TP1 on 81.25% and TP2 on 9.38%.
- Only 3.85% of mean-reversion positions reached 2R; 1.56% of continuation positions reached 2R; neither family recorded a 3R rate above zero.

The exit profile is creating many small realized gains while a full initial stop can erase several of them. Average losing positions were approximately four to five times the average winning-position gain in the May baskets.

## Stop behaviour and weekend gap finding

The trade table's `exitReason` combines stop-loss and take-profit into one category. For a more defensible stop analysis, close-price distance was normalized by the original stop distance:

`adverse stop overshoot R = (close beyond stop in the adverse direction) / abs(entry - initial stop)`

Positive overshoot means the closing price was worse than the stop level. Median overshoots were generally small, but tail events occurred on EURUSD and Gold.

| Family | Instrument | Stop/TP-labelled close rows | Median adverse overshoot | Maximum adverse overshoot |
|---|---|---:|---:|---:|
| Mean-reversion | Gold | 17 | 0.003R | 0.029R |
| Mean-reversion | EURUSD | 25 | 0.005R | 3.015R |
| Mean-reversion | Nasdaq 100 | 13 | 0.002R | 0.033R |
| Trend continuation | Gold | 24 | 0.004R | 0.648R |
| Trend continuation | EURUSD | 37 | 0.007R | 4.796R |
| Trend continuation | Nasdaq 100 | 14 | 0.003R | 0.029R |

The dominant tail event was the weekend opening gap. Several positions opened on Friday, May 8, then closed on Sunday, May 10, at the same reopening price:
- Mean-reversion: four Friday-to-Sunday positions, net -$48.01.
- Trend continuation: three Friday-to-Sunday positions, net -$72.07.

Three EURUSD long positions in the mean-reversion family and two EURUSD longs in continuation closed materially beyond their recorded stop levels. For example, a continuation EURUSD position opened at 1.17835 with a stop moved to 1.17843, then closed at 1.17466 at the Sunday reopening. Its close was about 4.80 times the original stop distance beyond the moved stop.

These losses explain most of the aggregate May basket drawdown. The current strategy's session-hour gate controls when it can enter but does not close positions or block Friday entries before the weekend. This is a risk-policy defect, not an entry-quality problem.

The platform does not model broker commissions or an independent slippage schedule. The observed gap is present in the recorded quote path; the size and execution handling must still be validated in a real MT5 broker demo.

## Entry quality and market regime: what is and is not known

The internal position-attribution tracker was valid for the April mean-reversion run, but not for April continuation (two missed close events, $9.63 P&L mismatch). It was invalid in four of the six May instrument runs. Consequently, tracker-derived feature means and per-regime outcome metrics from those invalid runs are excluded from selection.

On April Gold, entry-quality averages did not discriminate winners:
- Mean-reversion: winner mean 95.74 vs loser mean 95.50.
- Continuation: winner mean 88.40 vs loser mean 90.10.

A larger score was not evidence of a higher calibrated probability of success. No claim is made that the current score predicts a 90% win probability.

The existing telemetry uses a simple 8-bar vs 21-bar mean gap normalized by ATR: below 0.20 is labelled range-like, 0.20–0.45 transition and at least 0.45 trend-like. This is a rough proxy, not a validated market-regime classifier. The April samples showed that continuation performed better in the range and transition proxy buckets than in the trend bucket, but sample counts were small and the tracker limitation prevents treating this as a stable regime-selection rule. No regime gate is promoted.

The next version should produce a reliable entry-level audit trail for every opening fill: family, side, quality components, market regime at decision time, stop distance, spread/ATR, volatility and session context. Outcomes must then be reconciled against the saved position ledger. Averages without reliable entry-to-outcome linkage are not adequate for false-positive attribution.

## Research harness v2.2 — family regimes, exits and weekend protection

A separate StrategyTune research strategy is maintained independently from the consolidated production MQL5 EA:

- **Name:** MT2 Family Research v2.2 — Regime and Family Exits
- **Script ID:** `y8hhgudv0ojp8mf4dcmlrqdh`
- **Version:** 4
- **Compile status:** valid; `compileFailed=false`
- **New weekend behaviour:** when `avoidWeekendExposure=true`, block entries after the Friday UTC cutoff, flatten the entire net position through one `closePosition()` request, and block Saturday/Sunday entries. Diagnostics report flatten calls, failures, lots targeted, bars blocked and residual lots at finish.
- **Regime eligibility:** optional `rangeOnlySingleSwing` and `trendOnlyContinuation` gates. The existing research proxy is absolute 8-bar vs 21-bar mean separation divided by ATR: range below 0.20, transition from 0.20 to below 0.45, trend at or above 0.45. Enabling the family-specific gates excludes the transition bucket from both specialist families. This is a study proxy, not the production EA's classifier.
- **Independent stop controls:** separate stop buffer and maximum stop-distance inputs for sweep/reclaim and continuation families.
- **Independent exit controls:** separate TP1/TP2 R multiples, partial-close fractions, BE offsets in R, and trailing ATR distances for each family. Defaults match the previously tested shared exit configuration, preserving baseline behaviour until the inputs are deliberately varied.
- **Safety:** `minDailyTrades` remains diagnostic only; it does not force entries. This remains research code and is not deployed in the production EA.

The shared break-even input is named `beOffsetR` because the value is applied as a fraction of the original stop distance, not as an ATR multiple. Family-specific break-even inputs use the same R unit. The guard uses one account-wide flatten request to reduce the chance of leaving residual lots at the weekend boundary. If multiple lots close on the same update, the script's single-`lastClosedTrade` attribution path can miss close events; it explicitly invalidates the internal tracker when that occurs. Full-position outcomes must then be rebuilt from saved session rows grouped by original opening fill. A compile success is not a performance validation.

The previous v2.0 guard closed only one lot per update and blocked only Friday-after-cutoff entries. Version 3 supersedes that weaker behaviour. No backtest has yet been run on the new guard or the family-specific regime/exit controls.

## Walk-forward status and next tests

**Completed:** one initial training window (April Gold) plus one cross-asset time holdout (May 1–14). The May holdout rejects the current baseline family configurations on profitability.

**Not completed:** a proper series of rolling monthly folds. The family settings were not broadly optimized in April, the May period has now been examined, and no June/July/August tests have been run in this pass.

A valid next sequence is:
1. Use a previously unexposed training window to select each family's entry quality, regime gate and exit design independently.
2. Lock that configuration before the next month.
3. Test on the following untouched month, grouped by original opening fill, and include open positions at the test boundary in marked P&L and exposure.
4. Repeat sequentially. Never tune on a month after inspecting its validation result and still call that month an out-of-sample holdout.
5. Run a shared-allocator portfolio simulation in MT5 Strategy Tester, including cross-symbol risk, correlation, weekend rules, gaps and broker execution. StrategyTune's independent symbol runs cannot prove this.

At the time of the first report, the daily compute counter was nearly exhausted, so no additional runs were launched then. After the UTC reset, the v4 harness was tested on June and July 2026 Gold M15 folds with the weekend guard and family gates enabled. Those results and limitations are documented in the addendum below.

## Production EA portfolio audit — allocator is not yet a multi-symbol opportunity engine

I inspected the consolidated `MidasTouch2.mq5` on this branch after the StrategyTune portfolio proxy. The distinction is important:

- `CPortfolioManager` does aggregate stop-based risk from open positions and pending orders across symbols that share the configured Midas magic number. It also enforces per-symbol and coarse group count limits. Unknown protection geometry fails closed for positions/orders included in that calculation.
- That risk sum filters by `POSITION_MAGIC` and `ORDER_MAGIC` equal to the configured magic. It therefore does **not** currently account for manual or other-EA exposure under different magic numbers.
- The group classifier is a static symbol-name bucket (crypto, metals, indices, default FX). It does not calculate signed currency-factor exposure or rolling empirical correlation.
- The manager does not calculate projected portfolio margin or margin utilization as part of its `AllowNewTradeBatch` admission check.
- `CTFContextPool` is configured with `_Symbol`; it creates multiple timeframe contexts for that one symbol. The normal `OnTick` entry path generates buy/sell setups from the chart-symbol decision engine. `InpEnableMultiTrade` creates two- or three-leg batches on the current `_Symbol`; it is not multi-symbol scanning.
- Multiple chart instances can each run on their own chart symbol and the same magic-number risk gate can observe already-open/pending exposure from those instances. But there is no single candidate queue, cross-symbol ranking step or atomic reserve-before-submit mechanism visible in this manager. A concurrent multi-chart admission race must be tested and addressed before calling the risk budget authoritative.

**Conclusion:** the EA has a useful same-magic cross-symbol stop-risk gate, but it does not yet implement the requested account-wide multi-symbol opportunity allocator. The next production-engineering step is not to weaken the existing risk limits. It is to add symbol contexts, a shared opportunity queue, account-wide external exposure policy, margin and factor-risk checks, and atomic reservations while retaining the current gates as defence in depth.

The implementation specification is recorded here: [PORTFOLIO_OPPORTUNITY_MODEL_SPEC.md](PORTFOLIO_OPPORTUNITY_MODEL_SPEC.md). It defines the candidate contract, regime routing, expected-net-R ranking, account-wide budget, margin/factor exposure, atomic reservations, position ledger and synchronized MT5 validation protocol. It is an architecture specification only; no production MQL5 code was changed in this step.

## Promotion gates

No research candidate is eligible for production until all of the following are true:
- Full-position outcomes reconcile against every close row and open lot.
- Entry family, quality and regime labels are available per original opening fill.
- Stop movement, TP1, TP2, trailing behaviour, stop overshoot and gap handling are measured separately.
- Multiple rolling holdouts remain net profitable after realistic costs and show stable position-level expectancy; a 90% target is not accepted as a substitute for PF, expectancy or drawdown.
- The portfolio allocator enforces one shared risk budget and daily entry ceiling rather than per-symbol copies.
- The consolidated MQL5 EA passes Strategy Tester and broker-demo verification, including stop modification, weekend exposure and execution ledger checks.

**Decision:** reject both current family baskets as production candidates. Keep trend continuation as the more promising entry-family research baseline, not as a validated strategy. Keep the mean-reversion lane isolated until it has a distinct improvement in full-position expectancy. Prioritize the weekend gap guard and reliable entry/outcome attribution before another round of parameter optimization.


## Fold 2 — June baseline / July frozen-configuration holdout (Gold M15)

**Research dates:** June 1–30, 2026 (baseline/selection window) and July 1–31, 2026 (untouched holdout).  
**Instrument:** Gold, IC Markets, M15.  
**Harness:** StrategyTune script `y8hhgudv0ojp8mf4dcmlrqdh`, compiled version 4.  
**Shared settings:** strict chain disabled by setting its quality threshold above the valid range; micro-momentum disabled; only one specialist family enabled per run; 0.10% simulated risk per entry; six-entry daily ceiling; 2.25% run-level open-risk cap; Friday 17:00 UTC cutoff and weekend flatten enabled. The three-entry minimum remained diagnostic only.

Important qualification: June and July used the same fixed family settings. June was not used for an extensive parameter optimization, and July was not used to retune the configurations. July is therefore a frozen-configuration temporal holdout, not proof of a fully trained/calibrated model. Results remain single-instrument simulations, not a synchronized portfolio test.

### Position-level results (grouped by original opening fill)

| Fold | Family | Closed rows | Original positions | Wins / losses | Full-position WR | Net P&L | PF | Close-row WR | Partial-exit positions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| June | Sweep/reclaim, range-only | 66 | 33 | 27 / 6 | 81.82% | +$4.71 | 1.085 | 90.91% | 27 / 33 |
| June | Continuation, trend-only | 81 | 43 | 30 / 13 | 69.77% | -$41.19 | 0.634 | 83.95% | 30 / 43 |
| July | Sweep/reclaim, range-only | 46 | 25 | 15 / 10 | 60.00% | -$31.18 | 0.629 | 78.26% | 15 / 25 |
| July | Continuation, trend-only | 62 | 32 | 25 / 7 | 78.13% | -$5.39 | 0.912 | 88.71% | 25 / 32 |

All monetary values are simulated USD. Position P&L and PF were independently recomputed from the saved session trade rows grouped by `openingFillId`, summing every partial close belonging to the original opening fill. This is the authoritative calculation for this fold.

### Interpretation

- The range-only sweep/reclaim family moved from a small positive June result to a materially negative July holdout: full-position WR fell from 81.82% to 60.00%, PF from 1.085 to 0.629, and P&L from +$4.71 to -$31.18. Reject it as a production candidate.
- Trend continuation improved its position win rate from 69.77% to 78.13%, but remained negative in both folds: -$41.19 in June and -$5.39 in July; July PF was still below 1.0. Do not promote it.
- The attractive close-row rates (up to 90.91%) are again materially higher than full-position rates because partial exits generate multiple rows per opening fill. They are not strategy win rates.
- Neither family reliably met the three-entry daily objective. The research counter records days with at least three entries, not three winning full positions: sweep/reclaim met the entry count on 4/22 June eligible days and 4/23 July eligible days; continuation met it on 6/22 June days and 4/23 July days. No entries were forced.
- Weekend protection executed in July: one account-wide flatten call per family run, one lot targeted, zero flatten errors and zero residual lots at the end. No weekend flatten was needed in the June runs. This verifies that the research guard path was exercised in this sample, not that a broker will guarantee a stop/market exit across all real market closures.

### Attribution and telemetry caveats

- June sweep/reclaim position attribution was internally valid and matched saved-row P&L.
- June continuation attribution was invalid: one missed close event and a $4.32 difference versus saved-row P&L. Use saved-row grouping only.
- July sweep/reclaim attribution was invalid: two missed close events and a $7.84 P&L difference. Use saved-row grouping only.
- July continuation attribution was valid and matched saved-row P&L.
- Every run returned an explicit warning that the script emitted 111 custom-stat keys while the result limit retained only 100. The backtests themselves completed and aggregate trade statistics were valid, but 11 telemetry fields were dropped. Missing telemetry must not be interpreted as zero. Before the next research batch, reduce the script's emitted custom-stat set to a deliberate, prioritized subset so the key diagnostics fit within the result limit.
- StrategyTune's engine-level win/loss counts are close-record statistics. The independent position-level figures above are grouped from the saved session table and must be preferred for strategy evaluation.

### Decision after June/July

Both isolated families remain rejected as production candidates. The continuation family is less weak than sweep/reclaim on July, but its PF remains below 1 and its June loss was substantial. The June-to-July variation also shows why a single attractive training window is insufficient.

Do not broaden into a larger cross-asset sweep yet. First harden research telemetry and stop/exit attribution, then test a small number of predeclared hypotheses on later untouched folds. The next unexposed chronological period after the inspected April–July windows is August 2026; it must remain untouched until any candidate and its parameters are frozen.
