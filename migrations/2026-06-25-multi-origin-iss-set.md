---
title: Multi-origin iss-set tolerance (one box, many URLs)
date: 2026-06-25
status: active
originating-pr: parachute-hub#692
---

# Migration: multi-origin `iss`-set tolerance

**Decided:** 2026-06-25 (Aaron, onboarding-streamline round-2, decision item 7).
**Context:** the Render-like zero-SSH DO setup (Caddy-direct, `<ip>.sslip.io` +
optional custom domain) means a single box is reachable on **several URLs at
once**. Today resource servers (vault, scribe via `@openparachute/scope-guard`)
pin the token's `iss` claim to ONE exact origin (`PARACHUTE_HUB_ORIGIN`), so a
token minted when the hub was reached via URL-A is **rejected** when the
resource is reached via URL-B — even though it's the same box, same key.

## The shift

The signing **key is stable and origin-independent**; the only thing the
canonical origin drives is the `iss` string. So this is purely about **widening
`iss` VALIDATION from one string to a SET** — no key work, no `aud` work
(`aud=vault.<name>` is static, origin-independent).

The precedent: **hub#516** already solved this for the hub's OWN credentials
(operator token / SPA host-admin token) — verify the signature FIRST (proves
only this hub's key signed it), then accept `iss` if it's in a hub-controlled
SET (`buildHubBoundOrigins` in `src/origin-check.ts`). This migration extends
that same set-tolerant decision to the **OAuth / resource-server** path.

**Mechanism:** the hub publishes its legitimate-origin SET (issuer ∪ loopback
aliases ∪ expose-state public origin ∪ platform origin) to each supervised
module via a new comma-separated env var `PARACHUTE_HUB_ORIGINS`, alongside the
existing single `PARACHUTE_HUB_ORIGIN` (kept for back-compat). scope-guard
gains an optional `allowedIssuers` resolver; vault + scribe adapters read
`PARACHUTE_HUB_ORIGINS` and pass it through.

## NON-NEGOTIABLE security invariant

The accepted-issuer SET is **HUB/OPERATOR-controlled ONLY** —
`buildHubBoundOrigins` output (issuer, loopback, expose-state, platform). It
must **NEVER** include an unvalidated request `Host` / `X-Forwarded-Host`.
Accepting `iss ∈ hub's-own-legitimate-set` is safe ONLY because the JWKS
signature verify runs FIRST and unconditionally — it proves the hub minted the
token regardless of `iss`. The set is a belt-and-suspenders allowlist layered
on top of the signature gate, never a substitute for it.

## Code references — hub (originating PR, this repo: parachute-hub)

- [x] `packages/scope-guard/src/validate.ts` — add optional
      `allowedIssuers?: () => readonly string[] | undefined` to
      `CreateScopeGuardOptions`; pass the resolved set to jose's `issuer`
      option (already accepts `string | string[]`). Single-origin config =
      byte-identical exact-match (back-compat). The canonical `hubOrigin` stays
      the JWKS-fetch + revocation-endpoint pin (single string).
- [x] `packages/scope-guard/package.json` — `0.4.1` → `0.5.0` (additive minor).
- [x] `src/hub-origin.ts` — `HUB_ORIGINS_ENV` constant +
      `serializeHubOrigins` / `parseHubOrigins` helpers (comma-separated wire
      form).
- [x] `src/vault-hub-origin-env.ts` — `buildHubOriginsEnvValue` (assembles the
      set from `buildHubBoundOrigins`); `persistVaultHubOrigin` /
      `clearVaultHubOrigin` write/clear `PARACHUTE_HUB_ORIGINS` alongside the
      single var (daemon-boot path).
- [x] `src/commands/serve-boot.ts` (`buildModuleSpawnRequest`) — inject
      `PARACHUTE_HUB_ORIGINS` into supervised-child env.
- [x] `src/api-modules-ops.ts` (`spawnSupervised`) — same injection on the
      `/api/modules/:short/start` path (keep the two spawn sites in sync).
- [x] `src/jwt-sign.ts` (~`issuer` field jsdoc) — note the mint stays
      per-request; the canonical configured origin is minted AND is in the
      published set, so mint/validate already align (no clamp added).
- [x] Tests: `packages/scope-guard/src/__tests__/validate.test.ts`
      (iss=A/B/C against {A,B}, single-origin back-compat, empty set, per-call
      re-eval, hubOrigin-always-present); `src/__tests__/hub-origins-env-set.test.ts`
      (assembly + the "request Host never enters the set" invariant);
      `src/__tests__/serve-boot.test.ts` + `vault-hub-origin-env.test.ts`
      (env injection).

## Mint side (decision recorded — no change)

- [x] Hub mints `iss` per-request via `resolveIssuer` (tier 4 = request origin,
      and it already REFUSES `X-Forwarded-Host` for its own issuer derivation —
      `hub-server.ts:~1606`). **No mint change.** In the intended Caddy /
      zero-SSH deploy the canonical origin is configured (`PARACHUTE_HUB_ORIGIN`
      / DB `hub_origin`), so `resolveIssuer` returns it for every request AND it
      is a member of the published set → mint and validate already align. The
      unconfigured-multiple-public-domains case (clamp `resolveIssuer` to the
      bound set) is a riskier follow-up that would alter OAuth-discovery URL
      derivation — deliberately deferred. If pursued, the safe shape is: mint
      `iss` = request origin only when it's in the bound set, else canonical.

## Code references — follow-on PRs (separate repos, NOT in the hub PR)

- [ ] **parachute-vault** `src/hub-jwt.ts` — bump `@openparachute/scope-guard`
      `^0.4.1` → `^0.5.0`; add `allowedIssuers: () => parseHubOrigins(process.env.PARACHUTE_HUB_ORIGINS)`
      to the `createScopeGuard({ ... })` call (a tiny `parseHubOrigins` helper:
      split on `,`, trim, strip trailing slash, drop empties). Leave
      `hubOrigin` / `jwksOrigin` as-is. rc-bump + reviewer-gated.
- [ ] **parachute-scribe** `src/hub-jwt.ts` — same change: bump scope-guard dep
      (`^0.2.0` → `^0.5.0`) + add the `allowedIssuers` resolver reading
      `PARACHUTE_HUB_ORIGINS`. (scribe's guard is `createScopeGuard({ hubOrigin })`
      only — single line to extend.) rc-bump + reviewer-gated.

## Publish / version

- [x] scope-guard `0.5.0` published via the existing `release.yml` Trusted
      Publishing job — tag `scope-guard-v0.5.0` pushed 2026-06-25 (separate tag
      namespace from hub's `v*`). vault/scribe consume it from npm (`^0.5.0`)
      in their follow-on adapter PRs. (Library cut, not a deployed-module
      @latest release — the rc-soak governance is preserved at the module level:
      hub/vault/scribe all stay `@rc`.)

## Doc references

- [x] `src/hub-origin.ts` / `src/vault-hub-origin-env.ts` jsdoc — the security
      invariant is stated at the validation/assembly sites (in-code).
- [ ] `patterns/oauth-scopes.md` (or the hub-as-issuer pattern doc) — a line
      that resource servers accept `iss` ∈ the hub's published origin set, not a
      single origin, when on scope-guard ≥0.5.0. (Add when convenient — the
      in-code jsdoc is authoritative meanwhile.)
