# MidasTouch2 Validation Report

**Build branch:** \`build/single-file-staging\`  
**Build commit:** \`368020275a756eb80bace4165633940c11d21308\`  
**Upstream source:** \`cirvannaco-png/Midas-touch2-@3622ed5a434c36f0c05ab9c9863d17b6fd743e9a\`  
**EA artifact:** \`MidasTouch2.mq5\`

## MetaEditor compile

- Compiler: official MetaTrader 5 MetaEditor64 on Windows Server 2025
- Result: **0 errors, 0 warnings**
- EX5 output: produced and uploaded
- Build workflow: https://github.com/cirvannaco-png/midas/actions/runs/42371237736
- Artifact: \`MidasTouch2-MetaEditor-build\` (EX5, MetaEditor log, compile summary)

## Static validation

- Source regeneration: passed
- Flattened source structural/safety checks: passed
- No custom quoted include dependencies remain in the consolidated EA
- The remaining \`Trade\\Trade.mqh\` dependency is supplied by the official MT5 standard library

## LONA validation

- Existing Midas research strategy dry-run: completed
- Runtime error: none
- This dry-run is a strategy-runtime smoke test only; it does not compile MQL5 and does not provide performance metrics.
- LONA backtest credit balance at test time: 0; full LONA backtest was therefore not run.

## StrategyTune research

All tests used Gold (IC Markets data), M15, USD 10,000 starting balance, and recorded bid/ask data. StrategyTune does not model separate commission or slippage.

| Period | Profit Protection v2 | Reliable baseline |
|---|---:|---:|
| 2025-11-07 to 2026-11-06 | -$256.60 | -$328.58 |
| 2025-11-07 to 2026-05-01 | +$29.77 | -$2.57 |
| 2026-05-01 to 2026-11-06 | -$286.93 | -$326.01 |

The candidate beat the baseline by $71.98 over the full period but remained net negative. The second-half loss demonstrates material regime instability. The research scripts are not a byte-for-byte or behaviorally equivalent execution of the MT5 EA; these are strategy-logic research proxies, not proof of EA backtest performance.

## Remaining release gates

- MT5 Strategy Tester on the compiled EA: **not run**
- Demo-account execution and protective-stop reconciliation: **not run**
- Production/live approval: **not granted**

A successful compile proves the source compiles; it does not prove profitable behavior, broker compatibility, safe fills, or live readiness. Keep live trading disabled until the MT5 Strategy Tester and demo gates pass.
