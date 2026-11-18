# Fresh-Sweep Additive Router — StrategyTune source provenance

- StrategyTune script: **Midas v2.14 Fresh-Sweep Additive Router**
- Script ID: `zc2suyod4q34rxrgswjuk9wt`
- Version: 3
- Compile state at capture: compiled successfully
- Parent script: `gxd1a9kd9srqr0ca0cvpq809` — Midas v2.14 Trend-Continuation Frequency Lab v2
- Candidate source captured from the saved StrategyTune v3 script on 2026-11-18.

## Candidate delta

Compared with its parent, the saved candidate adds one input, `maxFallbackSignalAgeBars` (integer, default 4), and applies it in the single-swing sweep loop so that sweeps older than four completed bars are rejected. The rest of the StrategyTune metadata defaults are unchanged. In the source code, the previous cross-family best-candidate comparison was replaced with continuation-first selection: a selected continuation direction wins; only when continuation fails to select a direction does the router consider the single-swing lane. That includes close opposing continuation candidates whose normalized scores do not clear the directional-advantage threshold.

The router evaluates continuation first. If no continuation direction is selected, it can fall back to single-swing when that lane is enabled. Note that the source falls back when continuation candidates fail to produce a directional selection (including a close buy/sell conflict), not strictly only when no continuation candidate exists. The native port preserves that source behavior and keeps single-swing disabled by default. The single-swing regime gate is adaptive: below 0.20 ATR slope it applies midpoint premium/discount validation; from 0.20 to below 0.45 it rejects the transition regime; at or above 0.45 it admits trend conditions with a 1.5 ATR range cap.

## Research limitations

This is a StrategyTune research strategy, not the native MT5 EA. StrategyTune backtests do not exercise Midas' native execution ledger, broker adapter, sizing engine, position manager, protective-stop modifications, commissions, or slippage. A successful StrategyTune compile is not evidence of native compilation, trade accuracy, or profitability. See the pull request for matched-run and native-validation status.
