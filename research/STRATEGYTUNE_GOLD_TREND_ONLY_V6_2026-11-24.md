# Gold trend-only continuation research and Midas integration — 2026-11-24

Status: **research-only; native Midas option added but disabled by default**. This report records a controlled StrategyTune comparison and the narrowly scoped MQL5 port. It is not a profitability certification, broker-demo result, or live-trading approval.

## Experiment design

- Instrument/provider: IC Markets `Gold` (Gold / US Dollar).
- Timeframe: M15.
- Independent starting balance: USD 1,500 per run.
- StrategyTune risk overrides, held constant across candidates: `riskFraction=0.25` (0.25% per entry), `opportunityRiskFraction=0.10` (0.10%), and `maxPortfolioRiskPercent=2.0`.
- Candidates: StrategyTune `Midas Gold Trend-Only Research Candidate v1` v6, `Midas v2.14 Direction-Aware Dual-Lane Rank B` v2, and `Midas v2.14 Fresh-Sweep Additive Router` v3.
- Windows: independent monthly folds from June through September 2026, October 1–November 21 2026, and July–December 2025. The trend-only candidate also has a January–June 2025 half-year run.
- Partial close rows were grouped by `openingFillId` to count completed entry lots. This avoids treating each partial exit as a separate winning trade.
- The StrategyTune in-run position-attribution/close-observer diagnostics were not authoritative and were suppressed. MAE/MFE and custom position attribution are not used in the conclusions.

## Trend-only candidate results

### 2025

| Period | Completed entry lots | Wins / losses | Win rate | Profit factor | Net P&L | Platform max drawdown |
|---|---:|---:|---:|---:|---:|---:|
| Jan–Jun 2025 | 174 | 140 / 34 | 80.5% | 1.184 | +$6.89 | $10.86 |
| Jul–Dec 2025 | 199 | 152 / 47 | 76.4% | 0.828 | -$9.57 | $14.56 |
| **2025 combined** | **373** | **292 / 81** | **78.3%** | **0.971** | **-$2.68** | Not a single continuous annual run |

The candidate was not profitable across the full 2025 sample. The second half erased the first-half gain. This is a material regime-sensitivity warning, not a result to hide behind the win rate.

### 2026 monthly folds

| Period | Completed entry lots | Wins / losses | Profit factor | Net P&L | Platform max drawdown |
|---|---:|---:|---:|---:|---:|
| Jun 2026 | 6 | 4 / 2 | 0.475 | -$1.35 | $2.76 |
| Jul 2026 | 11 | 8 / 3 | 0.424 | -$2.36 | $3.68 |
| Aug 2026 | 10 | 9 / 1 | 3.246 | +$2.74 | $1.64 |
| Sep 2026 | 14 | 12 / 2 | 1.996 | +$2.48 | $1.96 |
| Oct 1–Nov 21 2026 | 31 | 28 / 3 | 2.499 | +$6.19 | $4.40 |
| **Jun–Nov 21 combined** | **72** | **61 / 11** | **1.530** | **+$7.70** | Not a single continuous six-month run |

The candidate was negative in June and July, then positive in August through November 21. The 72 completed entries are still a modest sample; the strong recent result is not proof of durable edge.

## Extended 2026 comparison: January 1–November 21

The same three candidates were also run on ten independent monthly folds (October and November 1–21 combined). Each fold used the same USD 1,500 starting balance and risk overrides. Saved session rows were grouped by `openingFillId` to compute completed-entry statistics.

| Candidate | Completed entry lots | Wins / losses | Win rate | Profit factor | Sum of monthly net P&L |
|---|---:|---:|---:|---:|---:|
| Trend-only v6 | 91 | 76 / 15 | 83.5% | 1.536 | **+$10.49** |
| Direction-Aware Rank B v2 | 347 | 272 / 75 | 78.4% | 1.007 | +$0.60 |
| Fresh-Sweep Router v3 | 197 | 152 / 45 | 77.2% | 1.062 | +$3.67 |

These are sums of ten independently reset monthly simulations, not one continuously compounded account curve. The trend-only candidate had no trades in March and only 3 entries in February and 1 in April; the lower frequency is material when interpreting its result. It led this comparison, but it remains regime-sensitive: its 2025 combined result was negative and its 2026 January, June, and July folds were negative.

## Matched candidate comparison

