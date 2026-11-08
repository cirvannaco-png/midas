# Integrated trading architecture audit

Audit baseline: Midas root EA source plus the pinned Midas-touch2 backend snapshot
at upstream commit 77b180f97855a315d8b62396a50dff8a44643e19.

This is an implementation audit, not a profitability certification.

## 1. Regime intelligence and strategy eligibility

### Already implemented

The root EA does route executable setup construction by regime. The active path is
CTradeDecision.BuildAuthoritativeStrategy() in
development/EA/includes/Trading/StrategyTradeZone.mqh:

- TRENDING can select the momentum/breakout family. Its builder requires an
  expansion/liquidity breakout class, a recent directional BOS, and a maximum
  0.75 ATR chase distance.
- RANGING can select mean reversion for value-fade or level-rejection evidence.
  Its builder requires a valid value-area edge or a nearby support/resistance
  reference.
- TRANSITION can select key-level reaction for rejection, retest, failed-break,
  or absorption evidence.
- An undefined regime abstains. Each non-SMC strategy must successfully build
  its own geometrically valid setup or the candidate is rejected.
- SMC remains a competing baseline; the strategy router compares candidate
  scores and may use environment-strategy memory.

CRegimeDetector combines BOS-backed trend state, volatility regime, and market
phase. It deliberately treats uncertain conditions as TRANSITION rather than
forcing them into trend or range.

### Remaining work

1. Trend continuation and breakout are currently combined as
   STRATEGY_MOMENTUM_BREAKOUT. Split their attribution and validation cohorts
   before claiming independent evidence for each.
2. CScoringEngine owns a CStrategySelector, while CTradeDecision also contains
   a second SelectPeerStrategy implementation. The scoring diagnostic selection
   is reset in PopulateStrategyReads before the executable router runs. This
   duplicate policy is a drift risk; establish one authoritative selector.
3. Validate each strategy/regime pair independently using completed positions,
   not raw close-deal rows. Report sample size, expectancy in R, profit factor,
   Wilson interval, MAE/MFE, holding time, costs, and drawdown.
4. The market-phase input is explicitly described in code as a heuristic.
   Measure classification stability and false transitions before increasing
   its authority.
5. Keep the existing router observable in shadow mode during ablations. Do not
   add new hard gates or change default weights until locked OOS evidence passes.

## 2. Portfolio-wide risk and margin

### Already implemented

The EA PortfolioManager aggregates stop risk across open positions and pending
orders for its configured magic number, across symbols. Unknown stop geometry
or uncomputable risk fails closed. It also applies per-symbol and broad
correlation-group position-count limits.

The backend execution ledger provides atomic, PostgreSQL-locked reservations
per portfolio_key, a hard 3R reservation ceiling, position synchronization,
pending-order synchronization, deal-event ingestion, and reconciliation. This
is the correct foundation for one authoritative admission ledger; the backend
never submits broker orders.

### Remaining work

1. The EA portfolio key currently includes broker server, account login, and
   magic number. Different Midas magic numbers therefore create separate books.
   Introduce an explicit account-level Midas portfolio ID shared by all symbols
   and Midas instances that must share risk.
2. The EA PortfolioManager does not calculate proposed margin or check
   ACCOUNT_MARGIN_FREE. No OrderCalcMargin call was found in the root EA.
3. The backend reserve request carries risk in R and an empty factor map. Its
   active reservation sum does not yet enforce a fresh broker margin snapshot
   or factor/correlation budget.
4. The backend portfolio_risk.py module is a deterministic reference evaluator;
   it is not wired into execution admission. Its correlation matrix must be
   sourced from validated, time-aligned returns, not guessed constants.
5. Extend admission atomically to account-wide open-position risk, pending
   orders, unfilled reservations, factor exposure, margin used, free margin,
   and a configurable margin safety buffer. The EA should provide
   OrderCalcMargin results and a timestamped account snapshot; stale or missing
   snapshots must reject new exposure.
6. Ensure reservations are not released merely because a lease expires or a
   send times out. Broker evidence and reconciliation remain mandatory.

The existing local PortfolioManager remains a useful secondary guard, but it
must not compete with or replace the backend's single authoritative ledger.

## 3. Strategy/regime attribution and position outcomes

### Already implemented

- TradeDecision records strategy, regime, strategy/model/calibration versions,
  decision fingerprint, and environment key.
- SignalPublisher emits strategy and regime.
- Backend Signal and SignalOutcome models store strategy and regime.
- ExecutionLedger links a signal to broker order/deal/position identities.
- ExecutionDealEvent stores immutable deal cashflows keyed by broker position.
- OutcomeTrackerLive aggregates fills and partial exits before publishing a
  resolved signal outcome.
- position_ledger_metrics.py collapses partial exit rows into completed
  position-level results.

### Remaining work

A decision may create multiple execution legs and broker positions. A single
signal-level outcome is not a substitute for one outcome per broker position.
Create a canonical join:

portfolio_key + broker_position_id
  -> execution ledger request/leg
  -> signal_id / decision_id
  -> immutable strategy, regime, versions, and entry fingerprint
  -> all deal events for that position
  -> one final position-level outcome after the position is fully closed.

Reject conflicting strategy/regime lineage for one position. Partial closes
must contribute cashflows to the same position outcome and never become
independent wins. Report strategy-by-regime metrics from completed positions.

## 4. Walk-forward validation and promotion

The backend snapshot includes strict walk_forward.py, oos_firewall.py,
position_ledger_metrics.py, regime_allocation.py, cost-stress and matched
variant tooling. These are useful validation components, not evidence that
the requested integrated strategy has already passed validation.

Required promotion protocol:

1. Freeze strategy definitions, regime labels, symbol taxonomy, costs, and
   feature/model versions before each experiment.
2. Build chronological train, validation, and locked OOS folds. No tuning,
   threshold selection, or calibration may inspect locked OOS outcomes.
3. Evaluate trend continuation, breakout, mean reversion, key-level reaction,
   and SMC baseline separately, then test the combined router.
4. Repeat across multiple instruments and asset classes with broker-specific
   contract sizes, spreads, commissions, swaps, and slippage.
5. Aggregate fills and partial exits to completed broker positions before
   computing performance. Report no-fill and ambiguous outcomes separately.
6. Require adequate samples and uncertainty bounds. A high win rate alone is
   insufficient; include net expectancy, profit factor, max drawdown, exposure,
   margin utilization, and robustness across folds.
7. Promote one policy change at a time. Keep the previous policy as champion
   and reject changes that only work in one symbol or market window.

## Release status

- Regime-first routing: implemented; independent family validation remains.
- Account-wide portfolio budget: partial; magic-scoped risk exists, margin and
  cross-magic consolidation remain.
- Strategy/regime lineage: signal-level fields exist; per-position attribution
  across multi-leg executions needs a canonical join and tests.
- Walk-forward tooling: present; integrated multi-instrument locked-OOS
  evidence is not yet certified.
- Live trading promotion: not approved by this audit.
