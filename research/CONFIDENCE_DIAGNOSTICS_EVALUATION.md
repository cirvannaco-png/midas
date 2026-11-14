# Confidence diagnostics: locked out-of-sample evaluation

## Purpose and boundary

This protocol tests whether shadow env_exec_confidence adds out-of-sample ranking information beyond confidence_at_signal for complete decision-level outcomes. It evaluates the telemetry introduced in Midas PR #13. It does not test a StrategyTune proxy or claim that the compiled MT5 EA is profitable.

env_exec_confidence is a heuristic derived from raw confidence, environment suitability, execution suitability and contradiction penalty. It is **not a probability**. The evaluator reports Spearman rank correlation and winner-versus-loser AUC, not Brier score or calibrated win probability.

The diagnostic remains shadow-only. No result authorizes changes to entry admission, weights, thresholds, position sizing, exits or live-trading status. The evaluator cannot write to the EA or its configuration.

## Required evidence

Create an immutable manifest.json and outcomes.csv from the same MT5 Strategy Tester build and data run. Record EA source SHA/build, terminal build, symbol, timeframe, provider, test period, market-data SHA-256, spread/commission/slippage/fill models, initial balance and currency, strategy/model/weight/calibration/feature/environment schema versions, training end, holdout start and evaluation cutoff.

Do not mix Strategy Tester and broker-demo data, symbols, builds, model versions or market-data versions in one manifest. Evaluate each homogeneous cohort separately. market_data_sha256 identifies the source tick-data artifact; the evaluator computes outcomes_csv_sha256 over the exact CSV bytes.

## Observation unit and CSV

Use exactly **one row per complete decision-level position outcome**, after aggregating all partial closes/fills for that decision and accounting for known broker cashflows in realized R. Do not count individual deal rows as independent trades. A decision ID must occur once.

Required CSV header:

    decision_id,position_id,signal_time,outcome_time,outcome_status,filled,outcome_history_complete,cashflows_known,confidence_at_signal,env_exec_confidence,realized_r

outcome_status must be win, loss, scratch, no_fill, ambiguous or pending. Boolean fields must be true/false. Flatten env_exec_confidence from environment.confidence_diagnostics.env_exec_confidence in the outcome payload. Both confidence values must be numeric in the EA's 0–100 range. realized_r is R from the EA's cumulative realizedPnL divided by the position's risk-money denominator. In this tracker, realizedPnL accumulates broker deal PnL plus commission, swap and fee cashflows; spread/slippage affect executable fill/exit prices and are also reported as separate diagnostics. Do not subtract the diagnostic spread/slippage estimates a second time. Wins are positive, losses negative, scratches exactly zero. Timestamps must include an explicit timezone, preferably UTC Z.

No-fill, ambiguous, pending, unfilled, incomplete-history, unknown-cashflow and unresolved-at-cutoff outcomes are excluded and counted. Missing fields/columns, duplicate decisions, invalid timestamps, inconsistent status/R values, or out-of-range scores reject the dataset. No silent source-data repair is performed.

## Locked chronology and metrics

The manifest must satisfy:

    period_start <= train_end < holdout_start <= evaluation_cutoff

Only rows with signal time on/after holdout start and on/before period end enter the locked holdout. Pre-holdout rows are excluded; no model is trained or tuned on the holdout.

For each score the report includes completed positions, winners, losers, scratches, win rate, mean realized R, Spearman correlation with realized R, win/loss AUC, and mean R in top and bottom score quartiles. Scratches remain in expectancy and quartile analysis but are excluded from binary AUC.

A paired bootstrap resamples identical position rows for both scores and estimates a 95% interval for AUC(diagnostic) minus AUC(raw). Defaults require 100 holdout positions, at least 30 winners and 30 losers, and 1,000 requested bootstrap replicates; at least half must be valid.

## Verdicts

- INSUFFICIENT_EVIDENCE: sample floors or valid bootstrap support are not met.
- INCREMENTAL_PREDICTIVE_SIGNAL: all evidence floors are met, the paired AUC-delta 95% interval is above zero, and the diagnostic improves point-estimate AUC and Spearman correlation.
- NO_DEMONSTRATED_INCREMENTAL_VALUE: evidence is sufficient but the incremental criteria are not met.

Even a positive verdict is only ranking association on this holdout. It does not prove profitability, causality, broker execution quality or improved P&L from gating entries.

## Run

From the repository root:

    python -m research.confidence_diagnostics.evaluate --manifest path/to/manifest.json --outcomes path/to/outcomes.csv

Exit codes: 0 complete evaluation, 1 insufficient evidence, 2 rejected dataset. Preserve manifest, CSV, report and EA/tester artifacts together. Any later model or score change requires a new chronological holdout and source/version identity.
