# MidasTouch2 Exit Architecture Audit

**Date:** 2026-11-09  
**Research branch:** `build/single-file-staging`  
**Scope:** StrategyTune research surrogate exit sensitivity and the actual MQL5 production position manager.  
**Production changes:** none. No risk inputs changed. No live deployment.

## Executive finding

The current research surrogate's exit structure produces a poor payoff distribution: winning full positions are too small relative to losing full positions. A 76.32% full-position win rate across four inspected Gold folds still produced negative aggregate expectancy. A delayed first partial target improved the aggregate sample, but its result was concentrated in August and failed to produce positive P&L in three of the four folds. It is not a robust candidate.

Crucially, the StrategyTune research surrogate does **not** implement the same exit architecture as the MQL5 EA. Its numerical exit experiments must not be copied into the production EA. The production manager needs its own MT5 Strategy Tester and broker-demo validation.

## 1. StrategyTune surrogate: baseline exit logic

The research harness baseline uses:

- TP1 at 0.25R; close 40% of original position size.
- On TP1, move the remaining stop to +0.10R.
- TP2 at 1.0R; close 20% of original position size.
- Trail the remaining 40% at 1.2 ATR after TP2.
- Maximum holding time: 120 bars.
- The family-specific controls are used for sweep/reclaim and continuation.

The break-even offset is not true break-even: +0.10R is a small locked gain if reached and filled.

## 2. Payoff diagnosis: continuation baseline

Saved session rows were grouped by original `openingFillId`; partial-close rows were summed into one full-position outcome.

| Metric | Four-fold aggregate |
|---|---:|
| Folds | June, July, August, October 2026 |
| Instrument / interval | Gold / M15 / IC Markets |
| Original positions | 152 |
| Winning / losing positions | 116 / 36 |
| Full-position win rate | 76.32% |
| Gross winning P&L | +$267.19 |
| Gross losing P&L | -$307.01 |
| Net P&L | -$39.82 |
| Profit factor | 0.870 |

Average winning position: approximately **+$2.30**. Average losing position: approximately **-$8.53**. With that payoff ratio, the break-even full-position win rate is approximately **78.74%**, before any additional commission or slippage not represented by this dataset. The observed 76.32% is insufficient.

This is the core issue: the system can win many positions and still lose money because the winners do not compensate for the losers.

## 3. One-factor exit experiments

All tests used the same continuation entry rules, Gold M15 data, 0.10% simulated risk per entry, six-entry daily ceiling, 2.25% run-level risk cap, and the research weekend guard. No entry-family or risk-budget changes were made. Each row below is reconstructed from saved trade records grouped by `openingFillId`.

### Four-fold comparison

| Exit configuration | Positions | Full-position WR | Net P&L | PF |
|---|---:|---:|---:|---:|
| Baseline: TP1 0.25R / 40%, BE +0.10R, trail 1.2 ATR | 152 | 76.32% | -$39.82 | 0.870 |
| TP1 delayed to 0.50R; other exits unchanged | 148 | 67.57% | +$13.34 | 1.033 |
| Runner trail widened to 1.8 ATR; other exits unchanged | 152 | 76.32% | -$40.04 | 0.870 |

### Monthly results

| Configuration | June P&L / PF | July P&L / PF | August P&L / PF | October P&L / PF |
|---|---:|---:|---:|---:|
| Baseline | -$41.19 / 0.634 | -$5.39 / 0.912 | +$8.66 / 1.124 | -$1.90 / 0.970 |
| TP1 0.50R | -$40.37 / 0.723 | -$5.23 / 0.939 | +$63.30 / 1.801 | -$4.36 / 0.955 |
| Trail 1.8 ATR | -$40.60 / 0.640 | -$3.80 / 0.938 | +$5.71 / 1.082 | -$1.35 / 0.979 |

The delayed TP1 variant's aggregate positive result depends on August. Its other three folds are negative. Its August top five winning positions contributed $49.86, or about 78.8% of that month's net gain. Removing those five wins makes the four-fold aggregate negative again. This is concentration, not reliable proof of an exit edge.

The wider 1.8 ATR trail did not improve aggregate expectancy: aggregate PF remained approximately 0.87 and net P&L was slightly worse than baseline.

### October one-factor sensitivity