All values below are sums of independent monthly folds, each starting at USD 1,500. They are not compounded equity curves.

| Candidate | Jul–Dec 2025 net | Jan–Nov 21 2026 net | Interpretation |
|---|---:|---:|---|
| Trend-only v6 | -$9.57 | **+$10.49** | Best relative result in the 2026 block, but negative in 2025 |
| Direction-Aware Rank B v2 | -$20.46 | +$0.60 | More frequent trading; near-flat net result on these folds |
| Fresh-Sweep Router v3 | -$12.50 | +$3.67 | Positive 2026 block, but below trend-only |

The six-month StrategyTune runs for Direction-Aware Rank B and Fresh-Sweep exceeded the per-run 120-second deadline. They were replaced with six completed independent monthly folds for each candidate. The monthly folds are the comparison evidence.

## What was integrated into native Midas

A narrowly scoped, opt-in regime gate was added to the existing native continuation fallback:

- `InpFreshSweepTrendOnlyContinuation=false` by default.
- `InpFreshSweepTrendMinSlopeATR=0.45` by default.
- When enabled, continuation fallback requires the absolute SMA(8)-versus-SMA(21) separation to be at least 0.45 ATR, measured on completed bars using the existing ATR(14) proxy.
- Invalid slope evidence fails closed when the gate is enabled.
- The gate is only relevant when the Fresh-Sweep additive router itself is enabled; that parent router also remains disabled by default and is only consulted when both native directional setup builders are inactive.
- The MQL5 port does **not** import StrategyTune sizing, exits, or order management. Native Midas retains authority over account risk profile, small-account and Gold cash-risk limits, portfolio admission, broker margin, execution ledger, orders, protective stops, partial closes, trailing, recovery, and audit.
- No risk percentage, daily-loss limit, position cap, exit rule, or live strategy default was changed.

This is a partial port of the candidate's trend-regime eligibility rule into the existing native continuation lane, not a line-for-line clone of the StrategyTune script.

## Costs and evidence limitations

1. These StrategyTune runs use IC Markets recorded bid/ask data, but the proxy does not apply commission, slippage, or swaps. Results are not fully cost-inclusive.
2. The runs use USD 1,500 and 0.25%/0.10% simulated entry-risk overrides. They do **not** validate Midas's separate small-account KES 1,500 policy, 20% non-Gold target, KES 7.50 Gold cash-risk cap, or broker minimum-volume rejection behavior.
3. StrategyTune does not execute the native MT5 EA, Midas broker adapter, PostgreSQL margin admission, execution ledger, or MT5 stop-modification/recovery lifecycle.
4. Several runs report incomplete in-run close-observer attribution. Completed entry outcomes above were reconstructed from saved session rows grouped by `openingFillId`; custom MAE/MFE and position-attribution diagnostics remain excluded.
5. No independent locked-OOS review, native MT5 historical Strategy Tester run, broker-demo execution, or live profitability evidence has been supplied.

## Decision

The trend-only continuation gate is integrated as a **disabled research option** because it was the strongest relative candidate in the tested 2025 H2 and 2026 June–November comparison blocks. It is **not promoted to a production default**: the full 2025 combined result was negative, June–July 2026 were also negative, sample size is limited, and costs/native execution are not represented.

Next acceptance gates: run matched native MT5 Strategy Tester ablations with the gate off/on, use the exact broker-server UTC offset evidence, preserve the user's current risk profile and all admission controls, evaluate an untouched future period, then run broker-demo stop modification, ledger, margin, and restart-recovery checks. No live trading is authorized by this research.


## Locked OOS contamination disclosure — 2026-11-25

The repository's locked reservation file specifies `2026-11-13T17:18:40Z` through `2027-02-13T17:18:40Z`, maturity through `2027-02-27T17:18:40Z`, status `reserved_unscored`, and requires external freshness attestation. This report's October 1–November 21 2026 fold intersects the reserved period. Its November 13–21 segment is therefore **not an untouched holdout** and is contaminated for candidate selection, parameter tuning, and independent OOS claims. Treat the full reported result as exploratory/descriptive only; do not use the overlapping segment as validation.

No further strategy comparisons may use the reserved interval. Preserve the reservation and audit trail. A replacement holdout must be newly reserved strictly after the existing maturity end and externally freshness-attested before scoring. Do not silently reset or edit the existing reservation to make previously inspected data appear unused.
