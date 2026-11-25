# Gold M15 entry-filter ablation — 2026-11-25

Status: **research-only; no EA code, strategy defaults, or risk settings changed**.

## Test scope

- StrategyTune script: `Midas Gold v2.14 Exit Guard Research`, compiled version 4.
- Instrument/provider/timeframe: IC Markets `Gold`, M15.
- Training windows only: 2025-07-01–2025-08-01 and 2025-08-01–2025-10-01.
- Starting balance reset to USD 10,000 for each run.
- Baseline inputs were unchanged. Variants tested one input at a time: `requireVolumeConfirmation=true` (using the existing `rvolThreshold=1.5`) and `minQuality=68`.
- All session rows were grouped by `openingFillId`; partial-close rows were summed into one entry-position P&L. Open positions are excluded from closed-position win rate and net closed P&L.
- StrategyTune uses recorded bid/ask, but does not model commission, slippage, or swap. These are pre-cost research results, not native MT5 or broker-demo results.

## Position-level results

| Window | Configuration | Closed positions | Wins / losses | Win rate | Net P&L | Profit factor |
|---|---|---:|---:|---:|---:|---:|
| Jul 2025 | Baseline | 49 (1 open) | 30 / 19 | 61.22% | -$117.31 | 0.359 |
| Jul 2025 | Volume confirmation | 2 | 2 / 0 | 100.00% | +$2.99 | Undefined |
| Aug–Sep 2025 | Baseline | 96 | 76 / 20 | 79.17% | +$25.85 | 1.139 |
| Aug–Sep 2025 | Volume confirmation | 8 | 6 / 2 | 75.00% | -$2.65 | 0.868 |
| Aug–Sep 2025 | `minQuality=68` | 96 | 76 / 20 | 79.17% | +$25.85 | 1.139 |

All P&L is USD. The baseline July session had one position still open at the end; it is excluded from the 49 closed-position statistics.

## Findings

1. **The 100% July volume-filter win rate is not meaningful.** It represents only two closed positions.
2. **Volume confirmation failed the adjacent two-month fold.** It reduced entries from 96 to 8 (91.7% fewer), lowered grouped win rate from 79.17% to 75.00%, changed positive baseline P&L (+$25.85) into a loss (-$2.65), and reduced PF from 1.139 to 0.868. Do not enable it by default.
3. **The 68 quality threshold produced exactly the same position-grouped outcomes** as the baseline in Aug–Sep. The script source applies `minQuality` to the strict `chain()` candidate, while fallback entry families may bypass that gate. The unchanged result suggests this aggregate entry population is not being controlled by that threshold in this fold. This is a diagnostic finding, not proof that the input is globally inert.
4. The strategy's in-run observer reported `positionAttributionValid=false` and suppressed its custom outcome stats in these runs. This is why the conclusions above use the persisted session trade rows grouped by `openingFillId`, not the observer's row-level win counts.
5. No tested filter has demonstrated a robust, cost-inclusive improvement across both folds.

## Decision

**Reject both filter changes for promotion.** Keep `requireVolumeConfirmation=false` and the existing `minQuality=62` default. Do not alter EA behavior based on these two folds.

Next research task should be a code-level audit of entry-family attribution: identify which family opens each position, ensure every intended quality/confirmation gate is applied consistently, and make persisted `openingFillId` outcomes the sole source for candidate-level statistics. Then repeat chronological training-fold ablations with adequate sample sizes and explicit drawdown/payoff criteria. Do not use the contaminated locked OOS interval (2026-11-13–2027-02-13) for tuning or validation. No live trading is authorized by this report.


## Fibonacci-zone filter follow-up

A further Aug–Sep 2025 run enabled `requireFibonacciZone=true` with the existing 50–61.8 retracement band. Grouped persisted-session results:

| Configuration | Closed positions | Wins / losses | Win rate | Net P&L | Profit factor |
|---|---:|---:|---:|---:|---:|
| Baseline | 96 | 76 / 20 | 79.17% | +$25.85 | 1.139 |
| Fibonacci-zone required | 4 | 3 / 1 | 75.00% | +$2.54 | 1.223 |

The apparent PF increase is based on only four closed positions and is not statistically persuasive. The filter removed 95.8% of baseline positions and reduced the win rate; it does not demonstrate a reliable improvement. Keep `requireFibonacciZone=false` by default.

## Updated conclusion

The volume and Fibonacci filters are both too selective on the tested fold, with very small samples and worse grouped win rates. The quality threshold change did not alter the Aug–Sep position outcomes. No entry filter is promoted. The next useful engineering work is entry-family attribution and gate-coverage auditing, not more blind threshold sweeps.


## Active single-swing quality gate follow-up

Source inspection showed that `minQuality` gates the strict `chain()` family, while the active single-swing fallback has its own `singleSwingMinQuality` input. The Aug–Sep fold was therefore rerun with the relevant gate raised from 55 to 68:

| Configuration | Closed positions | Wins / losses | Win rate | Net P&L | Profit factor |
|---|---:|---:|---:|---:|---:|
| Baseline (`singleSwingMinQuality=55`) | 96 | 76 / 20 | 79.17% | +$25.85 | 1.139 |
| Raised gate (`singleSwingMinQuality=68`) | 86 | 67 / 19 | 77.91% | +$14.62 | 1.080 |

The stricter gate removed 10 positions but lowered win rate by 1.26 percentage points, reduced net P&L by $11.23, and reduced profit factor. Reject the 68 threshold; keep the default 55.

This confirms that the previous `minQuality=68` no-op was a wrong-gate experiment for the dominant fallback path, not evidence that all quality controls are inert. The active family-specific gate has now been tested directly and did not improve this fold.
