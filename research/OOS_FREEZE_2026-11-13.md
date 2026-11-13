# Midas OOS freeze — 2026-11-13

**Status:** frozen research baseline; no production trading logic or risk configuration changed by this record.

## Repository and source identity

- Repository: `cirvannaco-png/midas`
- Frozen branch: `research/oos-freeze-2026-11-13`
- Frozen commit: `488ec04dd7440b58d00218c3e81f3fe6aa3022e1`
- Root EA: `MidasTouch2.mq5`
- Root EA blob SHA: `94dff03a624c47724d8dcba338176409084abcd6`
- Canonical modular source paths are under `backend/source/EA/`; the current root EA is the committed distributable single-file artifact.

### Critical source hashes

| File | Blob SHA |
|---|---|
| `MidasTouch2.mq5` | `94dff03a624c47724d8dcba338176409084abcd6` |
| `backend/source/EA/includes/Trading/OutcomeTrackerLive.mqh` | `52cfde06c000049aab28184e1495eb1622a590bd` |
| `backend/source/EA/includes/Execution/TesterDealExport.mqh` | `66334a01b9e7b4b654c99c295d82c5400fcdc04d` |
| `backend/source/EA/includes/Execution/PositionManager.mqh` | `9f28ef528524f534755921919809e793c6fbd763` |
| `backend/source/EA/includes/Execution/DynamicStopInputs.mqh` | `b3b3e0a8c7629dfce57fa17dacae0f7e149f9422` |
| `backend/source/EA/includes/Portfolio/AccountRiskProfilePolicy.mqh` | `6386b89364d3d613b1c65bde606d5d272ce93edc` |
| `backend/source/EA/includes/Trading/RiskEngine.mqh` | `b73d4666677e2896130b7c63ae2b95906be38a40` |

A test must record the exact compiled EX5 SHA, terminal build, broker server, symbol specification, tester model, date range, inputs and export artifact hashes. A compile of a later source revision is not this frozen EA.

## Frozen MQL5 default configuration

Values below are source defaults, not an assertion that a particular MT5 terminal currently has these inputs loaded.

### Risk and execution

- Account risk profile: `ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT`.
- Small-account target risk: 20% per trade; minimum configured risk: 15%.
- Maximum daily loss: 25%; maximum drawdown: 35%; maximum portfolio open risk: 20%.
- Gold-specific maximum stop risk: KSh 7.50, converted to account currency.
- Execution enabled; execution ledger required, fail-closed.
- Progressive daily-loss de-risk is disabled by default.
- The broker-minimum-volume path rejects a size if it exceeds the approved stop-risk budget; do not enable a minimum-lot override to force participation.

### Live MQL5 position management

- Dynamic stop enabled.
- Dynamic protection activation: +0.75R.
- Break-even stage: +1.00R.
- ATR trailing distance: 1.50 ATR.
- Structural stop anchor enabled, with 0.10 ATR structural buffer.
- Minimum successful stop-modification interval: 5 seconds.
- Live partial close trigger: +2.00R.
- Live partial close fraction: 50% of current position volume.

**Important:** `InpBreakEvenAtR` and `InpTrailATRMult` are documented as legacy outcome-tracker simulation controls. Live stop management uses the separate Dynamic Stop Engine inputs above. The native MQL5 policy is not the same as the StrategyTune v2.14/v2.15 exit model.

## Native tester export gate

The source default `InpTesterServerUtcOffsetMinutes=99999` is an invalid-offset sentinel. The exporter disables itself when this value is used. Before a native tester run:

1. Obtain the actual broker-server UTC offset from the MT5 tester/broker history for the test period.
2. Set the exact verified offset in minutes.
3. Split runs at broker DST offset changes; do not apply one fixed offset across a DST boundary.
4. Confirm logs contain `MIDAS_TEST_EXPORT_READY` and `MIDAS_TEST_EXPORT_COMPLETE`.
5. Reject the run as incomplete if either the deals CSV or open-position CSV is missing, exporter errors occur, or export row counts do not reconcile to MT5 history.

