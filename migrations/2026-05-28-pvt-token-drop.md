---
title: pvt_* token DROP — vault becomes a pure hub resource-server (vault#282 Stage 2)
date: 2026-05-28
status: in-flight — vault DROP PR open (0.6.0-rc.1); not merged
originating-pr: parachute-vault (the breaking DROP PR — vault#282 Stage 2)
---

# pvt_* token DROP — vault becomes a pure hub resource-server

The terminal, **breaking** step of the auth-unification arc. The enabling work
(capability-attenuation auth, hub-minted vault-admin, manage-token-as-proxy,
the SPA migration, C0 tag-scope-via-`permissions`) all landed first — see the
sibling tracker [`2026-05-28-operator-mintable-vault-admin.md`](./2026-05-28-operator-mintable-vault-admin.md).
This file tracks the DROP itself: vault stops minting **and** validating the
opaque `pvt_*` vault-DB token. A `pvt_*`-prefixed bearer now **fails closed
with 401** on every vault auth surface. Vault is now a pure hub OAuth
resource-server.

This is the one breaking change in the arc, so it leaves the `rc.N`-on-`0.X.Y`
chain and ships at **`0.6.0-rc.N` → `0.6.0` stable** (governance rule 2 —
breaking → minor bump; `@latest` untouched until the human says ship).

## Why this is the breaking step

`pvt_*` was vault's pre-hub token type. Every capability it provided has a
hub-minted equivalent already shipped (read/write/admin scopes, per-vault
binding, tag-scoped tokens, session-managed mint/revoke). Keeping two parallel
auth surfaces is exactly what this removes. After the DROP, vault validates
hub-issued JWTs + the coarse `VAULT_AUTH_TOKEN` / `vault.yaml` operator secrets
and nothing else. Closes the 2 residual audit P2s from the enabling arc (REST
pvt_* launder path; pvt_* row persistence) — both existed only because pvt_*
existed.

## The fresh-vault first-credential decision (the headline)

Pre-DROP, `parachute-vault create` / `init` minted a `pvt_*` so a fresh install
*without a hub* still worked out of the box. The DROP removes that. The
deliberate replacement (not a fall-out of mechanical deletion):

- **Hub reachable** (operator.token present + a real hub origin resolves — the
  same machinery `mcp-install --mint` uses): `create` / `init` **mint a hub JWT**
  (`vault:<name>:admin`) and emit it. This preserves the `create --json`
  `token`-string contract hub's `admin-vaults.ts` requires (a hub JWT is a
  string).
- **No hub reachable** (standalone): **no token issued** — explicit guidance
  ("install the hub, or set `VAULT_AUTH_TOKEN`"). `create --json` emits
  `token: ""` plus a new `token_guidance` field.

Granular per-token auth is a hub-minted capability; standalone-no-hub keeps only
the coarse `VAULT_AUTH_TOKEN` / `vault.yaml` secrets. (Aaron, 2026-05-28: hub is
a hard requirement for granular auth; vault is always hub-fronted.)

## Data migration: the `tokens` table is KEPT (inert)

**No DROP TABLE, no purge.** Three reasons:
1. Existing `pvt_*` rows are harmless once validation is gone (no path reads them).
2. `migrateVaultKeys` raw-INSERTs legacy YAML api_keys into this table — it's
   the import landing zone and must persist.
3. Precedent: `oauth_clients` / `oauth_codes` are already "left in place; a
   future migration will drop them." Follow that.

The table header comment is marked vestigial. A future cosmetic migration may
drop `tokens` alongside `oauth_clients` / `oauth_codes`. No new `migrateToVN`
ships for the DROP. `parachute-vault tokens list` / `tokens revoke` survive for
cleaning up leftover rows.

## PR map

| PR | Repo | Scope | Status |
|---|---|---|---|
| DROP | parachute-vault | remove pvt_* mint + validation; REST tokens module; `tokens create`; `mcp-install --legacy-pat`; SPA legacy panel; dead store fns; fresh-vault hub-mint re-plumb; docs; 0.6.0-rc.1 | ⏳ **open — this PR, not merged** |
| (migration) | parachute-patterns | this file | ⏳ **open — sibling PR** |

## Code references (parachute-vault DROP PR)

### Issuance removed
- [x] `src/tokens-routes.ts` + `src/tokens-routes.test.ts` — **deleted** (REST `POST|GET|DELETE /vault/<name>/tokens` module).
- [x] `src/routing.ts` — removed the `/tokens` route block + `handleTokens` import.
- [x] `src/cli.ts` — `createVault` now async, mints a hub JWT (`mintBootstrapCredential`) or returns no-token guidance; `cmdCreate` async + new `token`/`token_guidance` JSON shape + human output; `cmdInit` re-plumbed (hub-mint or guidance, `installMcpConfig` bearer + `buildInitSummaryLines`); `mcp-install --legacy-pat` removed (mode union `mint|token`); `tokens create` removed; dead `generateToken`/`createToken`/`TokenPermission`/`resolveCreateTokenFlags`/`parseDuration` refs cleaned.
- [x] `src/mcp-install-interactive.ts` — removed the `legacy` auth choice + `askScope`; no-hub branch is paste-only.
- [x] `src/init-summary.ts` — new `noTokenGuidance` + "wanted-token-but-no-hub" branch.

### Validation removed
- [x] `src/auth.ts` — removed the pvt_* DB-lookup block in `authenticateVaultRequest` (+ the `vaultDb` param, dropped from all 3 prod call sites in `routing.ts` + `isViewAuthenticated`); removed the pvt_* fallback loop in `authenticateGlobalRequest`; removed `warnPvtDeprecationOnce` / `PVT_MIGRATION_DOC` / `warnedPvtTokens`. A `pvt_*` bearer fails closed to 401.

### Dead store fns removed
- [x] `src/token-store.ts` — removed `generateToken`, `createToken`, `resolveToken`, `ResolvedToken`, `listMcpMintedTokens`, `softRevokeMcpToken` (+ the lone `pvt_` literal). KEPT `parseScopedTags`, `hashKey` import, `listTokens`, `revokeToken`, `findTokensReferencingTag`, `migrateVaultKeys`, ALL `mcp_mint_ledger` fns.

### SPA
- [x] `web/ui/src/lib/tokens-api.ts` — removed `LegacyTokenSummary` / `listLegacyTokens` / `revokeLegacyToken` (kept `_authedFetch` / `HttpError` / `listVaultTags`).
- [x] `web/ui/src/routes/VaultTokens.tsx` — removed the legacy state/effect/JSX + `LegacySection` / `LegacyTokenRow` (kept the hub-JWT tree + `fmtDate`).

### Schema / status
- [x] `src/auth-status.ts` — `auth_modes` → `["hub_jwt"]`; `hasTokens` reworded (probes vestigial rows).
- [x] `core/src/schema.ts` — tokens-table header marked vestigial; migration comments past-tensed (migration *code* untouched).

### Tests
- [x] `token-store.test.ts` rewritten (survivors only); `auth.test.ts` rewritten (pvt_* 401 fail-closed regression on per-vault + global + YAML + VAULT_AUTH_TOKEN); `auth-hub-jwt.test.ts` (Stage-1 deprecation block → pvt_* DROP regression); `routing.test.ts` (pvt_* mint helpers → hub-JWT mint fixture; `auth_modes` assertion; vestigial-row seeding for hasTokens + tag-reference guard); `vault-create.test.ts` / `init-summary.test.ts` / `mcp-config.test.ts` / `mcp-install*.test.ts` / `vault.test.ts` adapted.

## Doc references

- [x] `parachute-vault/UPGRADING.md` — pvt_* section flipped deprecation → breaking ("REJECTED as of 0.6.0"); migration steps kept as the recovery path; workstream-E "what survives" claims forward-pointed.
- [x] `parachute-vault/CHANGELOG.md` — one `0.6.0-rc.1` entry appended (history verbatim).
- [x] `parachute-vault/README.md` — auth table + token-format + token-management + mcp-install cheat-sheet sections rewritten to hub-JWT; `--legacy-pat` / `tokens create` examples removed.
- [x] `parachute-vault/CLAUDE.md` — `create` / `tokens` descriptions updated.
- [x] `parachute-vault/src/cli.ts` usage()/help + JSDoc — `--legacy-pat` removed; `mcp-config <pvt_...>` → `<bearer>`.
- [x] doc-comment debt — `auth.ts`, `token-store.ts`, `scopes.ts`, `mcp-tools.ts`, `schema.ts` pvt_* comments cleaned/past-tensed.
- [ ] **secondary README prose sweep (FOLLOW-UP)** — descriptive `pvt_...` mentions in `README.md` (the auto-wire narrative ~L96/L102, the Claude Desktop/Code MCP-entry examples ~L129–137/L157, the `/view` auth note ~L448, the `PARACHUTE_VAULT_TOKEN=pvt_...` env examples ~L675/L684) are non-erroring prose, not command examples — tracked as a follow-up issue, not blocking.
- [ ] **secondary design/API docs (FOLLOW-UP)** — `parachute-vault/docs/HTTP_API.md` (pvt_* credential-table row, POST /tokens docs), `docs/auth-model.md` (the "API tokens (Bearer) / pvt_*" subsection), `docs/design/2026-04-28-vault-config-and-scopes.md` (strikethrough treatment). Tracked as a follow-up.

## External references

- None change. The npm package description / GitHub repo description don't name
  pvt_*. The token *shape* operators receive changes (pvt_* gone), but no
  offsite-named surface references it. CI publishes `@openparachute/vault@0.6.0`
  on the `v0.6.0` tag push (tag-gated; not part of this PR).

## Cross-references

- [`./2026-05-28-operator-mintable-vault-admin.md`](./2026-05-28-operator-mintable-vault-admin.md) — the enabling arc (everything that had to land before this DROP was safe).
- [`../research/auth-architecture-shape.md`](../research/auth-architecture-shape.md) §11 — the AS/RS convergence + pvt_* retirement arc.
- [`../patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md) — hub is the sole minting surface; the DROP makes vault a pure consumer.
- [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — run after the DROP merges to catch missed pvt_* references.
