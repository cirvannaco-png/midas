# MidasTouch2 — Portfolio Opportunity Model and Allocator Specification

**Status:** Architecture specification based on the consolidated EA source. Not implemented in the production EA.  
**Source audited:** `MidasTouch2.mq5` on `build/single-file-staging`  
**Research evidence:** `FAMILY_PORTFOLIO_WALK_FORWARD.md`  
**Decision:** Do not equate the existing portfolio risk gate with a multi-symbol opportunity engine.

## 1. Audit finding: what exists today

The consolidated EA contains a useful `CPortfolioManager`, but its current scope is narrower than the requested portfolio model.

| Area | Current source behaviour | Gap |
|---|---|---|
| Risk aggregation | Sums stop-based risk for open positions and pending orders with the configured `InpMagicNumber` | It does not include other magic numbers or manual positions in its risk sum |
| Position limits | Enforces per-symbol and coarse correlation-group position counts | Count caps do not measure signed factor exposure or empirical correlation |
| Correlation groups | Uses symbol-name buckets for crypto, metals, indices and a default FX bucket | Broker suffixes/aliases and cross-asset relationships can be misclassified; there is no rolling covariance model |
| Open risk | Uses remaining distance to each position's current stop; unknown stop geometry fails closed for included positions | Planned stop risk is not a bound on gap, slippage or liquidation loss |
| Pending orders | Includes active pending-order stop risk for included magic-number orders | No durable cross-instance reservation is visible in this manager |
| Margin | No portfolio-level projected margin requirement is calculated in `CPortfolioManager::AllowNewTradeBatch` | Available margin is not an explicit allocation constraint in the current manager |
| Signal universe | `CTFContextPool` is configured with `_Symbol`; its contexts are multiple timeframes for that one symbol | It is not a multi-symbol context pool |
| Entry generation | `OnTick` calls `GenerateBuySetup()` and `GenerateSellSetup()` on the chart-symbol decision engine | The EA does not scan and rank a configured multi-symbol watchlist in one engine loop |
| Multi-trade option | `InpEnableMultiTrade` builds a two- or three-leg batch for the current chart symbol | Multiple legs are not multiple instruments |
| Daily objective | The minimum qualified trade count logs progress and does not generate entries | This behaviour must remain diagnostic-only |

**Precise conclusion:** MidasTouch2 has a same-magic, cross-symbol *risk gate* that can see trades placed by multiple chart instances using that magic number. It does not yet have a centralized multi-symbol *opportunity selector*. Separate chart instances may each produce signals for their chart symbol, but they do not share a candidate queue, rank all symbols at one decision time, or atomically reserve one common budget before concurrent submissions.

The account-level daily loss/drawdown guard is separate from the magic-filtered portfolio stop-risk calculation. It should remain a global circuit breaker.

## 2. Required architecture

Build a central portfolio service around four distinct stages:

1. **Symbol Context Registry** — configured instrument universe, broker-specific symbol resolution, per-symbol market-data readiness, session calendars, tick/contract metadata, trading permissions and quote freshness.
2. **Candidate Engine** — independent per-symbol/per-family strategy evaluation, regime eligibility, calibrated outcome probability, stop proposal, spread/cost estimate and timestamped feature snapshot.
3. **Opportunity Allocator** — compares candidates across instruments on common account-currency and net-R units, then ranks only admissible candidates.
4. **Portfolio Risk and Execution Reservation** — checks existing positions, pending orders, in-flight reservations, factor exposure, stressed stop loss and margin before an order is submitted. Successful fills reconcile the reservation; rejected or expired orders release it.

The portfolio coordinator must run independently of chart attachment. A chart is a data/visualization source, not the authoritative scheduler for the entire account.

## 3. Candidate contract

Every candidate must carry, at minimum:

- Unique candidate ID and idempotency key: account, symbol, timeframe, family, side, signal-bar time and strategy version.
- Symbol's broker-resolved name, quote currency, contract size, tick size/value and price precision.
- Strategy family: SMC/structure, sweep-reclaim reversal, trend continuation, breakout, mean reversion or another explicitly versioned family.
- Regime label and regime confidence from information available at candidate time; transitions are not silently assigned to trend or range.
- Raw score, calibrated probability, sample count, calibration version and calibration freshness. Raw confidence must never be described or consumed as a calibrated win probability.
- Entry reference, structural invalidation, proposed stop, stop distance in ATR and pips/points, spread/ATR and expected execution cost.
- Family-specific exit plan: TP1, partial quantity, TP2, break-even movement, runner trail, maximum hold and time/session exits.
- Estimated loss in account currency at the current stop, estimated loss under a stressed gap/slippage scenario, expected net R and candidate expiry time.
- Feature snapshot and later linkage to the original opening fill and all partial-close records.

