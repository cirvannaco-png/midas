# Midas account-wide margin admission

Status: implemented in the migration branch. Root CI and Windows MetaEditor validation passed for the MQL5 implementation commit; the PostgreSQL concurrency integration test is now wired to a disposable PostgreSQL 16 service but still needs a run on the latest CI configuration. Broker-demo execution remains a release gate.

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

Windows MetaEditor compilation and deterministic native MT5 policy tests passed in [run 45239954725](https://github.com/cirvannaco-png/midas/actions/runs/45239954725) for commit `60ea185a1b628754b581ffed172df631faaf87e5`; subsequent commits changed documentation and CI configuration only. The local Linux run skipped the PostgreSQL concurrency case because it had no database service. Root CI now supplies an isolated PostgreSQL 16 service, but that latest workflow configuration has not yet been run. No full Strategy Tester or broker-demo execution is claimed.
