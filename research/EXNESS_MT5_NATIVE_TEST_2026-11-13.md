# Exness MT5 native test manifest — 2026-11-13

**Status: PREPARED — NOT RUN.** This manifest records a reproducible native MT5 test configuration. It does not claim a Strategy Tester run, broker fill validation, or profitability result has occurred.

## Frozen executable identity

- Repository: `cirvannaco-png/midas`
- Frozen source branch: `research/oos-freeze-2026-11-13`
- Frozen source commit: `488ec04dd7440b58d00218c3e81f3fe6aa3022e1`
- Frozen root source: `MidasTouch2.mq5`
- Root source blob SHA: `94dff03a624c47724d8dcba338176409084abcd6`
- EA version in source: `2.81`
- MetaEditor build validation: GitHub Actions run `43471826607`, 0 errors / 0 warnings.
- Compiled EX5 SHA-256: `bd760f0d7c5ca908fe972ccfbb7ba3c17c9b3cd1fb2cfeabc95de0fc5dc68c0c`

Do not rebuild from a different commit or modify entry, exit, risk, symbol, or timeframe inputs between matched test runs. Record the final EX5 hash from the actual tester terminal.

## Broker and symbol

Use an **Exness MT5 Standard DEMO account denominated in KES**, provided that this account type and currency are available under the user's Exness entity.

