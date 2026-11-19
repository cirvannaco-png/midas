# Native MT5 policy test coverage

The Windows MetaEditor workflow compiles the complete Midas EA and every MQL5 test source under `development/EA/tests`.

The following deterministic suites execute as one-shot MT5 scripts without submitting broker orders:

| Suite | Coverage |
|---|---|
| AccountRiskProfilePolicy | Profile validation, hard risk ceiling, Gold cash-risk cap, KES conversion freshness |
| ConfigSyncContract | Metadata compatibility, lifecycle state and explicit activation acknowledgement |
| DecisionEngineGeometry | Entry, invalidation, protective-stop and monotonic-target geometry |
| DynamicStopEngine | BUY/SELL protection thresholds, breakeven, structural/ATR trailing, price-grid rounding and fail-closed guards |
| FreshSweepAdditiveRouter | Freshness boundary, lane priority, regime admission and abstention |
| OpposingPositionPolicy | Direction matrix, hedging permission, netting/exchange rejection |
| PositionManagementPolicy | Partial-close eligibility and trade-state transitions |

Each script writes a `failures=N` result file. The CI runner requires zero failures and a zero terminal exit code, then uploads the result files and MetaEditor logs.

## Scope boundary

These tests verify deterministic policy behavior and compile integration. They do **not** replace:

- a full-EA MT5 Strategy Tester run using broker-specific historical ticks;
- end-to-end broker order, partial fill, stop modification and rejection tests;
- restart recovery with real broker positions and ledger history;
- execution-cost stress testing or demo-forward validation.

Live trading remains blocked pending those separate acceptance gates.
