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
- Both presets must keep InpEnableExecution=true, InpEnableDynamicStop=true, InpTrackOutcomes=true, and InpAllowMinLotOverride=false.
- Both presets use InpAccountRiskProfile=1 (small account), keep InpSmallMinimumRiskPercentPerTrade=15 and set InpSmallRiskPercentPerTrade=20 exactly. The comparator rejects any context or preset that changes this protocol risk target. The existing ceilings may not be raised: daily loss 25%, drawdown 35%, portfolio risk 20%, Gold stop-risk KES 7.50, or position counts above 3.
- Both presets must set InpRequireExecutionLedger=false **only for the Strategy Tester run**. MT5 Strategy Tester agents cannot call WebRequest, so leaving the production default true blocks new EA entries and yields a misleading zero-trade run. Midas now enforces the bypass as tester-only: outside Strategy Tester the runtime always treats the ledger as required even when an imported .set says false. The remote ledger is not used in the tester; native CRiskEngine sizing, local order/position management, protective stops, partial closes, recovery and tester deal export remain active. Do not use this test preset on a live/demo chart.
- The tester's InpTesterServerUtcOffsetMinutes must be the historical broker-server UTC offset for the tested date segment. Supply server_timezone_evidence_path in the comparison manifest, pointing to a JSON record containing the exact broker server name, its IANA timezone, an HTTPS source reference to the broker's official timezone documentation, and the UTC time that mapping was verified. The comparator checks the IANA timezone's offset minute-by-minute over the complete inclusive MT5 tester date range and rejects a run that crosses any offset transition; split the experiment at DST changes and use separate presets/exports. The comparator cannot authenticate the broker document or infer the server-to-IANA mapping: an operator must independently verify that mapping against official broker evidence. The MQL5 exporter's numeric offset is still deliberately invalid by default; do not guess it.
- Preserve the original matched-experiment manifest horizon (it includes the registered locked-OOS interval because the shared comparator schema requires that chronology), but the actual MT5 terminal launch file must not run into the holdout. Its FromDate must equal the broker-local calendar date of the development start, with that start aligned to broker midnight. Its ToDate must be the broker-local calendar day immediately before the exclusive locked-OOS start date. The comparator derives this from the verified server offset, checks the exact .ini, and rejects an OOS-day ToDate. For this test fixture only, UTC+03:00 gives FromDate=2026.10.02 and ToDate=2026.11.12; production dates must be recalculated from the verified broker offset and reservation timestamp.
- For a KES account, leave InpAccountCurrencyPerKES=0; the engine uses 1.0 for a KES account. For a non-KES account, provide a verified positive account-currency-units-per-KES conversion in the tester preset. No FX rate is guessed.
- No risk, sizing, drawdown, daily loss, open-position, stop, partial-close, trailing, execution, or recovery input may differ between the pair. The only allowed .set difference is the router-enable flag.

## Native matched pair

Use one MT5 terminal build, one EA source commit/build, one broker's exact symbol specification, one immutable real-tick dataset, identical date range and warm-up, symbol/timeframe, starting equity, account currency, leverage, margin mode, fill policy, actual commission schedule and all non-router inputs.

Prepare two .set files:
1. baseline.set: router disabled.
2. continuation.set: same exact values as baseline except router enabled.

The pair manifest must include a separate broker timezone evidence record. Example structure (the broker name, IANA zone and source reference below are placeholders, not an actual broker assertion):

    {
      "schema_version": 1,
      "broker_server": "Exact broker server name from MT5",
      "iana_timezone": "Europe/Helsinki",
      "source_reference": "https://official-broker.example/timezone-documentation",
      "verified_at_utc": "2026-11-20T00:00:00Z"
    }

Set manifest.server_timezone_evidence_path to that file. The timezone identifier must reflect the broker's documented historical server clock, not the trader's local timezone.

Both keep InpFreshSweepEnableSingleSwingFallback=false. The same InpTesterExportRunId label is used in both .set files; the exporter appends a runtime suffix, and the manifest run_id must match the resulting MidasTesterMeta_*.json run_id. The matcher in tools/compare_mt5_continuation_runs.py rejects any other .set difference, a non-canonical EA filename, a tester preset that would block execution, any weakened small-account ceiling or non-20% test risk, mismatched run context, reused run IDs/artifacts, hash mismatch, missing tester metadata or launch .ini, a non-real-tick tester model, zero execution delay, mismatched tester execution settings, missing broker/server/symbol contract/spread observations, missing commission/swap/fee columns, and missing strategy attribution. It checks cash-per-point-per-lot against point/tick-size/tick-value and requires metadata server offset to match the preset. It validates the full real MT5 launch date range against the supplied IANA timezone rules, rejects a run that crosses any UTC-offset transition, and rejects a ToDate that reaches the locked-OOS start day. This is a schedule check against the supplied broker-server-to-IANA mapping, not independent authentication of that mapping; the operator must verify its source reference against official broker evidence. The report only scores development entries before the declared locked-OOS boundary; OOS outcomes stay withheld and are not run by the paired development tester configuration.

