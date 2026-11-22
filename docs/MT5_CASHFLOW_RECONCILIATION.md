# Native MT5 cashflow reconciliation

`backend/source/tools/reconcile_mt5_cashflows.py` independently checks the native tester export before any performance comparison is trusted.

## Required evidence

- Complete `MidasTesterMeta_*.json` from the same tester run.
- Matching `MidasTesterDeals_*.csv` (the CSV row count must equal both native recorded and exported deal counts).
- Optional normalized Strategy Tester summary JSON and, separately, broker statement deal CSV plus broker summary JSON.

The metadata must state `export_status=complete`, zero missing deals, matching expected/recorded/exported counts, and successful deal-file writing. Profit, commission, swap, fee and net-cashflow totals must all exist and reconcile to the exported deal CSV. Blank monetary cells fail closed; they are not interpreted as zero.

## Commands

Run from `backend/source/`:

```bash
python -m tools.reconcile_mt5_cashflows \
  --metadata /path/to/MidasTesterMeta_run.json \
  --deals /path/to/MidasTesterDeals_run.csv \
  --tester-summary /path/to/tester-summary.json \
  --broker-deals /path/to/broker-statement-deals.csv \
  --broker-summary /path/to/broker-summary.json \
  --output /path/to/cashflow-reconciliation.json
```

Summary JSON uses numeric `profit`, `commission`, `swap`, `fee`, and `net_cashflow` fields. `net_cashflow` must equal the sum of the four components. Broker statement rows may include separate commission/fee-only balance entries; include them in the broker CSV so they are not lost merely because they have no position identifier.

## Interpretation

Tester CSV vs tester metadata, tester CSV vs Strategy Tester summary, and broker statement vs broker summary are independent reconciliations. The tester-vs-broker delta is reported, not required to be zero: tester and broker execution can differ in spread, fills, slippage, swap timing, commissions, account conversion, and statement treatment. Investigate unexplained deltas; never erase them by changing signs or forcing totals to match.

This utility does not execute MT5, validate the tick archive, infer missing balance operations, or prove that a broker statement is complete. A native matched baseline/candidate run still requires the capture bundle documented in [IC Markets KE MT5 benchmark capture](IC_MARKETS_KE_MT5_BENCHMARK_CAPTURE.md).
