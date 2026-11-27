# Midas cross-market and Gold exit research — 2026-11-27

Status: **research only; no native EA defaults, risk settings, or production behavior changed.** All tests were StrategyTune simulations, not native MT5 execution.

## Executive decision

Do not promote any tested StrategyTune candidate as a cross-market strategy. Across a matched 30-day window, the Gold Trend-Only candidate, Fresh-Sweep Additive Router, and Direction-Aware Dual-Lane Rank B all lost money on Gold, EUR/USD, and GBP/USD.

The Gold Trend-Only candidate was the least bad of the three on the matched window, but it was still negative on every instrument tested. Two subsequent Gold exit ablations made results materially worse. The present evidence points to a payoff-distribution problem, not a lack of headline win rate: winning positions are too small relative to full-stop losses.

No strategy or exit change is approved for production.

## Matched cross-market candidate comparison

### Experiment design

- Window: 2025-12-13 through 2026-01-13 (IC Markets local data range; M15).
- Instruments: Gold, EURUSD, GBPUSD.
- Starting balance: USD 10,000 independently for every run.
- Inputs held constant where available: `maxPortfolioRiskPercent=2.0`, `maxConcurrentLots=2`; other inputs remained at each candidate's saved defaults.
- Candidate defaults include 0.25% standard entry risk and 0.10% opportunity risk.
- Candidates:
  - `Midas Gold Trend-Only Research Candidate v1`, version 6, StrategyTune script `h345lkflaiy1h993tqu2wjjr`.
  - `Midas v2.14 Fresh-Sweep Additive Router`, version 3, StrategyTune script `zc2suyod4q34rxrgswjuk9wt`.
  - `Midas v2.14 Direction-Aware Dual-Lane Rank B`, version 2, StrategyTune script `z46l7w15zi48s1fc40hiyz1u`.
- Results are account-currency USD. StrategyTune uses recorded bid/ask but this proxy does not fully model broker commission, slippage, or swap.
- These are exploratory historical folds, not locked-OOS evidence. The reserved 2026-11-13–2027-02-13 interval was not used.

### Results

| Candidate | Instrument | Closed rows | Platform win rate | Net P&L | Max drawdown |
|---|---|---:|---:|---:|---:|
| Trend-Only v6 | Gold | 86 | 87.2% | -$20.45 | $37.22 |
| Trend-Only v6 | EURUSD | 87 | 89.7% | -$24.34 | $55.79 |
| Trend-Only v6 | GBPUSD | 102 | 87.3% | -$33.18 | $71.79 |
| Fresh-Sweep v3 | Gold | 153 | 88.9% | -$24.44 | $60.95 |
| Fresh-Sweep v3 | EURUSD | 125 | 88.8% | -$44.80 | $67.61 |
| Fresh-Sweep v3 | GBPUSD | 159 | 85.5% | -$48.19 | $87.46 |
| Direction-Aware Rank B v2 | Gold | 169 | 87.0% | -$48.79 | $91.90 |
| Direction-Aware Rank B v2 | EURUSD | 141 | 87.9% | -$45.75 | $82.27 |
| Direction-Aware Rank B v2 | GBPUSD | 149 | 85.2% | -$46.74 | $65.09 |

The platform closed-row count is not the number of independent entry positions: partial exits create multiple rows for one opening fill. The platform win rate is therefore not a whole-position win rate. It must not be used as the strategy's headline accuracy without position-level reconciliation.

### Matched run IDs

| Candidate | Gold | EURUSD | GBPUSD |
|---|---|---|---|
| Trend-Only v6 | `2d638743-051a-4501-bbf3-654b1e4a1150` | `405aaa6d-4a45-4ef2-abd8-9f764961cc47` | `712cd50a-bbcb-41bb-b973-34585cf49f38` |
| Fresh-Sweep v3 | `10e8b9f7-dbf6-42a3-a1c3-6ad537269e4f` | `decb0950-3dd2-4ac7-9206-daf02cccf7c4` | `044f35be-c105-4bf3-bdd2-2868c4b8f4b0` |
| Direction-Aware Rank B v2 | `a2d7e38a-6dd4-4867-acbb-3f04799be29d` | `a5f56099-0880-4659-82bd-0994f1966143` | `530d48d2-3573-4116-8475-818ba4339faf` |

