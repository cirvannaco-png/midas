# Midas production authentication — security review and implementation gate

Status: design reviewed; implementation intentionally deferred until Midas has a confirmed production service origin and root-level deployment workflow.

## Why source PR #147 is not reusable as-is

The source branch's OIDC trust is bound to `cirvanna-co-png/Midas-touch2-`, audience `midas-touch2-production`, and `https://midas-touch2.onrender.com`. Those identifiers are wrong for the canonical Midas repository. Its verifier checks signed GitHub Actions claims for issuer, audience, repository name, branch, environment, event and workflow path, but it does not bind immutable repository/owner IDs and does not consume a one-time `jti`. A still-valid token can therefore be replayed during its validity window. The route allowlist also includes mutating maintenance/retry POST endpoints, which must not be inherited without a separate Midas-specific threat review.

## Midas immutable identity

- Canonical repository: `cirvanna-co-png/midas`
- GitHub repository ID: `1449162974`
- GitHub owner ID: `275909084`
- Required future audience: a new unique value scoped to Midas, not `midas-touch2-production`
- Required subject: `repo:cirvanna-co-png/midas:environment:production`

Repository IDs above were read from the canonical GitHub repository metadata. The deployed service URL is deliberately unspecified: the root Midas repository has no root `render.yaml` and no root production-health or production-maintenance workflow. The nested `backend/source/.github` files are imported provenance and are not executed by GitHub Actions.

## Required trust contract before implementation

1. Verify GitHub OIDC signatures using the official issuer/JWKS and a pinned allowed algorithm; require `iss`, `aud`, `sub`, `exp`, `nbf`, `iat`, `jti`, `repository_id`, `repository_owner_id`, `repository`, `ref`, `environment`, `event_name`, and `workflow_ref`.
2. Require the immutable repository ID and owner ID above, exact canonical repository name, `refs/heads/main`, protected `production` environment, an explicitly allowed event, and one exact root workflow path. Reject reusable workflows or alternate refs unless separately reviewed.
3. Consume each `jti` exactly once in durable PostgreSQL storage with a unique constraint and expiry cleanup. Consumption must be atomic across service replicas and occur before route execution. In-memory replay caches are insufficient.
4. Keep the initial route allowlist to read-only health endpoints only. Do not authorize subscription enforcement, calibration, retry, execution, order submission, position modification, or strategy mutation until each route has a distinct authorization design and audit trail.
5. Keep OIDC authorization separate from the MT5 bridge API key. It must never authorize broker trading or replace execution-ledger identity, session, or consent controls.
6. Use HTTPS with a configured, verified production origin. Do not copy the source Render hostname. Configure the GitHub `production` environment and restrict it to the canonical main branch outside repository code.
7. Test wrong repo ID, wrong owner ID, wrong audience, wrong issuer, wrong subject, wrong ref, wrong environment, unapproved event/workflow, expired/not-yet-valid token, invalid signature, malformed claims, repeated `jti`, concurrent replay, and route/method mismatch. Demonstrate that rejected identities cause no side effects.

## Release decision

Do not port source PR #147's verifier or workflows until the Midas production deployment origin, root workflow, PostgreSQL replay store, and protected GitHub environment are confirmed. No OIDC secret or token should be pasted into chat or committed.
