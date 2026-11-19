# Midas continuation router: matched native-MT5 validation plan

Status: implementation remains opt-in; matched native Strategy Tester evidence has not yet been supplied. This document defines the reproducible test rather than treating StrategyTune proxy results as live-EA evidence.

## Integration boundary

The Trend-Continuation Frequency Lab's native continuation chain is the closed-bar EMA20/EMA50 alignment, body ratio >= 0.35, signal range/ATR >= 0.45, EMA pullback touch within eight bars, break of the recent bars 2–5 level, and continuation quality floor 48. The native CFreshSweepAdditiveRouter::BuildContinuation implements that chain in MQL5.

The router is not a new execution or risk engine. It is consulted only when both existing native directional setup builders have returned inactive. The selected setup then re-enters the existing setup validation, confidence/decision policy, emergency/daily-loss/session/news controls, ledger admission, small-account and Gold cash-loss caps, native lot sizing, portfolio-risk admission, broker order manager, position manager, and execution audit/persistence path. Stop calculation still uses the existing spread floor and native invalidation/ATR stop geometry; CRiskEngine remains authoritative. Existing position management continues to own partial exits, trailing, and stop modification. Recovery still runs through the existing recovery engine.

The continuation setup also calls the scoring engine's configured mandatory RVOL/Fibonacci checks. If those required checks cannot be evaluated, the candidate fails closed. Existing risk and entry-quality settings are not disabled to increase the candidate's trade count.

Production defaults remain unchanged:
- InpEnableFreshSweepAdditiveRouter=false.
- InpFreshSweepEnableSingleSwingFallback=false.
- The candidate MT5 .set file may set only InpEnableFreshSweepAdditiveRouter=true.
- Both presets must leave single-swing fallback disabled.
- No risk, sizing, drawdown, daily loss, open-position, stop, partial-close, trailing, execution, or recovery input may differ between the pair.

## Native matched pair

Use one MT5 terminal build, one EA source commit/build, one broker's exact symbol specification, one immutable real-tick dataset, identical date range and warm-up, symbol/timeframe, starting equity, account currency, leverage, margin mode, fill policy, actual commission schedule and all non-router inputs.

Prepare two .set files:
1. baseline.set: router disabled.
2. continuation.set: same exact values as baseline except router enabled.

Both keep InpFreshSweepEnableSingleSwingFallback=false. The matcher in tools/compare_mt5_continuation_runs.py rejects any other .set difference, mismatched run context, reused run IDs/artifacts, hash mismatch, missing commission/swap/fee columns, and missing strategy attribution. The report only scores development entries before the declared locked-OOS boundary; OOS outcomes stay withheld.

Run the complete EA in MT5 Strategy Tester for both presets using Every tick based on real ticks when the chosen broker's genuine tick history is available. Export and retain for both variants:
- actual .set file;
- native HTML tester report including balance/equity graph and tick-level equity drawdown;
- complete tester deal CSV with profit, commission, swap, fee, partial-close rows, risk cash, requested/actual fill price and slippage evidence, strategy attribution, and position identifier;
- open-position ID CSV (header-only when no position remains open);
- tester metadata from MidasTesterMeta_*.json, including point, tick size, tick value, cash-per-point per lot, account currency, leverage, broker/server, terminal build, fill mode and spread observations;
- immutable tick-data/archive file and SHA-256.

Use the exact cash-per-point-per-lot value from the tester metadata/symbol specification in the cost tool. Never substitute a generic Gold pip value. For real ticks the observed baseline spread is already in fills; only incremental spread widening is added by the stress analyzer.

## Cost and adverse-condition matrix

Run tools/cost_stress_monte_carlo.py independently on both deal exports with identical parameters. Standard incremental grid:
- full-spread widening: 0, 2, 5 points;
- additional slippage: 0, 1, 2 points per executed deal-side fill;
- additional commission: zero and any broker-sourced surcharges that are actually applicable.

Actual commission/swap/fee remain in each position's base P&L. Additional commission sensitivity is a surcharge per 1.0 lot per deal-side fill. Only use values backed by the selected broker's current published contract/tariff or measured commission records. Do not guess an amount.

Include chronological trend, range/chop, transition, high/low-volatility and major-session periods in the native test corpus. Inspect rollover/illiquid periods and recorded spread spikes. Where the source history lacks gaps or stress events, label the limitation; do not claim a gap test was performed. Retain all walk-forward fold outputs and 10,000-run sequence-shuffle/bootstrap drawdown diagnostics at fixed seed. These are settlement diagnostics; native MT5 tick-level equity drawdown is still mandatory.

## Whole-EA test scope

The existing Windows mt5-compile.yml job compiles the consolidated EA and runs deterministic no-order native policy suites for account risk profiles, config contract, decision geometry, dynamic stops, Fresh-Sweep router policy, opposing exposure and position-management policy. The Python test suites cover whole-position broker-deal accounting, partial-close reconstruction, cost stress and the backend's durable execution-recovery journal.

These are necessary engineering tests, not a substitute for a native Strategy Tester run or broker demo. In a demo environment, separately fault-inject ambiguous submit timeouts, partial fills followed by cancellation/late fill, rejected/invalid stop amendments, terminal restart with open positions, duplicate/replayed deal events, and ledger reconciliation. Verify no duplicate order is sent, no unknown exposure is silently resumed, the original protective stop is not loosened, every partial exit is reconciled by position/deal identity, and the risk gate stays closed until authoritative broker state is restored.

## Comparison and promotion gates

Run the comparator after exporting both real MT5 runs:

    PYTHONPATH=backend/source python -m tools.compare_mt5_continuation_runs --manifest artifacts/mt5/continuation-pair/manifest.json --output artifacts/mt5/continuation-pair/comparison.json

Compare completed-position expectancy, profit factor, payoff asymmetry and realized R, maximum closed-position drawdown, loss streak, strategy attribution, open/censored counts, and native equity drawdown for baseline and continuation. A candidate is not useful merely because it trades more or has a higher win rate.

Do not promote based on a high win rate, research proxy, single window, or compile pass. Require cost-complete positive expectancy, more than one market regime, independent locked-OOS evaluation with sufficient closed positions, acceptable tick-level drawdown, no partial-close/accounting mismatch, successful stop and recovery tests, and a broker-demo forward run. Keep both registered locked-OOS intervals untouched unless their exact entry-time provenance has been independently verified. In particular, any research segment spanning November 13, 2026 after 17:18:40 UTC must be checked trade-by-trade against the later reservation before it can be called fresh OOS.