All nine matched runs were repeated with saved sessions. Their authoritative whole-position outcomes below group partial close rows by `openingFillId`; the open GBPUSD remainder in the Direction-Aware session is excluded from completed-position metrics.

### Authoritative whole-position results

| Candidate | Instrument | Completed entries | Wins / losses | Entry win rate | Profit factor | Net P&L | Avg win | Avg loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Trend-Only v6 | Gold | 45 | 34 / 11 | 75.6% | 0.804 | -$20.45 | $2.47 | $9.50 |
| Trend-Only v6 | EURUSD | 47 | 38 / 9 | 80.9% | 0.722 | -$24.34 | $1.67 | $9.74 |
| Trend-Only v6 | GBPUSD | 54 | 41 / 13 | 75.9% | 0.722 | -$33.18 | $2.10 | $9.19 |
| Fresh-Sweep v3 | Gold | 80 | 63 / 17 | 78.8% | 0.850 | -$24.44 | $2.21 | $9.61 |
| Fresh-Sweep v3 | EURUSD | 68 | 54 / 14 | 79.4% | 0.670 | -$44.80 | $1.69 | $9.70 |
| Fresh-Sweep v3 | GBPUSD | 84 | 61 / 23 | 72.6% | 0.752 | -$48.19 | $2.40 | $8.46 |
| Direction-Aware Rank B v2 | Gold | 89 | 67 / 22 | 75.3% | 0.770 | -$48.79 | $2.44 | $9.65 |
| Direction-Aware Rank B v2 | EURUSD | 76 | 60 / 16 | 78.9% | 0.705 | -$45.75 | $1.82 | $9.69 |
| Direction-Aware Rank B v2 | GBPUSD | 79 | 57 / 22 | 72.2% | 0.748 | -$46.74 | $2.44 | $8.45 |

All nine candidates have position-level profit factor below 1 and negative net P&L. The best observed PF is Fresh-Sweep on Gold at 0.850, which is still unprofitable. This confirms that the row-level win-rate inflation is not the only issue: the completed positions themselves have negative expectancy in this fold.

Saved session records for the matched cross-market runs:
- Trend-Only v6: Gold `fnszg8cs3ar23r4h6ol9eka2`; EURUSD `bpwu36rwklmbunj4i0hwlxfy`; GBPUSD `zlk5kubbnfmlhtzgqxl7m38n`.
- Fresh-Sweep v3: Gold `nblbrhpew2w0b7pmeomh7v93`; EURUSD `yufyecufh8xwkkblzg5x3y96`; GBPUSD `j0mzchwgq4wvopju3zni13jl`.
- Direction-Aware Rank B v2: Gold `ehkjw18klu3m1mt5ofluxl2x`; EURUSD `ixlnk90xblsegofr3sr95mdk`; GBPUSD `xl7n1fzl8i6xowknxs79bym5`. The GBPUSD session ended with one open residual row; it is not counted as a completed position.

## Gold whole-position reconciliation and exit ablation

Saved sessions were used for all nine matched candidate/instrument combinations so partial close rows could be grouped by `openingFillId` and the cross-market win-rate/PF comparisons could be calculated at the completed-position level.

### Baseline fold: 2025-12-13 through 2026-01-13

- Engine closed rows: 86 (75 winning rows, 11 losing rows), giving an apparent row-level win rate of 87.2%.
- Actual completed opening positions after grouping partial exits: 45.
- Whole-position outcomes: 34 wins, 11 losses; 75.6% win rate.
- Gross profit: USD 84.08.
- Gross loss: USD 104.53.
- Profit factor: 0.804.
- Average winning position: USD 2.47.
- Average losing position: USD 9.50.
- Net P&L: -USD 20.45; max drawdown: USD 37.22.

The high row-level win rate masks an asymmetric payoff distribution. Average losses were approximately 3.8 times average wins. This is a more actionable weakness than attempting to push the displayed win rate higher.

