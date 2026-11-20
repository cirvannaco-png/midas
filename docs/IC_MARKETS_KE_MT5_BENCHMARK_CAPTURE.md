# IC Markets (KE) MT5 benchmark capture

**Status:** selected benchmark; account-specific evidence is still pending. This document does not authorize a live account or live trading.

## Frozen benchmark choice

- Broker entity: IC Markets (KE) Limited
- Platform: MetaTrader 5
- Account type: Raw Spread demo
- Instrument: Gold / XAUUSD (use the exact symbol label shown by the connected server)
- Strategy timeframe: M15
- Research candidate: gated Direction-Aware Dual-Lane Rank B
- Control: continuation-first baseline with the Rank B selector disabled

IC Markets (KE)'s public account page describes its MetaTrader Raw Spread commission as USD 3.50 per lot per side. Its help centre explains that MT5 commission is charged on opening and closing sides and that account-currency tariffs vary. Treat these as published tariff references only. The actual account's deal history and commission schedule remain authoritative. Public spread pages explicitly warn that instrument specifications may change and that the most accurate details are those shown inside the electronic trading system.

## Step 1 — create or use a demo terminal

1. Use the IC Markets (KE) site and select **Try a free Demo**. Choose Raw Spread and MetaTrader 5.
2. Install the desktop MetaTrader 5 terminal. The mobile MT5 app is not the environment for this native Strategy Tester workflow.
3. Sign in to the demo server. Do not share the login, investor password, one-time code, account number or personal documents in this repository or chat.
4. In Market Watch, enable the broker's exact Gold symbol. If its name is not exactly XAUUSD, copy the exact symbol string.

This is a benchmark selection, not an instruction to fund a live account.

## Step 2 — export the account and Gold contract

1. Copy development/EA/tests/BrokerSpecSnapshot.mq5 into the terminal's MQL5/Scripts folder.
2. Open MetaEditor, compile the script, and confirm **0 errors / 0 warnings**.
3. In MT5 Navigator → Scripts, run BrokerSpecSnapshot on any chart while connected to the IC Markets (KE) demo server.
4. Set InpCaptureSymbol to the exact Gold symbol string (including suffix) and leave InpCaptureTag=ICMarketsKE.
5. Retrieve the generated MidasBrokerSpec_*.csv from the terminal's **Common Files** folder. In MT5, FileOpen with FILE_COMMON writes to the shared terminal files area.
6. Review the CSV before sharing it. Send only this CSV and, optionally, a screenshot of the non-sensitive symbol specification panel.

The script is read-only: it sends no orders and does not export account number, account holder name, login or credentials. It captures broker company, server, account currency/leverage/margin mode, terminal build, Gold digits/point/tick size, profit/loss tick values, contract size, volume limits, margin and swap properties, execution/filling modes, order modes, stops/freeze levels, currencies and one current quote.

The current server-clock versus PC-GMT difference is explicitly labelled diagnostic only. It is **not** accepted as proof of historical broker UTC offset or daylight-saving transitions.

## Step 3 — establish timezone provenance

Obtain broker-confirmed documentation or written support confirmation for the exact MT5 server's historical UTC offset over each proposed test window, including daylight-saving transition dates. Retain the source and the exact offset in minutes for every segment.

Do not use:
- the current offset as a historical offset;
- an MT4 trading-hours page as proof of MT5 server history;
- the PC's timezone as broker timezone;
- a single constant offset across a DST transition.

Split test segments at every offset change. Set InpTesterServerUtcOffsetMinutes from that evidence for each segment. A missing or ambiguous offset keeps evidence export disabled.

## Step 4 — archive the real-tick dataset

1. Use the same connected broker server and exact symbol in one desktop MT5 terminal.
2. In Strategy Tester, select **Every tick based on real ticks** and allow MT5 to download the required interval before comparing variants.
3. Preserve the broker/server identity, terminal build, symbol, interval, real-tick modelling mode and the exact tester cache/data files used for the run. Keep a read-only archive copy before the paired runs and calculate SHA-256 for every archived data file.
4. Use that same immutable archive for baseline and Rank B. Do not silently refresh one variant's history after the other has run.
5. If MT5 cannot supply real ticks for the requested period, stop the experiment. Do not replace them with generated ticks or StrategyTune data and call it the same broker dataset.

The existing paired-run comparator also checks that the baseline and candidate agree on server, account currency, leverage, terminal build, point/tick contract, fill mode, UTC offset and spread observations. A matching export does not, by itself, prove that two vendor feeds are identical: retain the underlying archive and its hashes.

## Step 5 — matched native MT5 run

Use the existing protocol in backend/source/docs/CONTINUATION_ROUTER_MATCHED_MT5_TEST_PLAN_2026-11-19.md. The pair must use identical EA build, real ticks, dates, warm-up, deposit, account currency, leverage, margin/fill assumptions, execution delay, commission, swaps, fees and every risk input. The only allowed .set difference is the Rank B router-enable input.

Keep these controls intact:
- InpFreshSweepEnableSingleSwingFallback=false in both variants.
- All production risk, sizing, stop, trailing, partial-close, recovery and position-management inputs identical.
- The tester-only external-ledger bypass may be used only inside the Strategy Tester preset; it must remain enforced as required outside Strategy Tester.
- Rank B and additive-router gates remain off in production until all promotion gates pass.

Retain for both variants the .set, exact tester .ini, native HTML report, deal CSV, open-position CSV, tester metadata, logs, tick archive and SHA-256 manifest. Then run incremental cost sensitivity, path-dependent adverse tick/spread variants, chronological walk-forward, locked out-of-sample evaluation and demo lifecycle/fault-injection tests.

## Acceptance criteria

A broker capture is complete only when all of the following exist:

- MidasBrokerSpec_*.csv from the exact IC Markets (KE) MT5 demo server;
- broker-confirmed historical server UTC offset evidence, segmented at DST changes;
- exact account commission tariff / account-currency basis;
- immutable broker-server real-tick archive with per-file SHA-256;
- matched baseline and Rank B .set/.ini plus tester exports;
- zero metadata or test-context mismatches.

Until then, the native profitability test is **blocked**, Rank B remains disabled, and PR #22 remains draft/unmerged.
