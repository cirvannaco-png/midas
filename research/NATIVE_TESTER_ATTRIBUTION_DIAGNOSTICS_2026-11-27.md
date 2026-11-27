# Native MT5 Tester Attribution Diagnostics — 2026-11-27

## Status

**Research telemetry and analysis tooling only.** No strategy selection, order admission, position sizing, stops, targets, trailing logic, partial-close logic, recovery, or live execution policy is changed.

The failed FX prototype remains rejected. This pipeline analyzes the canonical production EA's native MT5 Strategy Tester evidence.

## What is captured

The native tester deal export now carries, per deal:

- Stable MT5 position identifier, deal/order IDs, broker-server timestamp with explicit UTC offset, symbol, entry type and volume.
- Realized deal profit, signed commission, swap and fee.
- Initial stop price, initial stop distance in points and initial position risk cash.
- Decision ID, selected strategy, regime, position direction and entry session.
- MT5 deal reason (for example stop-loss, take-profit, expert, client).
- Requested market-order price, signed slippage points, adverse slippage cash and an explicit known/unknown flag.
- Spread points observed in the deal callback and an explicit observation flag.

The exporter continues to validate complete broker history, write the open-position list and metadata, and mark the export incomplete if any required artifact or history row is missing.

The outcome log is versioned and isolated per tester run:

- `MedisTouch_Outcomes_v3_<symbol>_<run-id>_<tick-count>.csv`

It includes stable `DecisionID`, `Session` and `RunID` columns appended after the previous schema, preserving all earlier column positions. It also contains direction, strategy, regime, exit outcome, realized R, MFE_R, MAE_R, bars held, TP1/TP2 hits, break-even and partial-close state. The analyzer verifies that the outcome RunID matches the prefix of the deal-export metadata run ID. A unique file per tester run prevents decision IDs from colliding when several test reports for the same symbol are compared.

## Session and strategy labels

The deal export uses the EA enum labels:

- Sessions: `SESSION_DEAD`, `SESSION_TOKYO`, `SESSION_LONDON`, `SESSION_NEWYORK`, `SESSION_LONDON_NY_OVERLAP`.
- Strategy families: `STRATEGY_SMC`, `STRATEGY_MOMENTUM_BREAKOUT`, `STRATEGY_MEAN_REVERSION`, `STRATEGY_KEY_LEVEL`.
- Fresh-sweep continuation and single-swing strategies remain separate additional categories; they are not silently folded into SMC.

The outcome log uses the existing display labels (`SMC`, `MomentumBreakout`, `MeanReversion`, `KeyLevel`, etc.) and the enum session labels. Decision outcomes are keyed by DecisionID and reported separately from broker-position metrics; one decision may create multiple execution legs, so its excursion statistics must not be copied onto each position and counted multiple times.

**Tester timezone safeguard:** MT5 Strategy Tester time is simulated broker-server time; `TimeGMT()` must not be assumed to be true UTC inside the tester. The production session filter now uses `TimeCurrent() - InpTesterServerUtcOffsetMinutes` in tester mode, while live mode continues to use `TimeGMT()`. If the tester offset is absent or invalid, the classifier returns `SESSION_UNKNOWN`; the session gate blocks unknown sessions when enabled, and the attribution report keeps them separate rather than assigning them to London/New York.

## Cost accounting rules

- Net position P&L is the sum of deal profit + signed commission + signed swap + signed broker fee. These cashflows are counted once.
- Adverse slippage cash is included only when every deal in a position has valid requested-price provenance. Unknown slippage remains unknown, never zero.
- The observed spread at the deal callback is an estimate of the spread at execution time, not a substitute for the exact tick-side fill. The analyzer estimates the embedded spread component using half the observed spread per deal-side fill and the export's cash-per-point-per-lot metadata. This is descriptive only; it is not deducted again from realized P&L.
- Actual tester fills already embed baseline bid/ask spread. Do not subtract baseline spread a second time. Use `backend/source/tools/cost_stress_monte_carlo.py` to stress only incremental spread widening, additional slippage and additional commission, using the exact symbol's cash-per-point contract value.
- The export's average/max spread metadata is run-level context. Per-deal callback spread is more granular but remains an observed estimate.

## Position and decision diagnostics

`backend/source/tools/analyze_native_tester_attribution.py`:

