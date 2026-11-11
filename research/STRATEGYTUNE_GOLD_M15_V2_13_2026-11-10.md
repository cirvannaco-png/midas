# Gold M15 StrategyTune research archive

This directory preserves the StrategyTune strategy proxies used in the November 2026 Gold research sequence. These files are **research artifacts**, not MQL5 source and not live-trading approvals. StrategyTune executes them in its own cloud runtime; they do not execute the native MT5 EA, broker adapter, execution ledger, or MT5 trailing-stop implementation.

## Archived candidates

| Candidate | StrategyTune script ID | Compiled version | Role |
|---|---|---:|---|
| v2.6 Regime Gate Strict-Off | `yzt9i490pquc1ozwiugl9qyy` | 2 | Control |
| v2.7 TP1 0.50R Exit Test | `ij2p286axsiarpfpf19ne2m2` | 2 | Rejected exit variant |
| v2.12 Gold Regime-Specialist Hybrid | `qz7i215ifbp0cysdtdsurhcm` | 2 | Trend single-swing + transition continuation |
| v2.13 Gold Trend-Single-Swing Ablation | `vr385fjuflmk0g9i5tz1wltx` | 1 | Current strongest research candidate; not approved |

Each candidate folder contains the exact StrategyTune metadata and source code exported from the compiled script version. Metadata and code must be treated as a coupled artifact. Do not change one without compiling and versioning the pair in StrategyTune.

## Research protocol

- Instrument/provider: Gold / IC Markets.
- Timeframe: M15.
- Account currency: USD.
- Starting balance: USD 10,000 for each independent monthly run.
- Position accounting: partial closes are grouped by opening fill; open remainders are not counted as completed positions.
- Daily minimum of three entries is an opportunity diagnostic only; no trades are forced.
- Monthly results are independent runs, each reset to USD 10,000. Their summed P&L is a comparable monthly-fold diagnostic, **not** one continuously compounded annual equity curve.
- StrategyTune uses recorded bid/ask data but does not apply commission or slippage. Results are not fully cost-inclusive and are not broker-demo evidence.

## v2.13 results

### 2025 monthly folds

| Month | Net P&L (USD) | Entries | Maximum drawdown (USD) |
|---|---:|---:|---:|
| Jan | -20.50 | 58 | 64.62 |
| Feb | -10.62 | 45 | 52.70 |
| Mar | -1.87 | 46 | 47.53 |
| Apr | -8.63 | 50 | 70.16 |
| May | +10.82 | 56 | 30.52 |
| Jun | +29.32 | 45 | 33.93 |
| Jul | -117.31 | 50 | 132.08 |
| Aug | +1.14 | 53 | 53.96 |
| Sep | +24.71 | 43 | 43.39 |
| Oct | -74.00 | 55 | 85.46 |
| Nov | +69.76 | 47 | 27.01 |
| Dec | +16.53 | 50 | 32.07 |
| **Sum of independent monthly folds** | **-80.65** | **598** | **Mean monthly max DD: 56.12** |

The 2025 control comparison:

| Candidate | Sum monthly P&L (USD) | Positive months | Entries | Mean monthly max DD (USD) |
|---|---:|---:|---:|---:|
| v2.6 control | -282.44 | 4/12 | 1,153 | 84.43 |
| v2.12 hybrid | -196.02 | 5/12 | 791 | 70.97 |
| v2.13 trend single-swing | **-80.65** | **6/12** | **598** | **56.12** |

v2.13 improved the 2025 summed monthly result by USD 201.79 versus v2.6 and USD 115.37 versus v2.12, with lower mean monthly maximum drawdown. It nevertheless remained negative. The result is evidence of better loss containment, not a profitable strategy.

### 2025 position-level audit

- 595 fully completed positions; three positions retained an open remainder.
- Completed-position outcomes: 462 wins and 133 losses.
- Position win rate: 77.65%.
- Gross wins: USD 1,141.79.
- Gross losses: USD 1,222.44.
- Profit factor: 0.934.
- Net realized P&L: -USD 80.65.
- Average winning position: approximately USD 2.47.
- Average losing position: approximately USD 9.19.

The central weakness is loss asymmetry: average losses were approximately 3.7 times average wins. The high win rate does not compensate for the loss tail.

### 2026 recent-period folds

| Month | Net P&L (USD) | Entries | Maximum drawdown (USD) |
|---|---:|---:|---:|
| Jul | +3.23 | 53 | 55.26 |
| Aug | +36.37 | 49 | 34.13 |
| Sep | +64.93 | 56 | 18.17 |
| Oct | -25.87 | 60 | 42.38 |
| **Jul–Oct total** | **+72.20** | **218** | **Mean monthly max DD: 37.49** |

November 1–9, 2026: -USD 30.31 across the two tested subperiods. The candidate reduced the loss relative to v2.6 (-USD 48.42) and v2.12 (-USD 35.64), but was still negative.

### Rejected or incomplete experiments

- **TP1 at 0.50R:** v2.7 produced +USD 119.64 over September–October 2026 versus +USD 92.75 for the v2.5/v2.6 0.25R control, but increased drawdown and reduced win rate. On v2.13, the first four 2025 months produced -USD 152.80 at 0.50R versus -USD 41.62 at the default 0.25R. Reject 0.50R.
- **Single-swing quality floor 60:** 2025 summed monthly P&L approximately -USD 91.99, worse than v2.13 default -USD 80.65. Reject; retain 55.
- **TP1 close fraction 60%:** not tested. StrategyTune rejected the attempted run before execution because the daily compute allowance had been exhausted (602/600 seconds). No result exists. Do not describe this as a completed experiment.

## Decision and next validation

v2.13 is the current research control for further Gold exit-management experiments because it contained drawdown better than the earlier candidates. It is **not approved for live use** and must not be copied into the MT5 EA as if it were proven profitable.

Next work should focus on loss-tail containment with one-variable-at-a-time tests, then validate any promising rule against an untouched period and the native MT5 implementation. A StrategyTune proxy cannot establish MT5 trailing-stop parity, broker stop-modification success, commissions, slippage, swap, or execution-ledger reconciliation.