Run the complete EA in MT5 Strategy Tester for both presets using Every tick based on real ticks when the chosen broker's genuine tick history is available. Export and retain for both variants:
- actual .set file;
- exact MT5 [Tester] launch .ini used for the run. It must use Model=4 (Every tick based on real ticks), Optimization=0, ForwardMode=0, and a matched non-zero ExecutionMode (-1 random delay or a positive fixed delay in milliseconds); symbol, period, dates, deposit/currency/leverage and expert preset must be explicit;
- native HTML tester report including balance/equity graph and tick-level equity drawdown;
- complete tester deal CSV with profit, commission, swap, fee, partial-close rows, risk cash, requested/actual fill price and slippage evidence, strategy attribution, and position identifier;
- open-position ID CSV (header-only when no position remains open);
- tester metadata from MidasTesterMeta_*.json, including run_id, point, tick size, tick value, cash-per-point per lot, account currency, leverage, broker/server, terminal build, fill mode, server UTC offset, spread observations, exporter status, full-history expected/recorded/missing deal counts, exported row counts, and file-write flags;
- immutable tick-data/archive file and SHA-256.

Use the exact cash-per-point-per-lot value from each validated tester metadata file/symbol specification in the cost tool. Never substitute a generic Gold pip value. For real ticks the observed baseline spread is already in fills; only incremental spread widening is added by the stress analyzer. The comparator requires the two metadata exports to match in broker/server, account currency, leverage, terminal build, point/tick contract, fill mode, UTC offset and spread observations before treating the pair as matched.

## Cost and adverse-condition matrix

Run tools/cost_stress_monte_carlo.py independently on both deal exports with identical parameters. Standard incremental grid:
- full-spread widening: 0, 2, 5 points;
- additional slippage: 0, 1, 2 points per executed deal-side fill;
- additional commission: zero and any broker-sourced surcharges that are actually applicable.

Actual commission/swap/fee remain in each position's base P&L. Additional commission sensitivity is a surcharge per 1.0 lot per deal-side fill. Only use values backed by the selected broker's current published contract/tariff or measured commission records. Do not guess an amount. Realised commission cashflows are not to be replaced with a generic commission assumption.

Important scope distinction: the cost-stress tool is a post-run settlement sensitivity. It deducts incremental spread/slippage/commission from each completed position based on executed volume; it does not re-simulate altered bid/ask ticks or model whether a widened spread would have changed an entry, stop, partial close or fill. To measure that path-dependent effect, run additional native MT5 Strategy Tester variants on a separately defined adverse tick stream / spread model and label them as separate matched experiments. Never describe a post-hoc cost deduction as a full re-simulation of execution.

Include chronological trend, range/chop, transition, high/low-volatility and major-session periods in the native test corpus. Inspect rollover/illiquid periods and recorded spread spikes. Where the source history lacks gaps or stress events, label the limitation; do not claim a gap test was performed. Retain all walk-forward fold outputs and 10,000-run sequence-shuffle/bootstrap drawdown diagnostics at fixed seed. These are settlement diagnostics; native MT5 tick-level equity drawdown is still mandatory.

## Whole-EA test scope

The existing Windows mt5-compile.yml job compiles the consolidated EA and runs deterministic no-order native policy suites for account risk profiles, config contract, decision geometry, dynamic stops, Fresh-Sweep router policy, opposing exposure and position-management policy. The Python test suites cover whole-position broker-deal accounting, partial-close reconstruction, cost stress and the backend's durable execution-recovery journal. The comparator now requires tester metadata and an explicitly configured isolated tester preset; its local tests also reject accidental live/demo use of the external-ledger bypass.

These are necessary engineering tests, not a substitute for a native Strategy Tester run or broker demo. In a demo environment, separately fault-inject ambiguous submit timeouts, partial fills followed by cancellation/late fill, rejected/invalid stop amendments, terminal restart with open positions, duplicate/replayed deal events, and ledger reconciliation. Verify no duplicate order is sent, no unknown exposure is silently resumed, the original protective stop is not loosened, every partial exit is reconciled by position/deal identity, and the risk gate stays closed until authoritative broker state is restored.

## Comparison and promotion gates

Run the comparator after exporting both real MT5 runs:

    PYTHONPATH=backend/source python -m tools.compare_mt5_continuation_runs --manifest artifacts/mt5/continuation-pair/manifest.json --output artifacts/mt5/continuation-pair/comparison.json

Compare completed-position expectancy, profit factor, payoff asymmetry and realized R, maximum closed-position drawdown, loss streak, strategy attribution, open/censored counts, and native equity drawdown for baseline and continuation. A candidate is not useful merely because it trades more or has a higher win rate.

Do not promote based on a high win rate, research proxy, single window, or compile pass. Require cost-complete positive expectancy, more than one market regime, independent locked-OOS evaluation with sufficient closed positions, acceptable tick-level drawdown, no partial-close/accounting mismatch, successful stop and recovery tests, and a broker-demo forward run. Keep both registered locked-OOS intervals untouched unless their exact entry-time provenance has been independently verified. In particular, any research segment spanning November 13, 2026 after 17:18:40 UTC must be checked trade-by-trade against the later reservation before it can be called fresh OOS.
