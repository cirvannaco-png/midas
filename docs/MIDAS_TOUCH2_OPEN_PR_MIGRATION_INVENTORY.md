# Midas-touch2 open pull request migration inventory

**Destination:** `cirvannaco-png/midas`  
**Source:** `cirvannaco-png/Midas-touch2-`  
**Audit date:** 2026-11-23

## Scope

The merged `main` history through `6dad8a00a522e3fd507b0f2669de47bcb47e43ee`
has been compared with the last imported upstream snapshot and refreshed in
`backend/source/`. That comparison found two commits and three changed files.

The source repository also has 17 open pull requests. They are not in the merged
`main` history and therefore are not included in the mainline snapshot refresh.
They are listed here to prevent accidental omission. Each must be diffed against
its base, checked for overlap with Midas's newer canonical implementation, and
classified as: (a) safe to migrate, (b) research/provenance only, (c) superseded,
or (d) blocked pending evidence. Draft or behavior-changing risk work must not
be promoted merely because it exists on a source branch.

## Open pull requests requiring individual review

| Source PR | Subject | Initial migration treatment |
|---:|---|---|
| [#169](https://github.com/cirvannaco-png/Midas-touch2-/pull/169) | Gold trend-only candidate and holdout evidence | Research-only; migrate evidence and caveats, not live parameters |
| [#168](https://github.com/cirvannaco-png/Midas-touch2-/pull/168) | Gold payoff ablation and no-promotion decision | Research evidence; preserve no-promotion decision |
| [#167](https://github.com/cirvannaco-png/Midas-touch2-/pull/167) | Margin-aware portfolio admission | Behavior-changing execution/risk code; require full API/EA/DB and demo review |
| [#150](https://github.com/cirvannaco-png/Midas-touch2-/pull/150) | Broker-neutral validation and tester timestamp provenance | Review for migration; likely overlaps existing Midas broker-neutral architecture |
| [#147](https://github.com/cirvannaco-png/Midas-touch2-/pull/147) | Production auth, AI execution, position reconciliation and OOS isolation | Security-critical; migrate only after workflow/OIDC and execution-authority review |
| [#144](https://github.com/cirvannaco-png/Midas-touch2-/pull/144) | 50% daily-loss cap research protocol | Do not promote the 50%/55% risk settings; preserve as a rejected/high-risk proposal unless separately approved |
| [#143](https://github.com/cirvannaco-png/Midas-touch2-/pull/143) | Separate small-account and large-account risk profiles | Risk-policy change; compare against canonical Midas risk limits before migration |
| [#118](https://github.com/cirvannaco-png/Midas-touch2-/pull/118) | Dedicated paid production PostgreSQL database | Infrastructure proposal; verify actual provider provisioning and billing state before adoption |
| [#115](https://github.com/cirvannaco-png/Midas-touch2-/pull/115) | Fail-closed MT5 diagnostic parity evidence audit | Review research/evidence tooling and preserve non-promotion gates |
| [#112](https://github.com/cirvannaco-png/Midas-touch2-/pull/112) | Diagnostic order-flow evidence and research validation | Draft research; no trading-behavior promotion without evidence |
| [#76](https://github.com/cirvannaco-png/Midas-touch2-/pull/76) | Payoff asymmetry and entry precision research candidate | Research-only; inspect exact branch diff and locked-OOS limitations |
| [#38](https://github.com/cirvannaco-png/Midas-touch2-/pull/38) | Dual-lane risk governor and position-level MT5 metrics | Behavior-changing risk work; preserve only after native MT5 and risk review |
| [#35](https://github.com/cirvannaco-png/Midas-touch2-/pull/35) | Capacity controls and weekday trade qualification | Risk/capacity behavior; compare to current Midas limits and tests |
| [#34](https://github.com/cirvannaco-png/Midas-touch2-/pull/34) | Hierarchical decision engine hardening | Architecture change; compare to current active strategy/router lineage |
| [#33](https://github.com/cirvannaco-png/Midas-touch2-/pull/33) | Feature-flagged environment hard-loss firewall | Research feature flag; require ablation and default-off verification |
| [#32](https://github.com/cirvannaco-png/Midas-touch2-/pull/32) | Inducement structural provenance | Telemetry; inspect compatibility and lineage |
| [#30](https://github.com/cirvannaco-png/Midas-touch2-/pull/30) | Causal SMC FVG loss-reduction candidate | Research candidate; preserve default/promotion boundary |

## Completion rule

This inventory is not proof that the open PRs have been migrated. The migration is
complete only when every source PR/branch has a recorded disposition and every
approved change has been ported, tested and reviewed in the canonical Midas
repository. Superseded or unsafe work should be documented as intentionally not
promoted rather than copied into the active EA.
