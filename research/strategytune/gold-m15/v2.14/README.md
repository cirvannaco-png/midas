# Midas Gold v2.14 Exit Guard Research

- StrategyTune script ID: `uzgla8z1xdjyv3496i28kom3`
- Saved compiled version: 4
- Attribution rule: per-position realized outcomes are not computed from the in-run `lastClosedTrade` snapshot. The export contains entry-time telemetry only; authoritative outcomes must be joined from saved `get_session_trades` rows grouped by `openingFillId` and reconciled with engine closed P&L.

This folder contains the exact metadata/code pair exported from StrategyTune. This TypeScript research proxy is not MQL5 production code.
