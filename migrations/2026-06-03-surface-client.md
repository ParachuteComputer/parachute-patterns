---
title: surface-client Phase 1 — standalone bootstrap first-class + docs truth
date: 2026-06-03
status: active
originating-pr: parachute-surface (surface-client Phase 1)
---

# surface-client Phase 1

The [surface-client design doc](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-06-03-surface-client.md) plans the work that makes a custom Parachute surface a thin `import` instead of a ~1,300-line fork. Phase 1 is "make importing actually work for a standalone external dev": the standalone Dynamic-Client-Registration (DCR) OAuth bootstrap becomes first-class, and the package stops lying about its own name, version, and tenancy contract.

This file is the propagation checklist. Phase 1 is mostly **additive + docs-truth** — the only *quoted-statement* shift is the runtime-tenancy contract reconcile (`getVaultPath` / `parachute-tenant-id` did not match the code). Later phases (the `createVaultSurface` factory, the `@openparachute/surface-render` extraction, the notes-ui + my-vault-ui migrations, the onboarding-prompt rewrite) get their own checklist items here as they land.

## Scope (Phase 1)

- Make the **standalone DCR bootstrap** usable through `ParachuteOAuth` (new `useClientId()` so the hosted-only `/surface/<name>/oauth-client` endpoint is never required).
- README docs-truth: package name `@openparachute/app-client` → `@openparachute/surface-client`; quick-start leads with the standalone path; runtime-tenancy `<meta>` contract + fallbacks documented; typed-error → UI affordance guide.
- Version drift: `index.ts` `APP_CLIENT_VERSION` (`0.1.0-rc.4`) reconciled to `package.json` (`0.1.0`); add correctly-named `SURFACE_CLIENT_VERSION`, keep `APP_CLIENT_VERSION` as a deprecated alias.
- `examples/standalone-spa` — a minimal framework-free standalone surface proving the DCR flow.
- Pattern-doc reconcile: `runtime-tenancy-contract.md` named `getVaultPath` + a `parachute-tenant-id` meta tag; the code exports `getVaultUrl` and derives tenant-id from the mount path. Code is the source of truth; the pattern doc was fixed to match.

## Code references

### parachute-surface (surface-client)

- [x] `packages/surface-client/src/oauth.ts`: add `useClientId(info)` — seeds the in-memory client-info cache for the standalone DCR bootstrap so `beginFlow` / `handleCallback` / `refreshAccessToken` never hit the hosted endpoint. Tracked-by: surface-client Phase 1 PR.
- [x] `packages/surface-client/src/index.ts`: `SURFACE_CLIENT_VERSION = "0.1.0"` (matches package.json); `APP_CLIENT_VERSION` kept as a deprecated alias. Tracked-by: surface-client Phase 1 PR.
- [x] `packages/surface-client/src/__tests__/oauth.test.ts`: tests for the `useClientId` standalone path (5 new tests). Tracked-by: surface-client Phase 1 PR.

### parachute-patterns

- [x] `patterns/runtime-tenancy-contract.md`: drop `getVaultPath` (code exports `getVaultUrl`), drop the `parachute-tenant-id` meta tag (tenant-id is derived from the mount path via `getTenantId`), add `parachute-vault-origin`, note the never-throw/null-for-standalone semantics. Tracked-by: this PR.

## Doc references

- [x] `parachute-surface/packages/surface-client/README.md`: package name fixed; standalone-first quick-start; runtime-tenancy contract + fallback table; error-handling guide. Tracked-by: surface-client Phase 1 PR.
- [ ] `parachute.computer/design/onboarding/surface-build.md`: rewrite from "hit the raw HTTP API / token-paste" to "import surface-client (+ surface-render)". **Phase 6** — not in Phase 1. Tracked-by: (pending).

## Later-phase items (not Phase 1)

- [ ] `createVaultSurface` factory with hosted/standalone auto-detect + auto-refresh VaultClient (**Phase 2**, surface-client). Tracked-by: (pending).
- [ ] Extract `@openparachute/surface-render` (markdown + wikilinks + embeds + multi-format + MDX-safe-default) (**Phase 3**, parachute-surface). Tracked-by: (pending).
- [ ] Migrate notes-ui onto surface-render; reconcile its `discovery.ts` shim against `createVaultSurface`'s `clientName` (**Phase 4**). Tracked-by: (pending).
- [ ] Adopt both packages in `~/Code/my-vault-ui`, deleting its hand-rolled oauth/api/pkce/types + Markdown/AudioEmbed (**Phase 5**, external). Tracked-by: (pending).

## Audit

Run [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) before the next surface-client release to catch any lingering `@openparachute/app-client` references in docs.
