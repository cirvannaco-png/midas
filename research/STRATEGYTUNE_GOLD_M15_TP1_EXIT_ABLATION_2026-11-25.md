# Gold M15 TP1 exit ablation — 2026-11-25

Status: **research-only; no EA inputs/defaults changed**. This experiment tests whether increasing the first partial take-profit target improves the payoff profile without simply optimizing win rate.

## Design

- StrategyTune script: `Midas Gold v2.14 Exit Guard Research` v4.
- Instrument/provider/timeframe: IC Markets `Gold`, M15.
- Training windows: 2025-07-01–2025-08-01 and 2025-08-01–2025-10-01. Both predate the repository's locked OOS reservation.
- Starting balance: USD 10,000, independently reset for each run.
- All defaults held constant except `singleSwingTP1RR`: baseline 0.25R; variants 0.35R and 0.50R. The TP1 close fraction remains 40%; other targets, stops, trailing, risk, and entry logic are unchanged.
- Risk defaults: 0.25% strict-entry risk, 0.10% opportunity risk, 2.25% portfolio cap.
- Outcomes were grouped by `openingFillId`; partial exits are combined into one entry-position P&L. Positions still open at period end are excluded from win-rate and closed-position P&L.
- StrategyTune uses recorded bid/ask but does not model commission, slippage, or swaps. This is not a native MT5 EA or broker-demo test.

## July 2025 fold

| TP1 target | Closed positions | Wins / losses | Win rate | Net P&L | Profit factor | Avg win | Avg loss |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0.25R baseline | 49 | 30 / 19 | 61.22% | -$117.31 | 0.359 | $2.19 | $9.64 |
| 0.35R | 50 | 29 / 21 | 58.00% | -$116.11 | 0.428 | $2.99 | $9.66 |
| 0.50R | 50 | 28 / 22 | 56.00% | -$51.30 | 0.749 | $5.47 | $9.29 |

The 0.50R variant substantially improved this losing month's net result and profit factor, but reduced win rate and remained unprofitable. The 0.35R variant made almost no net improvement.

## August–September 2025 fold

| TP1 target | Closed positions | Wins / losses | Win rate | Net P&L | Profit factor | Avg win | Avg loss |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0.25R baseline | 96 | 76 / 20 | 79.17% | +$25.85 | 1.139 | $2.78 | $9.27 |
| 0.35R | 96 | 71 / 25 | 73.96% | +$28.08 | 1.119 | $3.71 | $9.41 |
| 0.50R | 95 | 61 / 34 | 64.21% | -$17.96 | 0.944 | $4.97 | $9.44 |

The 0.35R variant added only $2.23 while reducing win rate by 5.21 percentage points and slightly reducing profit factor. The 0.50R variant turned a profitable baseline fold into a loss and reduced win rate by nearly 15 percentage points.

## Continuous July–September diagnostic

Separate continuous three-month runs were also completed, with one USD 10,000 starting balance per run:
- Baseline 0.25R: 146 closed positions, 107 wins / 39 losses, 73.29% win rate, -$88.92 net, profit factor 0.756.
- Variant 0.50R: 146 closed positions, 90 wins / 56 losses, 61.64% win rate, -$64.82 net, profit factor 0.876.

The 0.50R target reduced the loss by $24.10 and improved profit factor, but lowered position win rate by 11.65 percentage points and remained unprofitable. Its performance also reversed between the July and August–September folds. This is regime dependence, not a robust improvement. For reference, adding the independently reset monthly-fold P&Ls gives -$91.46 for baseline and -$69.26 for 0.50R; those sums are not the same as the continuous three-month runs. The 0.35R monthly-fold P&L sum was -$88.03, only $3.43 better than baseline, with lower win rate and no demonstrated robust profit-factor gain.

## Later fold

A 0.50R run for 2025-10-01–2026-01-01 was submitted but failed with `job exceeded deadline 120000ms`. It produced no valid result or saved session and is excluded from all conclusions. The pre-existing 0.25R baseline for this window is positive (+$13.28 platform P&L), so the proposed 0.50R variant has not passed this later-fold check.

## Decision

**Do not integrate 0.35R or 0.50R as a new EA default.** The higher target improves payoff in one fold but reduces hit rate, fails in the adjacent fold, and remains negative across the combined training sample. The 0.35R change is too small to justify its win-rate deterioration.

Keep the native TP1 default unchanged. A candidate exit change must improve net expectancy, profit factor, drawdown, and position-level win rate across multiple chronological folds, then pass cost-inclusive MT5 Strategy Tester and broker-demo validation. Never tune against the reserved 2026-11-13–2027-02-13 locked OOS interval; that interval has already been exposed by earlier research and is contaminated for candidate selection and independent OOS claims. Any replacement holdout must be newly reserved after the existing maturity end and externally freshness-attested.
