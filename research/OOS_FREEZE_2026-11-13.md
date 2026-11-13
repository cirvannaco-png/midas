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

## Exploratory StrategyTune exit experiments — training data only

These runs use the frozen StrategyTune proxy, not the MQL5 EA. All are historical development/training observations, use the platform's recorded bid/ask spread, and do not include a separate commission or slippage model. They are not independent OOS evidence.

### Full April–June matched exit-fraction comparison

Same frozen script, Gold / IC Markets / M15, 2026-04-01 through 2026-06-30, starting balance USD 10,000. The only changed input was the single-swing TP1 close fraction.

| Variant | Completed unique positions | Win rate | Net P&L | Profit factor | Mean win | Mean loss |
|---|---:|---:|---:|---:|---:|---:|
| TP1 0.25R / 40% | 144 | 75.0% | -$86.56 | 0.723 | +$2.09 | -$8.67 |
| TP1 0.25R / 60% | 144 | 75.0% | -$69.15 | 0.775 | +$2.21 | -$8.54 |

The platform's complete trade table had 269 close rows and 144 opening positions in each run. The exact opening-position set was identical. On paired position outcomes, 94 positions improved, 15 worsened, and 35 were unchanged under the 60% fraction; paired net P&L improved by $17.41.

This is a modest in-sample improvement, not a profitable strategy: both net P&L and profit factor remain negative/sub-1. The 60% run's custom tracker still recorded one missed close event and a $2.66 P&L mismatch; its internal position totals are invalid. The complete session trade table reconciles to engine P&L and is the source used for this comparison.

### TP1 trigger sensitivity and exit/entry interaction

An April-only challenger raised TP1 from 0.25R to 0.50R while leaving other inputs unchanged. It produced 41 completed unique positions and -$81.92 net P&L (PF 0.551), with one open position at the period end excluded from completed-position metrics. Only 41 openings matched between this challenger and the 45-position baseline set; on those 41 common openings the challenger was worse by approximately $43.39. The four baseline openings absent from the challenger show that changing exits can change exposure occupancy and therefore subsequent entry availability. This is not a clean exit-only comparison. Reject the 0.50R change; do not interpret it as a new entry edge.

### Higher TP1 partial fraction and lot-quantity failure

The initial 80% partial-close test using the unguarded research script failed with `Lot 14 not found`: after a small-volume CFD lot was closed, the manager unconditionally attempted to modify stops on a lot that no longer existed.

A separate StrategyTune research copy was created and patched (no change to the frozen script or MQL5 EA):

- Name: `Midas Gold v2.14 Exit Guard Research`
- Script ID: `uzgla8z1xdjyv3496i28kom3`
- Promoted copy version: 2
- Patch: after TP1 and TP2 partial-close calls, re-read `ctx.account.lots`; only modify stops or arm a trail if the lot still exists. If the close consumed the lot, mark that state closed and skip subsequent lot operations.

The guarded 80% version completed an April 1–12 training run without the runtime exception. On 15 unique closed positions, its net P&L was -$6.04, compared with -$6.34 at 40% and -$6.18 at 60% on the same 15 openings. All three variants had 73.3% win rates, and all remained negative. This is only a small runtime-safety and exploratory comparison; it does not justify promoting 80%.

### Exit research decision

- Keep the live MQL5 exit defaults unchanged: dynamic stop activation 0.75R, break-even at 1.00R, ATR trailing 1.50, and 50% partial close at 2.00R.
- Do not promote StrategyTune TP1/TP2 parameters into the EA; they are not the same exit engine.
- Retain the 60% proxy variant as an in-sample research challenger only. Its PF < 1 and negative expectancy fail promotion.
- Keep the guarded 80% research copy for further training-only work; do not use the unguarded 80% script.
- The next exit comparison must preserve a matched opening-position set or explicitly measure how exit changes suppress later entries. Reject any incomplete run, including the 0.50R test's open-at-end exposure.

## Research-governance pull request

- Draft PR: https://github.com/cirvannaco-png/midas/pull/12
- Branch: `research/locked-oos-multi-window-2026-11-13`
- Scope: discover and enforce all registered locked-OOS reservation intervals in the standard position-ledger CLI; add the post-freeze reservation through 2027-02-13 and tests for interval boundaries/coexistence.
- CI: source consistency, structural/safety validation, native deal-attribution/ledger tests, and static audit all passed. The MetaEditor compile job is skipped on pull requests by workflow design; the separate frozen-source build branch did compile successfully.
- PR remains draft/open; it has not been merged.

## Current status at freeze

- Frozen MQL5 source identity: recorded.
- Frozen StrategyTune proxy copy: created and compiled.
- Native MetaEditor compile for this precise snapshot: not run in this freeze operation.
- Native MT5 Strategy Tester: not run.
- Broker demo execution and protective-stop tests: not run.
- Current strategy profitability: not validated.
- Live deployment: not authorized.