- Reconstructs completed positions using the existing `position_ledger_metrics.py` ledger; partial exits remain one position.
- Excludes still-open positions, incomplete volume paths, missing deal cashflow components and netting reversals.
- Fails closed on inconsistent direction, session or initial-stop labels.
- Reports expectancy, profit factor, wins/losses/flats and realized R by symbol and direction.
- Separates SMC, momentum-breakout, mean-reversion, key-level and fresh-sweep strategy families.
- Reports symbol × strategy × direction × session and symbol × strategy × regime × direction × session cohorts.
- Breaks out realized commission, swap, fee and known adverse slippage, plus estimated embedded spread coverage.
- Uses the outcome file for MFE_R, MAE_R, realized R, bars held, TP/BE/partial state and exit outcome.
- Flags a **possible premature-exit candidate** only when a non-SL/non-TP decision exit had MFE_R >= 1.0 and realized R <= 0.25. This is a diagnostic screen, not proof that the exit was avoidable.
- Reports initial stop geometry and stop-loss exit reasons so stop placement can be examined against adverse excursion. Closed-position drawdown is not tick-level equity drawdown.

No strategy family is automatically promoted. A cohort with fewer than 30 completed positions is marked insufficient; 30–99 is exploratory. These are review labels, not statistical certification.

## Running a native test

Run the EA in the Windows MetaTrader 5 Strategy Tester (or a Windows MT5 VPS). Android/Termux alone cannot execute the native MetaEditor/Strategy Tester workflow.

1. Use the exact intended production EA revision and freeze the `.set` inputs, symbol, timeframe, broker data source, account currency, leverage, commission and test interval.
2. Set `InpTesterExportRunId` to a unique readable run label using only letters, numbers, underscores or hyphens. The outcome file records this base RunID; the deal exporter adds its own unique suffix.
3. Set `InpTesterServerUtcOffsetMinutes` to the verified historical broker-server UTC offset for that test interval. The default sentinel intentionally disables evidence export. Split the test at broker timezone/DST offset changes.
4. Run the test with real ticks where available. Do not use the locked OOS windows for diagnostic tuning.
5. Retrieve the three exporter artifacts from MT5 Common Files:
   - `MidasTesterDeals_<run>.csv`
   - `MidasTesterOpen_<run>.csv`
   - `MidasTesterMeta_<run>.json`
6. Retrieve the matching `MedisTouch_Outcomes_v3_<symbol>_<run-id>_<tick-count>.csv` from the terminal's `MQL5/Files` directory. Use the file created by the same tester run.
7. Keep the `.set` file and MT5 Strategy Tester HTML report with the artifacts. They establish the test context; the CSVs alone do not establish broker/data provenance.

Run from the repository root:

```bash
python backend/source/tools/analyze_native_tester_attribution.py \
  --deals /path/to/MidasTesterDeals_<run>.csv \
  --open-positions /path/to/MidasTesterOpen_<run>.csv \
  --metadata /path/to/MidasTesterMeta_<run>.json \
  --outcomes /path/to/MedisTouch_Outcomes_v3_<symbol>_<run-id>_<tick-count>.csv \
  --output /path/to/native-attribution-report.json
```

The analyzer requires a complete export manifest, balanced history counts, explicit broker timezone provenance and matching outcome lineage. It also enforces the repository's registered locked-OOS entry reservations.

For additional cost robustness, run the existing cost-stress tool against the same deals/open-position CSVs, with broker-verified point value and predeclared stress assumptions:

```bash
python backend/source/tools/cost_stress_monte_carlo.py \
  --deals /path/to/MidasTesterDeals_<run>.csv \
  --open-positions /path/to/MidasTesterOpen_<run>.csv \
  --point-value-per-lot <verified-account-currency-cash-per-point-per-lot> \
  --start <inclusive-timezone-aware-start> \
  --end <exclusive-timezone-aware-end> \
  --output /path/to/native-cost-stress.json
```

## Remaining evidence requirement

The code and analysis pipeline are prepared, but no native tester CSVs or HTML reports were supplied in this work session. Therefore **no production-EA expectancy, profit factor, session ranking, or stop/exit conclusion is claimed yet**. The next factual step is to run the production EA in native MT5 and provide the matching four CSV/JSON artifacts plus the tester report and `.set` file.

The pipeline must then be checked for attribution coverage, history reconciliation, spread/slippage coverage, commission completeness and enough completed positions before any family is shortlisted for further research.