| Change from baseline | October positions | Full-position WR | Net P&L | PF |
|---|---:|---:|---:|---:|
| Baseline | 35 | 77.14% | -$1.90 | 0.970 |
| TP1 delayed to 0.50R | 32 | 62.50% | -$4.36 | 0.955 |
| TP1 close fraction reduced from 40% to 20% | 35 | 77.14% | -$3.86 | 0.939 |
| TP1 stop moved to entry (0R), instead of +0.10R | 35 | 77.14% | -$13.31 | 0.788 |
| Runner trail widened to 1.8 ATR | 35 | 77.14% | -$1.35 | 0.979 |

The 0R stop experiment materially worsened P&L. Do not remove the +0.10R protection on the strength of this sample. Reducing the first partial fraction also worsened October. The 1.8 ATR trail change was too small to justify a production change.

**Interpretation:** TP1 at 0.50R is a research hypothesis only, not an approved setting. The results show an interesting payoff shift—lower win rate, larger average winners—but the cross-fold stability test failed.

## 4. Actual MQL5 production exit architecture

The production source file `MidasTouch2.mq5` has a different implementation in `CPositionManager` and `CDynamicStopEngine`.

The current configured defaults are:

- Dynamic stop enabled.
- Dynamic stop activation at +0.75R.
- Breakeven floor begins at +1.00R.
- ATR fallback trailing distance: 1.50 ATR.
- Prefer a confirmed structural swing anchor with a 0.10 ATR buffer when available.
- Partial close at +2.00R, closing 50% of the current position volume.
- Remaining position stays in the position manager's runner state and continues to receive dynamic stop management.

The dynamic stop is evaluated on ticks. It only modifies stops when the candidate is tighter, passes spread/volatility and broker stop/freeze-distance checks, and exceeds the minimum improvement threshold. Successful modifications are recorded in the SL audit and linked to execution-ledger intent/confirmation. This is materially different from the StrategyTune surrogate's 0.25R/1R staged scale-out.

### Configuration clarity issue

The `CPositionManager::Init` signature accepts `breakEvenAtR` and `trailAtrMult`, but the manager does not store or use those arguments. Its live dynamic-stop configuration is sourced from `InpDynamicStopBreakevenAtR` and `InpDynamicStopATRMult`. The older `InpBreakEvenAtR` and `InpTrailATRMult` inputs are passed to the outcome/simulation tracker as well as to the manager initializer, but they do not control the manager's active stop engine.

This creates a misleading configuration surface: changing the older inputs may change simulation/tracker calculations without changing the live manager's dynamic-stop behavior. Treat this as a code/configuration clarity defect to resolve only with a focused regression-tested patch.

The active partial-close settings `InpPartialAtR` and `InpPartialFraction` are assigned to the manager and used by `ShouldTakePartialAtR` and `PartialVolumeForPosition`.

## 5. Research telemetry correction

The StrategyTune harness is now **version 6**, compiled successfully.

A defect was found in v5's feature-mean reporting: the code reduced the emitted feature names to six but continued reading the first six slots of a 12-element feature vector. Consequently, some values labelled trend slope, MFE and MAE were mislabelled. Historical v5 feature means for those fields must not be used.

Version 6 explicitly maps feature names to their source indices: quality 0, RVOL 1, spread/ATR 2, trend slope/ATR 9, MFE in R 10, and MAE in R 11. It also calculates the runner-P&L approximation using the selected family's actual TP1/TP2 R-multiples and close fractions, rather than the generic inputs. This is telemetry-only; it does not change entry, sizing, stop or exit decisions.

## 6. Decision and next validation

1. Do not change production MQL5 exit settings based on these surrogate tests.
2. Keep the existing production risk controls and stop geometry intact.
3. Resolve the stale/ambiguous manager initializer parameters in a separate, regression-tested code change; preserve the active `InpDynamicStop*` controls.
4. Build MT5 Strategy Tester experiments that change one production exit variable at a time: partial target R, partial fraction, dynamic-stop activation R, breakeven floor R, and ATR/structural trail policy.
5. Reconstruct full-position P&L from broker deals, including commission, swap, fees, spread and slippage. Use MFE/MAE and stop-at-close snapshots to classify exit failure modes.
6. Validate on multiple untouched periods and instruments. November 2026 must remain untouched until its data window is sufficiently complete and the hypothesis is frozen.
7. Do not promote based on win rate alone. Require positive out-of-sample expectancy, profit factor above 1 after costs, controlled drawdown and robust results across folds.

**Status:** research diagnosis complete; no production EA code or risk settings changed; no live-readiness claim.