Position-level side split for this fold:
- Long: 31 entries, 24 wins / 7 losses, -USD 5.17 net.
- Short: 14 entries, 10 wins / 4 losses, -USD 15.28 net.

Neither side was profitable. This is not evidence to disable shorts; the sample is small and the loss may be regime-specific.

### Exit ablations: same fold, same entries/risk

Only the continuation exit inputs changed; entry logic and risk settings remained fixed.

| Variant | TP1 | TP2 | TP1 close | TP2 close | Trail ATR | Entries | Whole-position win rate | PF | Net P&L |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Baseline | 0.25R | 1.0R | 40% | 20% | 1.2 | 45 | 75.6% | 0.804 | -$20.45 |
| Patient exit | 0.50R | 1.5R | 25% | 25% | 1.2 | 42 | 57.1% | 0.555 | -$70.42 |
| Runner-first | 0.50R | 2.0R | 20% | 20% | 1.5 | 42 | 57.1% | 0.578 | -$66.76 |

The two exit variants were rejected.

### Follow-on fold: 2026-01-13 through 2026-02-13

| Variant | Entries | Whole-position win rate | PF | Net P&L | Max drawdown |
|---|---:|---:|---:|---:|---:|
| Baseline | 49 | 79.6% | 0.831 | -$17.42 | $64.84 |
| Patient exit | 47 | 63.8% | 0.674 | -$51.66 | $99.99 |

The patient exit variant failed again on the next chronological fold. This rejects the tested exit adjustment more strongly than the first fold alone.

Saved session records:
- First-fold baseline: `vgw4wwo5mqvyc6vkasuwxp75`.
- First-fold patient exit: `pk8u2ycirhzmw0do6s8yfksh`.
- First-fold runner-first: `w53kfvatmmetsyirsvy1uwns`.
- Follow-on baseline: `uwhsjwexq7hnrnz5a7eg5uou`.
- Follow-on patient exit: `l3ggdvcbfo6q0m04vrcxgu4t`.

Whole-position metrics above were calculated by summing each position's partial-close P&L by `openingFillId`. The close rows were available from saved sessions; the in-run close observer was not treated as authoritative.

## Diagnostic hypotheses — not approved filters

- Quality-score buckets were non-monotonic in the first Gold fold. For example, the 80–89 bucket was net positive while the 90–100 bucket was net negative. A simple higher quality threshold is not supported by this sample.
- The first-fold UTC hour breakdown showed weakness around 12:00–15:59, but this is a small, post-hoc sample. No session restriction is approved.
- Both long and short positions lost money in the first fold. Do not disable either direction on this evidence.
- The first-fold exit variants increased average winning position size but also reduced whole-position win rate and profit factor. Simply delaying partial profit-taking is not a demonstrated fix.

These are hypotheses for preregistered chronological tests only. They must not be turned into production defaults from this evidence.

## Decisions and next work

1. **Reject all three StrategyTune candidates for cross-market promotion.**
2. **Reject both tested Gold exit variants.** Keep the native MQL5 exit policy unchanged.
3. Do not change risk fraction, position sizing, Gold KES cash-risk cap, daily loss limit, concurrency, stop policy, or manual-trading controls.
4. Improve research reporting so every candidate's headline win rate is calculated from completed positions grouped by `openingFillId`, not raw partial-close rows. Reconcile summed realized P&L to engine closed P&L and reject incomplete pagination.
5. Next research should isolate entry-quality/market-regime hypotheses with preregistered folds and saved sessions, not continue broad parameter searches. Use instrument-specific candidates for EURUSD and GBPUSD rather than assuming the Gold model transfers.
6. Require multiple chronological folds, cost-inclusive assumptions, and positive net expectancy/PF with controlled drawdown before considering native MQL5 changes.
7. Native MT5 Strategy Tester with real ticks, the selected broker's commission/swap/slippage, small-account KES 1,500 sizing, minimum-volume rejection, margin admission, partial-close/reversal reconstruction, stop modification, and restart recovery remain separate acceptance gates.

No live trading is authorized by this research. The canonical EA source and production defaults were not changed.
