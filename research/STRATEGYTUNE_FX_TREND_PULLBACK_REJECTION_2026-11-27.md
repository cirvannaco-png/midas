# StrategyTune FX Trend-Pullback Candidate v1 — 11-Fold Rejection (2026-11-27)

## Decision

**REJECT — research only; do not port into the production MQL5 EA.**

A separate EURUSD/GBPUSD trend-pullback prototype compiled and was tested across eleven consecutive, non-overlapping monthly folds from 2025-12-13 through 2026-11-13. The aggregate result is negative on both instruments. The candidate is not robust, does not meet positive-expectancy / profit-factor gates, and has not been validated in native MT5.

No production MQL5 source, EA defaults, risk controls, or the main branch were changed by this experiment.

## Candidate definition

- StrategyTune script: `u1q58ejp5a9vdkd2thnjpmzh`
- Compiled version: 2
- Name: Midas FX Trend-Pullback Research Candidate v1
- Provider: IC Markets
- Instruments: EURUSD and GBPUSD
- Timeframe: M15
- Account currency: USD
- Starting balance: USD 10,000 independently for every fold
- Risk: 0.25% of balance per entry
- Entry: SMA(20)/SMA(50) directional alignment, minimum normalized trend gap and fast-average slope, a pullback to the fast average, then a bullish/bearish closed candle confirmation
- Stops/targets: 1.5 ATR stop, 1.8R take-profit
- Controls: one position at a time, two entries maximum per UTC day, 75-minute cooldown, UTC 07:00–20:00 entry window, spread gate at 0.08 ATR
- Both long and short entries enabled
- Strategy closes any remaining position at the end of each test window

The candidate is deliberately separate from the Gold trend-only research script. It is a hypothesis test, not a port of the production EA.

## Test design

Eleven contiguous monthly folds were used, each with a fresh USD 10,000 starting balance:

1. 2025-12-13 to 2026-01-13
2. 2026-01-13 to 2026-02-13
3. 2026-02-13 to 2026-03-13
4. 2026-03-13 to 2026-04-13
5. 2026-04-13 to 2026-05-13
6. 2026-05-13 to 2026-06-13
7. 2026-06-13 to 2026-07-13
8. 2026-07-13 to 2026-08-13
9. 2026-08-13 to 2026-09-13
10. 2026-09-13 to 2026-10-13
11. 2026-10-13 to 2026-11-13

The locked out-of-sample window beginning 2026-11-13 was not touched.

Metrics are calculated at the position-entry level by grouping all trade rows by `openingFillId` within each session record. This avoids counting partial close rows as independent entries. All candidate sessions ended flat; there were no residual open positions. P&L is in USD.

## EURUSD results

| Fold | Entries | Wins/Losses | Win rate | Profit factor | Net P&L | Max drawdown |
|---|---:|---:|---:|---:|---:|---:|
| 2025-12-13–2026-01-13 | 26 | 12/14 | 46.2% | 1.527 | +187.59 | 122.57 |
| 2026-01-13–2026-02-13 | 28 | 7/21 | 25.0% | 0.585 | -218.94 | 254.46 |
| 2026-02-13–2026-03-13 | 25 | 10/15 | 40.0% | 1.083 | +30.45 | 177.37 |
| 2026-03-13–2026-04-13 | 28 | 10/18 | 35.7% | 0.762 | -135.79 | 378.67 |
| 2026-04-13–2026-05-13 | 32 | 13/19 | 40.6% | 1.045 | +25.13 | 206.46 |
| 2026-05-13–2026-06-13 | 21 | 5/16 | 23.8% | 0.606 | -152.67 | 210.40 |
| 2026-06-13–2026-07-13 | 28 | 7/21 | 25.0% | 0.583 | -227.15 | 307.75 |
| 2026-07-13–2026-08-13 | 29 | 7/22 | 24.1% | 0.838 | -88.40 | 365.01 |
| 2026-08-13–2026-09-13 | 28 | 8/20 | 28.6% | 0.677 | -169.52 | 234.33 |
| 2026-09-13–2026-10-13 | 28 | 11/17 | 39.3% | 1.111 | +49.03 | 168.97 |
| 2026-10-13–2026-11-13 | 33 | 9/24 | 27.3% | 0.651 | -211.95 | 293.28 |
| **Total** | **306** | **99/207** | **32.4%** | **0.832** | **-912.22** | — |

