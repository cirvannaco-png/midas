# Trend-continuation frequency lab — research only

**Status: promising research candidate; not production-approved.** This bundle preserves a reproducible StrategyTune experiment. It does not change the native MQL5 EA, risk engine, execution ledger or live configuration.

## Candidate changes

The separate v2.14 Gold M15 research fork disables the single-swing fallback and enables the continuation fallback. It lowers the continuation quality floor from 55 to 48, relaxes the minimum body ratio from 0.40 to 0.35, relaxes minimum range/ATR from 0.60 to 0.45, and expands the EMA pullback-touch scan from 5 to 8 bars. Every candidate comparison run explicitly overrides `maxDailyTrades=3`; the saved metadata default remains 6.

## Matched aggregate across seven segments

Gold / IC Markets / M15, USD 10,000 starting balance.

| Measure | Candidate | v2.14 baseline |
|---|---:|---:|
| Opening positions | 613 | 531 |
| Completed positions | 613 | 529 |
| Open at segment boundaries | 0 | 2 |
| Wins / losses | 495 / 118 | 407 / 122 |
| Complete-position win rate | 80.75% | 76.94% |
| Gross profit | $1,172.92 | $899.25 |
| Gross loss | $1,034.92 | $1,034.04 |
| Profit factor | 1.133 | 0.870 |
| Net realized P&L | +$138.00 | -$134.79 |
| Average win / loss | $2.37 / $8.77 | $2.21 / $8.48 |

Position count was **15.44% higher** than baseline. Net P&L was $272.79 better across the separate sessions. These are summed segment outcomes, not a single continuously compounded account curve.

## Segment detail

| Segment | Candidate positions | Candidate win rate | Candidate net | Candidate PF | Baseline positions* | Baseline win rate | Baseline net | Baseline PF |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2026 Q1 | 174 | 76.44% | -$52.81 | 0.853 | 144 | 71.53% | -$93.26 | 0.717 |
| 2026 Q2 | 180 | 82.78% | +$38.01 | 1.142 | 144 | 75.00% | -$86.56 | 0.723 |
| July 2026 | 55 | 76.36% | -$15.62 | 0.870 | 53 | 81.13% | -$3.23 | 0.966 |
| August 2026 | 56 | 85.71% | +$58.66 | 1.827 | 49 | 83.67% | +$36.37 | 1.529 |
| September 2026 | 63 | 82.54% | +$56.25 | 1.588 | 56 | 92.73% | +$64.93 | 2.834 |
| October 2026 | 60 | 81.67% | +$19.73 | 1.210 | 60 | 72.88% | -$25.87 | 0.803 |
| November 1–16 | 25 | 88.00% | +$33.78 | 2.240 | 25 | 72.00% | -$27.17 | 0.565 |

*Baseline September and October each ended with one position still open. Open P&L is excluded from realized P&L and win-rate calculations.

## Interpretation

The aggregate evidence is encouraging: activity is higher rather than lower, while aggregate win rate, profit factor and realized P&L improve. But the candidate does **not** beat the baseline in every segment. July was worse; September had a very strong baseline that this candidate did not surpass.

A stricter October diagnostic with `maxDailyTrades=2` produced 42 positions versus 60 baseline positions, with 85.71% win rate, PF 1.416 and +$23.49. It was rejected because it reduced trade count by 30%.

Average loss remains much larger than average win ($8.77 versus $2.37), so PF 1.133 has limited margin against costs.

## Limitations

1. **StrategyTune proxy only.** The candidate uses the `MidasTouch2NoQuotaResearch` class. It does not establish parity with the active MQL5 signal router, broker adapter, production risk engine, execution ledger or order lifecycle.
2. **No commission/slippage model.** StrategyTune uses recorded bid/ask fills but does not model commission or slippage. Results are pre-cost.
3. **Not a preregistered locked holdout.** October influenced initial candidate design, and feature/regime diagnostics were inspected during research. Treat these as exploratory matched-window comparisons, not formal untouched OOS certification.
4. **Two open baseline positions.** September and October baseline sessions ended with one open position each. Their unrealized P&L is excluded.
5. **Drawdown is per segment.** Each segment is a separate reset account; the per-segment maximum drawdowns are not one continuous equity curve.
6. **Sample uncertainty.** Monthly samples are modest and require further independent data and uncertainty intervals.

## Next gates

- Freeze the candidate and v2.14 baseline by source/script hash.
- Test additional chronological windows not used during design, with uncertainty intervals.
- Add conservative commission, spread-widening and slippage stress.
- Run native MT5 Strategy Tester parity checks against broker-specific symbols and contract specs.
- Run matched broker-demo tests for partial closes, stop changes, trailing, rejected orders, restart recovery and ledger reconciliation.
- Port to active MQL5 source only after code-level parity review and native testing.

**No production source, EA input or live-trading configuration was changed.**
