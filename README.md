# Midas Touch 2

Midas Touch 2 is a MetaTrader 5 Expert Advisor (EA) with a separately deployed execution-ledger bridge. The distributable EA is the single root file, `MidasTouch2.mq5`; the modular MQL5 development source remains under `development/EA/`.

This repository is a **release candidate**, not a live-trading approval. A successful compile proves source validity only. It does not establish profitability, broker compatibility, position-management safety, or production readiness.

## System boundary

### MT5 Expert Advisor

The EA owns market analysis, signal generation, strategy selection, risk sizing, order submission, broker-facing position management, and protective-stop logic. Its custom implementation is flattened into `MidasTouch2.mq5` so it can be installed directly in `MQL5/Experts/`. The only external compile-time include is MetaTrader's standard `Trade/Trade.mqh` library.

### Execution-ledger bridge

The bridge is a separate FastAPI service backed by PostgreSQL. It provides authenticated execution reservations, idempotent state transitions, position/order/deal synchronization, and restart/history reconciliation. It **does not submit or retry broker orders**; the EA remains the sole broker execution authority.

The EA requires an authenticated `GET /execution-ledger/health` probe returning HTTP 200 with both `execution_ledger=ready` and `ledger_schema=ready`. Health verification and reconciliation are separate state gates: the health probe alone never opens admission; only successful broker snapshot and history reconciliation do. Failed ledger POSTs invalidate both gates and require a fresh health probe plus reconciliation before another entry. The EA throttles retries with local terminal time, so recovery is not dependent on new market ticks or an open session. If the bridge or ledger is unavailable, new entries fail closed. Local protective management of already-open broker positions remains an EA responsibility.

The bridge API uses `X-API-Key`. Configure the HTTPS base URL and key through EA inputs locally; do not commit credentials. Add the bridge origin to MT5's **Tools → Options → Expert Advisors → Allow WebRequest for listed URL** setting.

## Source provenance

`SOURCE_MANIFEST.json` keeps two records separate: the immutable upstream baseline and the exact staged EA source snapshot. The staged snapshot pins the Git tree commit and Git blob SHA-1 plus byte size for every source file under `development/EA/`. `scripts/validate_single_file.py` rejects missing, extra, modified, or size-mismatched staged source files. The generated EA banner records both the upstream baseline and the staged-source snapshot used by the generator.

## Source and generated file

Edit modular sources in `development/EA/`, not the generated root EA. The generator expands the active local include closure and rejects include cycles, missing dependencies, conditional local includes, and duplicate include guards.

```bash
python scripts/build_single_file.py
python scripts/build_single_file.py --check
python scripts/validate_single_file.py
```

The source-consistency workflow regenerates the distributable file on branch pushes. The MetaEditor validation workflow checks that the committed single-file EA matches the modular source before compilation.

## Backtesting versus bridge validation

MetaTrader does not allow `WebRequest` from Strategy Tester agents. For isolated strategy backtests only, leave the bridge URL/key blank and explicitly set `InpRequireExecutionLedger=false` in the tester configuration. Such a run tests strategy behavior; it does **not** test reservations, database persistence, or bridge availability.

For demo/forward validation, restore `InpRequireExecutionLedger=true`, configure the HTTPS endpoint and API key, allow-list the endpoint in MT5, and run the read-only `ProductionRuntimePreflight.mq5` script. Verify the authenticated database-health response and the EA's `EXECUTION_LEDGER_READY` startup audit before evaluating broker fills, stop amendments, close events, or restart recovery.

## Daily opportunity objective

The default target is **three qualified closed winning trades per weekday**, with each counted result meeting the configured minimum realized-R threshold (default 0.25R). This is an objective and reporting mechanism, not an entry quota: the EA must never manufacture or force trades to meet it.

## Absolute Gold stop-risk exception

Gold symbols (`XAU*` or names containing `GOLD`) have an **absolute hard maximum of KES 7.50 stop risk per signal across every account-risk profile**, including the combined risk of all legs in an automated multi-leg entry. Non-Gold instruments retain the selected profile's own risk settings. The EA converts KES to account currency using a fresh broker FX quote; direct KES/account-currency quotes use bid, inverse quotes use ask, and a quote older than five minutes is rejected. A missing/stale rate or minimum broker volume above the cap blocks the Gold order. For non-KES Strategy Tester accounts, set `InpAccountCurrencyPerKES` explicitly (account-currency units per KES); no FX rate is guessed. Manual chart orders use the same cap. Gold sizing uses the adverse edge of the configured entry-deviation band when calculating stop risk.

