# StrategyTune OOS Research — 2026-11-09

## Purpose and boundary

This report records five consecutive out-of-sample monthly research runs of the saved StrategyTune proxy script used for Midas Touch 2 strategy diagnostics.

These runs are **not MetaTrader 5 Strategy Tester runs** and do not execute the native MQL5 EA or its `CTesterDealExport` implementation. They therefore cannot validate PR #8's native deal export, requested-price semantics, slippage calculations, or PR #9's MT5 `DEAL_ENTRY_INOUT` handling. They are strategy-behavior evidence for the StrategyTune proxy only.

## Reproducibility

- Strategy: `MT2 False-Positive Attribution Lab v1.1 — Reconciled`
- StrategyTune script ID: `a15gl2vswagiiobrul4z58uc`
- Compiled version: `9`
- Instrument/provider: `Gold` / IC Markets (`icmarkets`)
- Timeframe: M15
- Starting balance: USD 10,000 per independent monthly run
- Periods: 2026-06-01 through 2026-11-01, split into five non-overlapping calendar months; end timestamps are exclusive
- Defaults retained: strict risk fraction 0.25, fallback opportunity risk fraction 0.10, max portfolio risk 2.25%, maximum six entries/day, maximum nine concurrent lots
- Minimum daily entries: three is a diagnostic target only. The script explicitly does not force or authorize trades to meet it.
- StrategyTune uses recorded bid/ask tick data, but the platform does not apply a commission or slippage model. Results are not broker-demo execution evidence.
- StrategyTune runs one instrument per session; this is not a synchronized multi-symbol portfolio test.

## Results

| Month | Run ID | Engine closed records | Engine wins/losses | Engine net P&L (USD) | Max drawdown (USD) | Reconstructed positions | Position win rate | Position ledger valid? | Daily target compliance |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| 2026-06 | `9ea39322-c424-40c4-be3e-73f92408b090` | 204 | 183 / 21 | -5.11 | 63.49 | 105 | 80.00% | Yes | 95.45% (21/22) |
| 2026-07 | `c11e2067-f99c-44ec-a071-f2c2760f4547` | 216 | 186 / 30 | -117.41 | 175.95 | 107 | 76.64%* | **No** | 95.65% (22/23) |
| 2026-08 | `eb9d6b0e-c519-4623-9379-57374979c914` | 180 | 160 / 20 | -32.48 | 74.43 | 94 | 78.72% | Yes | 95.24% (20/21) |
| 2026-09 | `61e52f6d-2e0a-4a1a-8694-a49a24bee7e5` | 216 | 195 / 21 | -249.40 | 326.60 | 107 | 85.05%* | **No** | 100.00% (22/22) |
| 2026-10 | `2f527243-9f98-4340-9e7d-6977412277a1` | 213 | 181 / 32 | -138.12 | 176.26 | 116 | 72.41%* | **No** | 100.00% (22/22) |

`*` The StrategyTune script's own position reconstruction reported invalid reconciliation in these months. Do not use those monthly position win rates as accepted full-position statistics.

## Findings

1. **All five monthly folds lost money** at the engine level. Combined net P&L was -USD 542.52 across five independent USD 10,000 runs. This is not a pooled account curve.
2. The engine's 87.95% aggregate record win rate (905 wins / 1,029 closed records) is not a full-position win rate. It counts partial-close records and must not be used as a position-level performance claim.
3. Only June and August passed the proxy's position-attribution reconciliation. Together those two valid folds contained 199 reconstructed positions, 158 winners and 41 losers (79.40% position win rate), with combined position P&L of -USD 37.59. Both valid folds were still net losers.
4. July, September and October failed the script's own P&L reconciliation:
   - July: position ledger P&L -USD 5.38 versus engine P&L -USD 117.41; delta -USD 112.03; eight missed close events and five unmatched close records.
   - September: position ledger P&L -USD 47.95 versus engine P&L -USD 249.40; delta -USD 201.45; eight missed close events and five unmatched close records.
   - October: position ledger P&L -USD 150.01 versus engine P&L -USD 138.12; delta +USD 11.89; five missed close events.
5. The three-entry daily target was met on 107 of 110 observed eligible days (97.27%) without forcing entries. Average entries/day ranged from 4.48 to 5.32. This shows the proxy can often reach the diagnostic frequency target, not that the native EA achieves three qualified trades/day.
6. These findings do not approve a strategy, alter risk inputs, or validate live profitability.

## Decision

- **Strategy performance: NOT APPROVED.** The proxy loses in every tested month, and three of five monthly position reconstructions are invalid.
- **StrategyTune ledger: needs repair.** The missed-close and P&L reconciliation defects must be fixed before pooling full-position statistics across folds.
- **PR #8 / PR #9 telemetry code: separate question.** Their code-level regression tests and exact-head MetaEditor compilation must pass. StrategyTune cannot validate the MQL5 exporter. A native MT5 Strategy Tester export and subsequent broker-demo comparison remain required before treating slippage or attribution telemetry as execution evidence.
