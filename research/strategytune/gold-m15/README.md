# Gold M15 StrategyTune archive

This directory stores the exact StrategyTune research proxy code and metadata for the selected Gold M15 comparison candidates.

- `v2.6/`: control.
- `v2.7/`: TP1 0.50R exit experiment; rejected.
- `v2.12/`: regime-specialist hybrid.
- `v2.13/`: trend-only single-swing candidate; strongest current research candidate, not approved for live trading.

Each folder contains `metadata.json` and `strategy.ts` exported from the compiled StrategyTune script version. The two files are a coupled artifact. The source is StrategyTune TypeScript, **not MQL5**; it cannot be copied into the MT5 EA or used as proof of native EA behavior.

See [the consolidated research report](../../STRATEGYTUNE_GOLD_M15_V2_13_2026-11-10.md) for test windows, results, accounting methodology, rejected experiments, and the next validation gate.

StrategyTune scripts are private cloud objects in the connected StrategyTune account. These exports make the selected research candidates reproducible from this repository, but the original saved scripts remain in StrategyTune.
