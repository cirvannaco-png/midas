# Midas Touch 2 open-PR migration review and disposition

**Date:** 2026-11-23  
**Canonical destination:** `cirvannaco-png/midas`  
**Source repository:** `cirvannaco-png/Midas-touch2-`  
**Scope:** 17 source PRs found open during the migration audit.

This is the high-level migration disposition. All 17 open source PR heads were subsequently fetched and diffed against their recorded base commits. Exact base/head SHAs, changed-file counts, code-level findings, and final Midas decisions are recorded in [the branch-level review](MIDAS_TOUCH2_OPEN_PR_BRANCH_LEVEL_REVIEW_2026-11-23.md). The table below is a summary; it does not claim that every source PR's code was copied. Approved changes were ported only where they fit the active Midas call graph and could be regression-tested.

## Confirmed mainline migration

The source repository's merged mainline was refreshed through commit
`6dad8a00a522e3fd507b0f2669de47bcb47e43ee`. The compare from the prior imported
snapshot `52d737237c08f36d668853312f643cb74d4548da` contained two commits and three
paths: `EA/MedisTouch_v2.8.mq5`, `EA/README.md`, and
`tools/tests/test_daily_objective_dual_direction_contract.py`.

Those files are refreshed under `backend/source/`; the source revision and root
README are updated. The active Midas EA under `development/EA/` was not replaced:
it already generates BUY and SELL setups, and replacing it with the source EA
would discard Midas-specific execution, risk, position-management, and runtime
preflight behavior. A regression test protects the active modular and generated
EA from Gold-only suppression.

## Per-PR disposition