The 20% small-account profile remains high-risk for non-Gold instruments and is not a live-trading recommendation. Resolve broker contract, symbol and account-currency settings in demo before any live use.

## Release gates

A release requires all of the following evidence:

1. Source generator check and structural/safety validation pass.
2. Official Windows MetaEditor compile reports zero errors and zero warnings.
3. Matched MT5 Strategy Tester runs cover baseline and controlled strategy ablations with realistic spread, commission, slippage, and out-of-sample periods.
4. Demo execution verifies reservations, fills/rejections, partial/full closes, protective-stop modifications, disconnections, restart recovery, and emergency-stop behavior.
5. Risk limits, broker contract constraints, and independent forward results are reviewed before any live approval.

No backtest or win-rate target is a profitability guarantee. Keep live trading disabled until these gates have been evidenced and reviewed.

## Single-repository source layout

`cirvannaco-png/midas` is the one authoritative repository for Midas Touch 2. The former companion repository, [`cirvannaco-png/Midas-touch2-`](https://github.com/cirvannaco-png/Midas-touch2-), is retained as source provenance; its complete project tree is included under `backend/source/`. Builds, tests, MT5 packaging, and ongoing development are maintained from this repository.

### Canonical MT5 / MQL5 build

| Path | Authority / purpose |
|---|---|
| `MidasTouch2.mq5` | Generated, distributable single-file MT5 Expert Advisor. Install this file in `MQL5/Experts/`. |
| `development/EA/` | **Canonical modular MQL5 source** used to generate the root EA. Contains the EA, indicator, all local `.mqh` modules, policy engines, risk/trailing-stop logic, broker execution, recovery, monitoring, UI, and native MQL5 tests. |
| `scripts/build_single_file.py` | Expands the active local include closure into the standalone EA; rejects missing dependencies, include cycles, conditional local includes, and duplicate guards. |
| `scripts/validate_single_file.py` | Verifies the staged source manifest, generated output, and safety invariants. |
| `.github/workflows/mt5-compile.yml` | Active MT5 validation workflow, source-consistency checks, official Windows MetaEditor compilation, and supported native policy tests. |
| `tests/mt5/` and `development/EA/tests/` | MT5 package/demo validation and native MQL5 policy/runtime tests. |
| `docs/MT5_TESTER_TIMEZONE_PROVENANCE.md` | Rules for timestamp provenance in native Strategy Tester exports. |

The flattened EA is generated from `development/EA/`; do not hand-edit `MidasTouch2.mq5`. The local EA include closure is in this repository. Its only external compile-time include is MetaTrader's standard `Trade/Trade.mqh` library supplied by the installed MT5 terminal. Compiled `.ex5` files are generated locally and are not source-controlled.

### Imported upstream project and supporting services

`backend/source/` contains the full 495-file upstream project snapshot at commit `52d737237c08f36d668853312f643cb74d4548da`: FastAPI services, PostgreSQL migrations, Telegram bridge, deployment manifests, tests, research tooling, documentation, and the original upstream EA. `backend/SOURCE_REVISION.md` records its provenance and the small number of target-specific reconciliations.

The nested `backend/source/EA/` tree is an upstream reference snapshot, **not a second active EA build target**. The active root EA remains `development/EA/` plus the generated `MidasTouch2.mq5`. Workflows under `backend/source/.github/` are imported provenance only; GitHub Actions executes workflows from the root `.github/workflows/` directory.

### Research and external validation tools

- `research/`: StrategyTune research reports and archived candidate artifacts. Gold M15 StrategyTune source/metadata for v2.6, v2.7, v2.12, and v2.13 are preserved under `research/strategytune/gold-m15/`.
- `backend/source/tools/`: imported upstream validation, MQL5 architecture, MT5 variant-comparison, walk-forward, trailing-stop experiment, and deal-ledger analysis tools.
- `backend/source/medis_touch/`: research/reference implementation; it is not the live MT5 EA or the production execution bridge.
- `backend/source/telegram-bridge/`: FastAPI execution-ledger and signal bridge source, migrations, and service tests.

StrategyTune proxy results are not native MT5 Strategy Tester results. They do not prove parity for the EA's broker adapter, trailing-stop amendments, margin checks, commissions, slippage, swaps, or execution-ledger behavior. The Gold v2.13 report records this boundary and its negative 2025 expectancy; it is research evidence, not live-trading approval.

Use the repository's source-consistency and MT5 compile workflows for changes. Do not promote StrategyTune parameters into the live EA without a separate code-level parity review, native MT5 Strategy Tester validation, broker-demo execution evidence, and the release gates above.