Candidate generation and candidate selection are separate. Each family can propose a candidate; the allocator, not the family implementation, decides whether it receives account risk.

## 4. Entry-family and regime routing

Use a regime state machine with three labels:

- **Range / mean-reversion eligible**
- **Directional trend / continuation eligible**
- **Transition / uncertain**

Each family has an explicit eligible-regime policy, independently validated on training and untouched holdouts. Do not let a high setup score override a regime veto. Do not force a trade when no family is eligible.

The current StrategyTune 8/21-mean-gap proxy (normalized by ATR) is a research feature only. It is not a replacement for the production EA's regime/phase classifier. The production classifier must be measured against future outcomes and versioned. Transition should remain a separate state until its own sample supports a routing decision.

## 5. Opportunity ranking

Rank admissible candidates by a conservative estimate of net expectancy rather than raw score or the number of entries available.

A starting metric is:

`ExpectedNetR = p(win) × avgWinR − (1 − p(win)) × avgLossR − expectedCostsR − gapReserveR`

Where:

- `p(win)` is a calibrated, family-and-regime-specific probability with adequate sample support.
- `avgWinR` and `avgLossR` are estimated from full-position outcomes, never individual partial-close rows.
- `expectedCostsR` includes spread, commission, swap/financing and a conservative slippage estimate.
- `gapReserveR` is a stress allowance based on instrument/session-specific gap behaviour; it is not assumed to be zero.

Use uncertainty penalties or conservative bounds when calibration samples are sparse. A candidate with unknown probability is not automatically assigned a high score. The allocator should prefer no trade over a false precision ranking.

## 6. One authoritative portfolio budget

The allocator must calculate exposures over the complete account, not only positions bearing one EA magic number, unless the operator explicitly configures an isolated sub-portfolio.

### Required exposure inputs

- All open positions on the account, with symbol, side, volume, entry, current stop, current unrealized P&L, magic and account-currency stop-risk estimate.
- All pending orders, including their contingent margin and risk.
- All in-flight reservations created by Midas instances but not yet reflected as broker positions/orders.
- Available margin, used margin, margin level, projected margin after each candidate batch and broker stop-out buffer.
- Currency-factor exposures (USD, EUR, JPY, GBP, CHF, CAD, AUD and other supported currencies), not just instrument labels.
- Asset and macro factors (equity beta, metals, energy, crypto) and directional concentration.
- Stress loss under simultaneous adverse moves, weekend reopening gaps, spread widening and correlated liquidation.

A position or pending order with missing/invalid protection or uncomputable exposure must be classified as **unknown**, not zero. The account policy decides whether unknown external exposure blocks all new automated risk; the safe default for the strict profile is fail-closed.

### Correlation handling

Do not rely solely on static categories such as `FX`, `METALS` and `INDICES`. Maintain both:

- Deterministic factor exposure rules (e.g. a long EURUSD position has short-USD factor exposure).
- Rolling return correlation / covariance estimates with data-sufficiency checks, shrinkage and regime awareness.

When estimates are unavailable, stale or unstable, use conservative group limits and stress scenarios. Do not assume correlation is zero.

### Margin and risk admission

A candidate batch passes only when all of these are true:

1. Its stop-risk plus existing and reserved risk stays within the shared account-level loss budget.
2. Its group/factor exposure stays within concentration limits.
3. Its projected margin remains below a configurable utilization ceiling and above broker-required stop-out safety buffers.
4. Its position count, per-symbol count and per-family/regime count limits remain valid.
5. All stop geometry, quote freshness, account currency conversion and volume-step checks pass.
6. The candidate remains current and has not already been consumed by another EA instance.

A 0.10% nominal stop allocation is not a hard-loss guarantee. Stressed gap loss and available margin are separate constraints.

## 7. Atomic reservations across chart instances

The current `CPortfolioManager` reads the live terminal position/order lists. That is useful, but multiple chart instances can evaluate the same available risk before either has submitted its order.

Implement a terminal-wide atomic reservation protocol:

1. Generate an idempotent candidate ID.
2. Acquire a short-lived account-level portfolio lock using an atomic terminal-global-variable compare-and-swap or equivalent serialized service.
3. Re-read open positions, pending orders, existing reservations, account equity and margin while holding the lock.
4. Reserve stop-risk, stressed-risk and projected margin for the proposed candidate batch.
5. Submit the order and write the broker response/ledger identity.
6. Reconcile the reservation to actual broker exposure after fill; release it on rejection, cancellation or expiry.
7. On restart, reconstruct reservations from durable order/position state and expire orphan reservations only after reconciliation.