The export records broker deal identifiers, stable position identifiers, deal time, entry type, volume, P&L, commission, swap, fee, entry risk, decision/strategy/regime attribution and explicitly-known market slippage. A missing slippage value is unknown, not zero.

## Research proxy freeze

A separate StrategyTune copy was created for exploratory exit research:

- Name: `Midas Gold v2.14 Frozen Exit Baseline`
- Script ID: `j6nu9khd0zs02c9mxrwq8h43`
- Frozen copy version: 1
- Copied source: StrategyTune `MT2 v2.14 Gold Excursion and Outcome Attribution R`, version 8.

This is **not** the compiled MQL5 EA and must not be described as an actual-EA test. Its default exit model is TP1 0.25R / 40%, TP2 1.00R / 20%, followed by an ATR runner. It is useful only for exploratory proxy research and for testing the research script's own hypotheses.

## Position attribution contract

- Primary research unit: one unique opening position/lot, not an order, closing deal or partial-exit row.
- Group every close row by the source's stable opening/position identifier.
- Use the complete MT5 deal export as the realized P&L and cashflow authority.
- Join the position identifier to the entry-time feature record for sweep grade, BOS, regime, session and entry characteristics.
- Calculate net position P&L as the sum of all associated deal profit, commission, swap and fee cashflows.
- Calculate position R from the actual opening stop-risk cash, not a generic account percentage.
- Calculate MAE/MFE from the position's executable-price path relative to its initial risk; never infer missing excursion values.
- Reconcile: total attributed closed-position net P&L must equal the MT5 history/account result to the currency's rounding tolerance; all open positions must be separately listed.
- Any unmatched deal, duplicate deal ID, missing opening ID, netting reversal, unexplained cashflow or missing excursion path is UNKNOWN/INVALID, not zero and not a losing/winning observation.
- Preserve partial close count and volume as execution diagnostics, but never count them as independent trades.

The StrategyTune proxy's `lastClosedTrade` is only the most recently closed record. Multiple close events between updates can make its internal attribution incomplete. Where `missedCloseEvents > 0` or `positionAttributionValid=false`, discard its internal position P&L totals and reconcile from the complete per-session trade table. Do not silently repair or overwrite the original result.

## Out-of-sample rules

- All previously used StrategyTune dates through 2026-11-11 are known/seen research data. Do not relabel them as blind out-of-sample.
- The StrategyTune v2.14 frozen copy was created at 2026-11-13 17:18:40 UTC. Any future StrategyTune holdout must begin strictly after the freeze timestamp and after market data has become available; confirm actual provider coverage before submitting a run.
- For the actual EA, use this exact Git commit and unchanged MT5 inputs for the first prospective evaluation. Any source, entry, exit, risk, symbol, broker or execution change creates a new experiment version and requires a new future holdout.
- No parameter tuning, feature selection or strategy rejection may use the holdout period while it is being evaluated.
- First checkpoint: at least 20 completed unique opening positions, with full deal/position reconciliation. Twenty is a screening minimum, not statistical proof. Report confidence intervals and expand the sample if it is inconclusive.
- Report gross and net expectancy, profit factor, mean/median R, win/loss payoff, maximum drawdown, MAE/MFE, cost coverage, regime/session concentration and incomplete/open-position counts.
- Include realistic commission, swap, spread and adverse slippage. StrategyTune's built-in backtester does not model separate commission or slippage and cannot validate the MT5 EA's actual broker fills.
- No live-trading approval follows from compilation or a proxy result. Require native MT5 Strategy Tester, then broker demo fill/stop-modification/ledger reconciliation.

## Current status at freeze

- Frozen MQL5 source identity: recorded.
- Frozen StrategyTune proxy copy: created and compiled.
- Native MetaEditor compile for this precise snapshot: not run in this freeze operation.
- Native MT5 Strategy Tester: not run.
- Broker demo execution and protective-stop tests: not run.
- Current strategy profitability: not validated.
- Live deployment: not authorized.
