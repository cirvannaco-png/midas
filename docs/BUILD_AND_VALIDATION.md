# Build and validation

## Build the one-file MT5 EA

Use modular sources in `development/EA/`. Do not hand-edit `MidasTouch2.mq5`.

```bash
python scripts/build_single_file.py
python scripts/build_single_file.py --check
python scripts/validate_single_file.py
```

The root `MidasTouch2.mq5` is the deployable EA. Custom modules are inlined; MetaTrader's standard `Trade/Trade.mqh` is the one expected platform include.

## Bridge and ledger configuration

Production/demo EA inputs must include:

- `InpExecutionLedgerBaseUrl`: HTTPS bridge origin, without an endpoint suffix.
- `InpBridgeApiKey`: the key matching the bridge's `X-API-Key` configuration.
- `InpRequireExecutionLedger=true`: required for all demo/forward and live-candidate runs.

The MT5 terminal must allow-list the HTTPS bridge origin in **Tools → Options → Expert Advisors → Allow WebRequest for listed URL**. Startup must show a successful authenticated `GET /execution-ledger/health` check and subsequent complete broker/history reconciliation. A green bridge health response alone does not complete reconciliation.

The bridge is separate from the EA: FastAPI/PostgreSQL stores execution intent and evidence; the EA remains the only component that submits broker orders. The bridge never places or retries a broker order.

## Strategy Tester configuration

MetaTrader's `WebRequest` function is not available inside Strategy Tester agents. For isolated research backtests:

1. Leave the bridge URL and API key blank.
2. Set `InpRequireExecutionLedger=false` in the tester inputs only.
3. Label the result as a strategy simulation; it is not evidence of bridge, database, broker-execution, or restart-recovery correctness.

Do not carry this override into demo or live-candidate operation. Those environments must restore `InpRequireExecutionLedger=true` and pass the bridge/runtime preflight.

## Strategy and daily objective

The default objective is three qualified, fully closed winning trades per weekday, each meeting the configured minimum realized-R threshold (default 0.25R). It does not force an entry, lower filters, or promise three opportunities. Preserve configured risk limits and distinguish entry count, position-level outcomes, and close-deal records when evaluating results.

## Required validation

- Python source generator check and structural/safety validator.
- Official Windows MetaEditor compile with exactly zero errors and zero warnings.
- Matched Strategy Tester comparisons using consistent date ranges, broker symbol specifications, spread, commission, and slippage.
- Chronological out-of-sample and forward validation.
- Broker demo checks for reservations, fill and rejection handling, SL/TP amendments, partial/full exits, bridge disconnects, restart/history reconciliation, and emergency stop.
- Review of all evidence before live approval.

A compile is not a profitability test. Strategy research results are not live execution evidence. If a gate has no evidence, leave it marked pending rather than treating it as passed.