A simple read-then-send check without an atomic reservation is not sufficient for a multi-chart account allocator.

## 8. Three winning positions per day: measure opportunity, never force it

The requested three-winning-position target is a reporting objective, not an admission rule.

Report separately:
- candidates generated per symbol/family/regime;
- candidates rejected by regime, quality, spread, session, stale quote, risk, correlation and margin;
- candidates admissible but displaced by a higher-ranked candidate;
- orders submitted, fills, full positions closed, open positions at day end;
- net winning positions and daily shortfall.

Never lower quality gates, widen risk or open a trade merely because the daily count is below three. A no-trade day is a valid output. A target should be evaluated over weekly/monthly opportunity distributions, not forced every day.

## 9. Portfolio outcome ledger

Use one immutable position identity from original opening fill through every partial close and final close. Store:

- parent position / opening fill identifier;
- symbol, family, regime, direction and entry-time feature snapshot;
- initial risk money, initial stop and every subsequent stop modification;
- each partial fill, realized P&L and exit reason;
- final aggregate realized P&L and full-position R;
- unrealized exposure at test boundary;
- commission, swap, spread and slippage;
- maximum favorable/adverse excursion and holding time;
- correlation/factor exposure at entry and at peak portfolio exposure.

Calculate win rate only after the position is fully closed. Keep close-row metrics as execution diagnostics, never as strategy win rate.

## 10. Validation protocol

### Phase A — unit and integration tests

- Symbol resolver with broker suffixes, unavailable symbols and stale ticks.
- Per-symbol data warm-up and one-new-bar scheduling.
- Candidate expiry and duplicate suppression.
- Stop-risk and account-currency conversion for each instrument.
- Missing-stop and unknown external exposure fail-closed tests.
- Pending-order and reservation accounting.
- Two chart instances attempting to spend the same remaining budget.
- Order rejection, partial fill, partial close, reconnect and restart reconciliation.
- Margin exhaustion, broker stop-out level and minimum-volume rejection.
- Friday cutoff, weekend market closure, Monday reopening gap and crypto-weekend behaviour.

### Phase B — single-symbol family tests

Select entry quality and regime gates on training periods only. Validate stop behaviour and partial-exit plans separately. Group outcomes by original opening fill and include marked-to-market open positions at each fold boundary.

### Phase C — synchronized multi-symbol portfolio tests

Use MT5 Strategy Tester with all selected symbols' real-tick histories and synchronized portfolio state. Model commission, swap, spread, slippage and gaps. Do not add independent per-symbol account returns and call the sum a simultaneous portfolio result.

Report:
- net P&L and return on one shared starting balance;
- full-position win rate, PF, expectancy and average win/loss R;
- max equity drawdown and intraday loss;
- peak aggregate stop-risk, stress-risk, margin utilization and factor concentration;
- correlation and simultaneous signal overlap;
- daily winning positions and no-trade days;
- order rejection, reservation collision and unprotected-position counts.

### Phase D — rolling walk-forward

For each fold:
1. Fit/calibrate candidate quality and family/regime policy on training data.
2. Lock code, inputs and thresholds.
3. Run the next untouched period and publish results without tuning it.
4. Roll forward and repeat.
5. Reject configurations that only work in one instrument, one regime or one window.

The already inspected April through July 2026 periods are not clean future holdouts for the next candidate. Keep August 2026 untouched until the candidate, parameters and hypotheses are frozen; then use it as the next chronological holdout.

## 11. Delivery order

1. Preserve the current consolidated EA source and its production risk settings.
2. Build a portfolio simulator / reservation API separately from entry logic.
3. Prove atomic account risk and margin admission with multi-instance tests.
4. Add symbol contexts and a candidate queue, initially with a small, explicitly configured universe.
5. Add family/regime routing and calibrated expected-net-R ranking.
6. Add synchronized portfolio ledger and MT5 multi-currency backtests.
7. Promote only after the full risk, operational and rolling holdout gates pass.

## 12. Non-negotiable controls

- No forced entries to meet the three-winner objective.
- No artificial win-rate inflation from partial exits.
- No assumption that stop risk bounds weekend gap losses.
- No margin or external exposure treated as zero when unknown.
- No production risk-profile increase merely to improve opportunity count.
- No live deployment based only on StrategyTune or this research model.
- No merge into the production branch until compilation, Strategy Tester, broker demo, ledger and restart/recovery evidence are complete.
