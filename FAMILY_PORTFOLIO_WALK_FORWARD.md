# MidasTouch2 — Independent Family and Portfolio Walk-Forward Research

**Status:** Research only. No production EA code or live risk settings changed.  
**Research script v1.1:** `a15gl2vswagiiobrul4z58uc` (compiled version 9)  
**Weekend-guard candidate:** `y8hhgudv0ojp8mf4dcmlrqdh` (version 1; compiled successfully)  
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

## Research-only weekend guard added

A separate StrategyTune strategy was created and compiled successfully:

- **Name:** MT2 Family Research v2 — Weekend Guard Candidate
- **Script ID:** `y8hhgudv0ojp8mf4dcmlrqdh`
- **Version:** 1
- **Compile status:** valid
- **New inputs:** `avoidWeekendExposure` (default false, for baseline parity) and `fridayCutoffHourUTC` (default 17).
- When explicitly enabled for research, the guard blocks entries after the configured Friday UTC cutoff and closes at most one remaining lot per market update. It returns before ordinary entry selection while the guard is active.
- Counters report Friday flatten actions, failed flatten attempts and blocked entry bars.

This is not added to the production MQL5 EA and is not yet validated. It must be tested on training data first, then a genuinely untouched later holdout. The May data that exposed the problem is now known and cannot be presented as an untouched validation period for this guard.

## Walk-forward status and next tests

**Completed:** one initial training window (April Gold) plus one cross-asset time holdout (May 1–14). The May holdout rejects the current baseline family configurations on profitability.

**Not completed:** a proper series of rolling monthly folds. The family settings were not broadly optimized in April, the May period has now been examined, and no June/July/August tests have been run in this pass.

A valid next sequence is:
1. Use a previously unexposed training window to select each family's entry quality, regime gate and exit design independently.
2. Lock that configuration before the next month.
3. Test on the following untouched month, grouped by original opening fill, and include open positions at the test boundary in marked P&L and exposure.
4. Repeat sequentially. Never tune on a month after inspecting its validation result and still call that month an out-of-sample holdout.
5. Run a shared-allocator portfolio simulation in MT5 Strategy Tester, including cross-symbol risk, correlation, weekend rules, gaps and broker execution. StrategyTune's independent symbol runs cannot prove this.

The current StrategyTune daily compute use reached approximately 586 of 600 seconds. No additional StrategyTune backtests were started after that limit was reached. The weekend guard has only been compiled; no performance claim is made for it.

## Promotion gates

No research candidate is eligible for production until all of the following are true:
- Full-position outcomes reconcile against every close row and open lot.
- Entry family, quality and regime labels are available per original opening fill.
- Stop movement, TP1, TP2, trailing behaviour, stop overshoot and gap handling are measured separately.
- Multiple rolling holdouts remain net profitable after realistic costs and show stable position-level expectancy; a 90% target is not accepted as a substitute for PF, expectancy or drawdown.
- The portfolio allocator enforces one shared risk budget and daily entry ceiling rather than per-symbol copies.
- The consolidated MQL5 EA passes Strategy Tester and broker-demo verification, including stop modification, weekend exposure and execution ledger checks.

**Decision:** reject both current family baskets as production candidates. Keep trend continuation as the more promising entry-family research baseline, not as a validated strategy. Keep the mean-reversion lane isolated until it has a distinct improvement in full-position expectancy. Prioritize the weekend gap guard and reliable entry/outcome attribution before another round of parameter optimization.