EURUSD produced positive net P&L in only 4 of 11 folds. Aggregate gross profit was USD 4,515.83 against gross loss of USD 5,428.05. Aggregate expectancy was -USD 2.98 per entry.

## GBPUSD results

| Fold | Entries | Wins/Losses | Win rate | Profit factor | Net P&L | Max drawdown |
|---|---:|---:|---:|---:|---:|---:|
| 2025-12-13–2026-01-13 | 25 | 10/15 | 40.0% | 1.183 | +68.09 | 159.98 |
| 2026-01-13–2026-02-13 | 34 | 16/18 | 47.1% | 1.627 | +278.45 | 136.41 |
| 2026-02-13–2026-03-13 | 20 | 5/15 | 25.0% | 0.501 | -180.73 | 321.73 |
| 2026-03-13–2026-04-13 | 27 | 12/15 | 44.4% | 1.375 | +143.91 | 142.71 |
| 2026-04-13–2026-05-13 | 26 | 9/17 | 34.6% | 0.888 | -50.37 | 127.52 |
| 2026-05-13–2026-06-13 | 32 | 7/25 | 21.9% | 0.505 | -306.24 | 387.09 |
| 2026-06-13–2026-07-13 | 25 | 7/18 | 28.0% | 0.686 | -140.55 | 212.71 |
| 2026-07-13–2026-08-13 | 23 | 5/18 | 21.7% | 0.494 | -225.87 | 273.20 |
| 2026-08-13–2026-09-13 | 26 | 8/18 | 30.8% | 0.710 | -129.79 | 219.62 |
| 2026-09-13–2026-10-13 | 30 | 10/20 | 33.3% | 0.892 | -53.75 | 184.01 |
| 2026-10-13–2026-11-13 | 34 | 9/25 | 26.5% | 0.629 | -232.86 | 306.23 |
| **Total** | **302** | **98/204** | **32.5%** | **0.837** | **-829.71** | — |

GBPUSD produced positive net P&L in only 3 of 11 folds. Aggregate gross profit was USD 4,269.91 against gross loss of USD 5,099.62. Aggregate expectancy was -USD 2.75 per entry.

## Interpretation

1. The initial positive folds were regime-dependent and reversed in subsequent folds.
2. EURUSD and GBPUSD both failed the aggregate PF > 1 and positive expectancy gates.
3. The GBPUSD early five-fold aggregate was slightly positive, but the later six folds were materially negative. This is precisely why the full chronological sequence matters.
4. Win rate is not the objective. Both instruments had approximately 32% aggregate wins; the 1.8R target did not compensate for the observed loss distribution.
5. The large fold drawdowns relative to a USD 10,000 starting balance reinforce rejection.

## Limitations

- StrategyTune models recorded bid/ask fills but does not provide commission or slippage modelling. Real-world net results would be worse if those costs are material.
- This is not a native MetaTrader 5 real-tick test and is not proof of parity with the production MQL5 EA.
- The account balance is USD 10,000, not the user's KSh 1,500 operating context. No small-account lot-size feasibility is established.
- No live trading was performed.
- The reserved out-of-sample interval from 2026-11-13 through 2027-02-13 remains untouched.

## Engineering disposition

- Keep this StrategyTune script as a rejected research artifact for reproducibility; do not make it a default or dependency of the production EA.
- Do not change the EA's entry logic, risk engine, sizing, SL/TP, trailing, partial-close, recovery, execution-ledger, or manual controls based on these results.
- Keep Gold's two-way trading policy intact.
- The next useful work is not parameter optimization of this rejected prototype. It is to audit the production EA's entry attribution and risk-adjusted outcomes by instrument, direction, setup family, session, spread/volatility regime, and exit reason, then form a new falsifiable hypothesis from those diagnostics.
- Any future candidate must pass multiple chronological folds, position-level PF and expectancy after realistic costs, drawdown gates, and native MT5 validation before code integration.
