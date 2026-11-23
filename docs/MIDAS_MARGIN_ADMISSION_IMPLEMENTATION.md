# Midas account-wide margin admission

Status: implemented in the migration branch; local bridge tests pass, but PostgreSQL concurrency, Windows MetaEditor compilation, and broker-demo execution remain release gates.

## Contract

- All Midas instances on the same broker server and account share one ledger portfolio key (`server:login:midas`). Strategy magic numbers and chart identity remain in decision request IDs, not in the account risk-book key.
- Each new leg requires broker-calculated `OrderCalcMargin`, a positive `ACCOUNT_MARGIN_FREE` snapshot, UTC snapshot epoch, and account currency. Missing, non-finite, non-positive, stale, future, or currency-inconsistent evidence fails closed.
- Snapshot freshness is limited to 10 seconds; timestamps more than 2 seconds in the future are rejected.
- The default free-margin buffer is 20%, configurable through `MIDAS_MIN_FREE_MARGIN_BUFFER_RATIO` (accepted range 0.05–0.90). Invalid configuration prevents bridge startup.
- The account-scoped PostgreSQL advisory transaction lock serializes portfolio admission. Existing active heat reservations and unreflected margin are checked inside the same transaction before new ledger and reservation rows are flushed.
- `RESERVED`, `CHECKED`, `SENT`, and `RECOVERING` margin remains reserved. A broker-observed `ACKED` pending order or `FILLED` position is counted only when its durable transition time is later than the supplied free-margin snapshot. That avoids double counting broker exposure already reflected in a newer snapshot while retaining post-snapshot fills/orders.
- If a post-snapshot active order/fill lacks margin or transition-time evidence, admission fails closed. Conflicting currency evidence also fails closed.
- Pending-order startup reconciliation now transmits broker-calculated required margin and account currency. A live broker order that contradicts a terminal/filled ledger state is rejected for manual reconciliation rather than silently resurrected or hidden.
- The reserve API and authenticated health response require protocol marker `midas-account-margin-v1`. The EA verifies that marker before opening admission and verifies it again in each successful reserve response. An older bridge that ignores the new request fields cannot falsely appear margin-capable; missing protocol confirmation keeps entries blocked.
- The existing 3R portfolio heat ceiling, stop-risk policy, daily-loss policy, and protective-stop behavior are unchanged. No strategy thresholds or trade-frequency targets were changed.

## Validation performed

- Bridge tests: run with `cd backend/source/telegram-bridge && PYTHONPATH=.. python -m pytest -q`. Root GitHub Actions CI starts an isolated PostgreSQL 16 service and sets `MIDAS_TEST_POSTGRES_URL`, so the concurrency test runs instead of being skipped in CI.
- Static EA package checks: `python scripts/build_single_file.py` followed by `python scripts/validate_single_file.py`.
- Root static regression: `python -m pytest tests/research/test_margin_admission_contract.py -q`.

The local test environment is Linux and cannot provide native MetaEditor evidence. The local run skipped the PostgreSQL concurrency case because it had no database service; root CI now supplies an isolated PostgreSQL 16 service and executes that case. No broker demo or live-trading claim is made by this document.