- Account type: Standard (demo)
- Account currency: KES
- Gold symbol: `XAUUSDm` (Standard account's `-m` symbol suffix)
- Instrument group: Forex / Forex_Group
- Official Exness contract specification for XAUUSD: contract size 100 troy ounces; pip size 0.01; minimum volume 0.01 lot.
- Exness states its MT4/MT5 server timezone is GMT+0 (UTC+0); set tester offset to **0 minutes**, not Kenya local time (UTC+3).
- Standard accounts are documented as commission-free; retain the broker's real variable spread and instrument swap conditions in the test report.

Official references (checked 2026-11-13):
- MetaTrader timezone: https://get.exness.help/hc/en-us/articles/360014390760-What-is-the-default-timezone-set-for-MetaTrader
- Account currency availability: https://get.exness.help/hc/en-us/articles/360011677700-Trading-account-currencies
- Account-type symbol suffixes: https://get.exness.help/hc/en-us/articles/360014560220-Account-type-suffixes
- Gold contract and trading conditions: https://get.exness.help/hc/en-us/articles/17854173039388-Commodities
- Standard account conditions: https://get.exness.help/hc/en-us/articles/17537782738460-Standard-account

If the MT5 account's live Market Watch differs from `XAUUSDm`, do not guess or rename the symbol: record the exact server-provided symbol and verify its contract specification before proceeding. Also record the exact Exness server label and account entity shown by MT5.

## Historical cross-broker replication run

This is a **cross-broker replication on previously researched calendar dates**, not blind out-of-sample evidence. The IC Markets StrategyTune research already used April–June 2026.

| Parameter | Required setting |
|---|---|
| Symbol | `XAUUSDm` |
| Period | M15 |
| Model | Every tick based on real ticks |
| From | 2026-04-01 |
| To | 2026-06-30 |
| Test deposit | 1,500 KES |
| Leverage | Record the demo account's actual setting |
| EA | Frozen `MidasTouch2.mq5` build above |
| Optimization | Off |
| Forward mode | Off |
| Visual mode | Optional; not required for metrics |

A 1,500 KES deposit matches the small-account test basis. The small-account profile's Gold-specific stop-risk ceiling remains KES 7.50 per signal (0.5% of 1,500 KES). The 20% target / 15% minimum profile inputs remain unchanged; the separate Gold cash cap is the stricter exception. Do not raise the KES 7.50 cap or enable minimum-lot overrides to force orders.

## Tester-only input overrides

Use these overrides only in the historical Strategy Tester run. They are **not** live/demo-trading settings:

| Input | Tester value | Reason |
|---|---:|---|
| `InpTesterExportRunId` | `exness-gold-q2-2026-crossbroker` | Stable human-readable experiment label |
| `InpTesterServerUtcOffsetMinutes` | `0` | Exness MT4/MT5 server UTC+0 |
| `InpRequireExecutionLedger` | `false` | Native historical simulation has no live bridge reservation service |
| `InpExecutionLedgerBaseUrl` | empty | No HTTP bridge in this historical-only run |
| `InpBridgeApiKey` | empty | No bridge credential in this historical-only run |
| `InpAccountCurrencyPerKES` | `0.0` | KES-denominated tester account uses the EA's direct KES=1 path |
| `InpSmallGoldMaxStopRiskKES` | `7.50` | Preserve the configured per-signal Gold cash cap |
| `InpAllowMinLotOverride` | `false` | Do not force a minimum lot above the risk budget |

Keep `InpEnableExecution=true` so the Strategy Tester simulates the EA's order flow. Disabling the ledger requirement is an isolated tester-only exception: this run cannot validate live execution-ledger admission, bridge health, broker reconciliation, or live stop modification. The production/default `InpRequireExecutionLedger=true` requirement must remain unchanged.

The EA source explicitly treats a missing tester currency-conversion factor as an error when a non-KES account is used. A KES account avoids inventing or freezing a USD/KES conversion rate for the whole historical window. Do not use a USD account with `InpAccountCurrencyPerKES=0`.

Keep `InpEnableTopDownMTF=false` (frozen source default) and the M15 execution chart. The configured FVG timeframe is also M15. Do not enable Top-Down MTF for this test; the EA explicitly requires an M1 chart when that option is enabled.

The daily qualified-trade target remains `InpMinimumQualifiedTradesPerDay=3`, with qualification threshold `InpMinimumQualifiedTradeR=0.25`. This target is diagnostic; never force entries to meet it. Report days below target as misses, not as a reason to lower filters.

## Export acceptance gate

Before the test is accepted, the MT5 Journal must contain:

- `MIDAS_TEST_EXPORT_READY`
- `MIDAS_TEST_EXPORT_COMPLETE`

The terminal must produce all three files in the Common Files area:

1. `MidasTesterDeals_<run>.csv`
2. `MidasTesterOpen_<run>.csv`
3. `MidasTesterMeta_<run>.json`

Reject the export as incomplete if either marker is absent, any `MIDAS_TEST_EXPORT_ERROR` appears, any output file is missing, the deal IDs/position IDs do not reconcile to the Strategy Tester history, or the exported net cashflows do not reconcile to the tester report within currency rounding. Open positions at test end must be reported separately.

The metadata must confirm:
- `server` matches the actual Exness MT5 server label;
- `account_currency` is `KES`;
- `server_utc_offset_minutes` is `0`;
- `timestamp_basis` is `broker_wall_clock_with_explicit_offset`;
- symbol point, tick size, tick value, fill mode, leverage, and spread sample statistics are populated.

## Required deliverables for independent analysis

Upload the HTML Strategy Tester report, Journal log, the three export files, and the actual `.set` file used. Then reconcile by unique `position_id` / deal lineage, never by raw closing-row count.

Required metrics:
- closed unique positions and partial-close rows separately;
- gross/net P&L, commission, swap and fee cashflows;
- expectancy per position and per R, profit factor, mean/median R;
- MAE/MFE per unique position using executable bid/ask path;
- max equity drawdown and consecutive loss sequences;
- spread distribution, trade duration, session and weekday concentration;
- setup/regime attribution, qualified-trade-per-day counts, and rejected/blocked-entry diagnostics;
- open-at-end positions and all unmatched/ambiguous IDs.

Do not infer zero commission, slippage, swap, or excursion when the evidence is missing. If the tester data cannot expose a component, label that component UNKNOWN and keep the result provisional.

## Prospective holdout discipline

The reserved future holdout window remains separate:
- Start: `2026-11-13T17:18:40Z`
- End: `2027-02-13T17:18:40Z`
- Maturity cut: `2027-02-27T17:18:40Z`

Do not tune or select parameters on that period. First verify Exness tick coverage after the freeze timestamp. The Q2 2026 Exness exercise above is a broker replication only; it must not be relabelled as blind OOS.

## Explicit limitations

This manifest is prepared, not executed. No native MT5 terminal is available to this repository workflow. A successful compile does not establish that the EA trades correctly in Exness MT5, that the broker's historical ticks are complete, that exported data reconcile, or that the strategy is profitable. A separate demo forward test must validate broker fills, stop modifications, and the production execution ledger before any live consideration.