| Source PR | Subject | Midas disposition | Reason / next action |
|---:|---|---|---|
| [#169](https://github.com/cirvannaco-png/Midas-touch2-/pull/169) | Gold trend-only candidate and holdout evidence | **Research evidence only; not promoted** | Both-direction candidate: 249 opening positions, 78.31% win rate, PF 0.97, net -$1.80. Long-only ablation: 174 positions, 80.46% win rate, PF 1.18, net +$6.89. StrategyTune v6 compiles, but its corrected integrity check was not rerun; costs are incomplete and a new untouched holdout is required. Preserve the result as a warning against assuming SELL profitability. Full run IDs and raw artifact diffs remain to be imported. |
| [#168](https://github.com/cirvannaco-png/Midas-touch2-/pull/168) | Gold payoff ablation and no-promotion decision | **Research evidence only; not promoted** | 0.15R TP1 was positive in October (+$5.17) and a five-entry November partial week (+$3.71), but negative in September (-$59.56). 0.20R October and other variants failed attribution reconciliation. No robust improvement established. Preserve no-promotion decision; exact run IDs and raw artifacts remain to be imported. |
| [#167](https://github.com/cirvannaco-png/Midas-touch2-/pull/167) | Margin-aware portfolio admission | **Midas-native implementation added; release gates remain** | Account-wide portfolio identity, `OrderCalcMargin`, fresh free-margin/currency snapshot, configurable buffer, atomic advisory lock admission, durable transition timestamps, pending-order and post-snapshot fill handling, and protocol handshake are implemented with corrections to source defects. PostgreSQL concurrency, deployed bridge, MetaEditor and broker-demo evidence remain open under issue [#36](https://github.com/cirvannaco-png/midas/issues/36). |
| [#150](https://github.com/cirvannaco-png/Midas-touch2-/pull/150) | Broker-neutral validation and tester timestamp provenance | **Superseded by stronger Midas exporter** | Exact diff reviewed. Midas requires a verified broker UTC offset, emits an explicit ISO-8601 offset, records timestamp basis, and disables export when the offset is unknown. No weaker source exporter copied. |
| [#147](https://github.com/cirvannaco-png/Midas-touch2-/pull/147) | Production auth, AI execution, position reconciliation and OOS isolation | **Midas-specific security review complete; implementation deferred** | Source OIDC uses the wrong repository, audience and Render origin; it lacks immutable repository/owner ID binding and durable one-time `jti` replay protection. Midas has no root production workflow or deployment origin yet. See [security review](MIDAS_PRODUCTION_AUTH_SECURITY_REVIEW.md); no source OIDC code or route allowlist was ported. |
| [#144](https://github.com/cirvannaco-png/Midas-touch2-/pull/144) | 50% daily-loss cap research protocol | **Do not promote risk settings** | A 50% daily-loss allowance on KSh 1,500 exposes KSh 750 before costs/gaps. Research-only and not validated. Keep risk defaults unchanged; preserve only as historical rejected proposal if required. |
| [#143](https://github.com/cirvannaco-png/Midas-touch2-/pull/143) | Separate small- and large-account risk profiles | **Compare; no blind port** | Source proposal changes risk-profile semantics and limits. Midas has its own account-risk profile, KES Gold cash-risk cap and minimum-volume rejection. Map all enums/defaults and test both source and active EA before considering changes. |
| [#118](https://github.com/cirvannaco-png/Midas-touch2-/pull/118) | Dedicated paid production PostgreSQL database | **Infrastructure proposal; not applied** | Source PR reports provisioning rejected with HTTP 402 pending billing. This is not proof of a provisioned database or recovery capability. Verify Midas Render workspace, billing, database identity, backup/PITR and restore before adoption. |
| [#115](https://github.com/cirvannaco-png/Midas-touch2-/pull/115) | Fail-closed MT5 diagnostic parity evidence audit | **Research/telemetry; not promoted** | Exact diff reviewed. Adds regime-shadow and diagnostic evidence tooling; no validated incremental edge or Midas-native schema mapping. Synthetic fixtures are not market or broker evidence. |
| [#112](https://github.com/cirvannaco-png/Midas-touch2-/pull/112) | Diagnostic order-flow evidence and research validation | **Research-only; not promoted** | Exact diff reviewed. The order-pressure values are tick-direction proxies, not true exchange aggressor-side volume or footprint delta. No live signal edge established. |
| [#76](https://github.com/cirvannaco-png/Midas-touch2-/pull/76) | Payoff asymmetry and entry precision candidate | **Optional HTF stop research; disabled** | Exact diff reviewed. Weekly/monthly stop anchors use completed candles, but the master switch is false; enabling it changes live stop placement and needs matched MT5/broker-demo validation. |
| [#38](https://github.com/cirvannaco-png/Midas-touch2-/pull/38) | Dual-lane risk governor and position-level MT5 metrics | **Mostly superseded; one retcode fix ported** | Midas already uses `OrderCalcProfit`, pending-order risk, and stable position identifiers. The remaining broad `TRADE_RETCODE_PLACED` acceptance was narrowed to new market/limit requests only; management operations require completion retcodes. |
| [#35](https://github.com/cirvannaco-png/Midas-touch2-/pull/35) | Capacity controls and weekday trade qualification | **Risk/capacity change; not promoted** | Daily trade targets must never force entries. Compare profile limits, account mode, position attribution and cooldowns with Midas before any port. |
| [#34](https://github.com/cirvannaco-png/Midas-touch2-/pull/34) | Hierarchical decision engine hardening | **Architecture overlap; preserve Midas router** | Midas already has its own strategy router, environment policy, setup geometry and evidence-family logic. Do not replace it with a source decision engine. Port only isolated, demonstrably missing behavior. |
| [#33](https://github.com/cirvannaco-png/Midas-touch2-/pull/33) | Environment hard-loss firewall | **Research feature; not promoted** | Keep any candidate default-off and require strategy/environment ablation, sample adequacy and locked OOS before activation. |
| [#32](https://github.com/cirvannaco-png/Midas-touch2-/pull/32) | Inducement structural provenance | **Telemetry candidate; review required** | Potentially useful diagnostics, but source must not introduce a second authoritative detector or alter setup decisions. Compare against Midas's existing inducement/BOS provenance first. |
| [#30](https://github.com/cirvannaco-png/Midas-touch2-/pull/30) | Causal SMC FVG loss-reduction candidate | **Research candidate; not promoted** | A feature flag and structural hypothesis are not evidence of lower losses. Keep disabled until matched baseline/candidate tests and locked OOS support it. |

## Existing Midas architecture constraints

The target's compatibility matrix and integrated architecture audit establish that Midas is
not a byte-for-byte copy of the source project. In particular:

- Midas's `PortfolioManager`, `OrderManager`, `BrokerAdapter`, `PositionManager`,
  `RecoveryEngine`, `OutcomeTrackerLive`, decision store, config-sync contract and
  strategy router have target-specific behavior that must be preserved.
- The target has a backend PostgreSQL execution ledger with atomic risk-R reservations,
  but account-wide margin-aware admission remains incomplete. Issue #36 tracks this gap.
- The target exporter already requires a verified broker UTC offset and emits explicit
  timestamp offsets; do not regress to an unqualified server-local timestamp.
- Midas promotion gates are intentionally stricter than source gates in several areas.
  Do not weaken evidence completeness, OOS isolation, or risk policy to achieve superficial
  file parity.

## Exact branch review and implementation evidence

The definitive code-level record is [MIDAS_TOUCH2_OPEN_PR_BRANCH_LEVEL_REVIEW_2026-11-23.md](MIDAS_TOUCH2_OPEN_PR_BRANCH_LEVEL_REVIEW_2026-11-23.md). Margin implementation and validation limits are in [MIDAS_MARGIN_ADMISSION_IMPLEMENTATION.md](MIDAS_MARGIN_ADMISSION_IMPLEMENTATION.md). Production authentication findings are in [MIDAS_PRODUCTION_AUTH_SECURITY_REVIEW.md](MIDAS_PRODUCTION_AUTH_SECURITY_REVIEW.md).

## Completion criteria

The migration is complete only when:

1. Every source PR is either merged/closed or has an explicit Midas disposition.
2. Each approved code change is ported to the correct Midas-native module and reviewed
   against the active call graph, not merely copied by filename.
3. Every behavior change has regression tests, full CI, MetaEditor compilation and
   selected-broker MT5 demo evidence appropriate to its risk.
4. Research artifacts retain exact run IDs, source hashes, data hashes, cost assumptions,
   attribution checks and limitations.
5. Superseded or unsafe proposals are explicitly documented as not promoted.
6. `cirvannaco-png/midas` remains the only canonical development repository.
