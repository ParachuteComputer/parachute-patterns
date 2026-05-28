---
title: Capability-attenuation auth (operator-mintable vault:admin → general attenuation)
date: 2026-05-28
status: active — arc LANDED; only the breaking pvt_* DROP (vault#282) remains, gated on the human
originating-pr: parachute.computer (design doc 2026-05-28-operator-mintable-vault-admin)
---

# Capability-attenuation auth (operator-mintable vault:admin → general attenuation)

An auth-surface shift, landed across hub + vault. It began narrow: hub's `POST /api/auth/mint-token` learns to mint `vault:<name>:admin` **when, and only when, the calling bearer carries `parachute:host:admin`** — a privilege de-escalation (vault-pinned admin descends from box-wide admin), not an escalation. It then generalized into **capability attenuation** — *any bearer may mint OR revoke a token whose authority is a subset of its own* — which lets `parachute vault mcp-install`, the `manage-token` MCP tool, and the vault admin SPA tokens page drop the deprecated `pvt_*` opaque token **entirely** ahead of its hard removal at vault 0.6.0 (vault#282), with vault becoming a pure hub resource-server.

Full architectural reasoning: [`parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md`](../../parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md).

> **Update 2026-05-28 — generalized to capability attenuation; decision locked; arc LANDED.** PR-A's `host:admin → vault:<name>:admin` carve-out was the first instance of a broader principle Aaron landed on: **any bearer may mint OR revoke a token whose authority is a subset of its own.** hub#452 generalizes mint-token's guard into a single `canGrant(bearerScopes, requestedScope)` (in `scope-attenuation.ts`, alongside the `hasMintingAuthority` entry gate) covering: (1) `host:auth` → any requestable scope; (2) `host:admin` → `vault:<N>:admin` (PR-A); (3) **`vault:<N>:admin` → `vault:<N>:{read,write,admin}` same-vault subsets (new).** hub#454 makes revoke symmetric — you may revoke exactly what you could mint. This dissolves the apparent conflict between "clean auth (vault = pure resource-server)" and "keep features" — manage-token becomes a thin hub-mint proxy rather than a local-token issuer (vault#405), so `pvt_*` can be dropped **entirely**, not partially. **Aaron confirmed (2026-05-28): hub is a hard requirement for granular auth; vault is always hub-fronted; granular per-token auth is a hub-minted capability** (standalone-no-hub keeps only the coarse `VAULT_AUTH_TOKEN`/`vault.yaml` secrets). vault#282 amends from "delete the pvt_* validation path" to "pure RS; granular auth is hub-minted via attenuation." **Everything below is merged to `main` except the breaking DROP (vault#282), which is gated on the human.** Adversarial audit: 5 findings, 0 P0/P1; the 2 residual P2s are closed-by-DROP (see §Adversarial audit). Continuity memory: `project_auth_unification_arc`.

## Why the shift

- **Vault-admin had no headless hub-mint path.** The non-requestable-scope guard on mint-token refused `vault:<name>:admin` outright. The only source was `pvt_*`, which mcp-install fell back to and the SPA tokens page minted directly.
- **`pvt_*` is being removed.** vault#282 hard-retires `pvt_*` at 0.6.0 (vault rejects with 401, deletes the validation path). Both consumers break with no replacement unless vault-admin gets a hub-minted equivalent first.
- **De-escalation makes the guard relaxation safe.** `parachute:host:admin` already implies admin of every vault on the box. A vault-pinned admin token can do strictly less, so minting it from a host-admin bearer grants nothing new. The guard stays fully in force for every caller below host-admin (a `parachute:host:auth`-only bearer still cannot mint vault-admin).

This decision is recorded as the admin-scope replacement step in the pvt_* retirement arc — see [`../research/auth-architecture-shape.md`](../research/auth-architecture-shape.md) §11.6.

## The change in one sentence

One hub guard refinement (PR-A) unlocks two consumers — the headless CLI via `operator.token`, and the browser SPA via the existing `session → /admin/host-admin-token → mint-token` chain — both landing a durable, revocable, audience-bound hub JWT instead of a `pvt_*`.

## PR map

| PR | Repo | Scope | Depends on | Status |
|---|---|---|---|---|
| PR-A | parachute-hub | mint-token: `host:admin` → `vault:<N>:admin`; `isVaultAdminScope` export + `vault_scope` pin + tests | — | ✅ hub#449 merged |
| PR-B | parachute-vault | mcp-install admin → hub-mint; `verb==="admin"` reject removed; `#288`→`#282` citation fixes | PR-A | ✅ vault#397 merged |
| **ATTEN** | parachute-hub | **capability attenuation: `canGrant` / `hasMintingAuthority` model (`scope-attenuation.ts`); `vault:<N>:admin` → same-vault subtokens; subsumes PR-A** | PR-A | ✅ hub#452 merged |
| SG | parachute-hub (scope-guard) | scope-guard 0.4.0-rc.2 surfaces the `permissions` claim on `HubJwtClaims` (stops stripping it); **published** | — | ✅ hub#453 merged |
| REVOKE | parachute-hub | revoke-token applies the same `canGrant` rule — revoke what you could mint (symmetric attenuation) | ATTEN | ✅ hub#454 merged |
| HYGIENE | parachute-hub | reject malformed vault-shaped scope strings at mint-token (defensive) | ATTEN | ✅ hub#455 merged |
| C0 | parachute-vault | vault `authenticateHubJwt` reads `permissions.scoped_tags` → `AuthResult.scoped_tags` (fail-closed on malformed) | SG | ✅ vault#403 merged |
| C0-storage | parachute-vault | enforce tag-scope on raw `/api/storage` attachment-binary reads (close C0 bypass) | C0 | ✅ vault#407 merged |
| MGT | parachute-vault | manage-token MCP → hub-mint proxy (forward caller bearer to mint-token; revoke/list via hub registry; session-pinned ledger) | ATTEN, C0 | ✅ vault#405 merged |
| SPA | parachute-vault | admin SPA tokens page mints hub JWTs (was "PR-C") via session → host-admin-token → mint-token; list/revoke via hub registry; legacy pvt_* read-only until 0.6.0 | ATTEN, C0 | ✅ vault#406 merged |
| DROP | parachute-vault | remove pvt_* issuance + validation entirely; vault becomes a pure RS; amend vault#282 | MGT, SPA | ⏳ **only remaining — pending human go (0.6.0), vault#282** |
| Docs | parachute.computer + patterns | finalize design doc + migration tracker; tag-scoped-tokens pattern + §11.6 coherence; stop recommending pvt_* in install/token docs | ATTEN | 🔄 this PR pair (design + patterns); install/token-doc sweep tracked below |

## Code references

Items are `[x]` when landed, `[ ]` when planned/pending. PR refs appended as they land.

### parachute-hub (PR-A) — ✅ LANDED (hub#449)

- [x] `src/api-mint-token.ts` — exempt `vault:<name>:admin` from the non-requestable-scope guard **when the calling bearer carries `parachute:host:admin`**; leave the refusal in place for every other caller (incl. `parachute:host:auth`-only). (hub#449)
- [x] `src/api-mint-token.ts` — pin `vault_scope: [<name>]` on admin mints (match the canonical session-path mint in `admin-vault-admin-token.ts`; defense-in-depth + least privilege, not the `[]` sentinel). (hub#449)
- [x] `src/scope-explanations.ts` — export `isVaultAdminScope` (+ `vaultAdminScopeName`) for the guard to use. (hub#449)
- [x] `src/scope-explanations.ts` — update the comment that says vault-admin is "minted by a session-cookie-gated hub endpoint, never by the public OAuth flow" to note the new operator-bearer mint-token path (still **not** the public OAuth flow). (hub#449)
- [x] Tests — host-admin bearer mints vault-admin (allowed); host-auth-only bearer mints vault-admin (still refused); bare `vault:admin` not caught by the exemption; minted token has `aud=vault.<name>` and `vault_scope=[<name>]`. (hub#449)
- Follow-ups filed: hub#450 (optional vault-existence validation on the bearer mint path), hub#451 (review whether bare unnamed `vault:admin` should be headlessly requestable).

### parachute-hub capability attenuation (ATTEN — generalizes + subsumes PR-A) — ✅ LANDED (hub#452)

- [x] `src/scope-attenuation.ts` — new module: `canGrant(bearerScopes, requestedScope)` (3 rules — host:auth→requestable, host:admin→`vault:<N>:admin`, `vault:<N>:admin`→same-vault subtokens) + `hasMintingAuthority(bearerScopes)` entry gate. Pure functions, no DB/IO. (hub#452)
- [x] `src/api-mint-token.ts` — guard becomes `scopes.filter((s) => !canGrant(bearerScopes, s))`; PR-A's host-admin→vault-admin carve-out is now rule 2 of the general rule. (hub#452)
- [x] Tests — `vault:<N>:admin` bearer mints same-vault `read`/`write`/`admin` (allowed); cross-vault mint refused; bearer-with-no-authority 403'd at the entry gate. (hub#452)

### parachute-hub scope-guard `permissions` claim (SG — C0 prerequisite) — ✅ LANDED (hub#453, published)

- [x] `packages/scope-guard` — 0.4.0-rc.2 surfaces the `permissions` claim on `HubJwtClaims` (stops stripping it). Published so vault can depend on it for C0. (hub#453)

### parachute-hub symmetric revoke (REVOKE) — ✅ LANDED (hub#454)

- [x] `src/api-revoke-token.ts` — a target jti is revocable by a non-`host:auth` bearer iff **every** recorded scope on it is `canGrant`-able by the bearer (revoke what you could mint). Reuses `scope-attenuation.ts`. (hub#454)
- [x] Tests — vault-admin revokes its own same-vault subtokens; cross-vault / host-authority targets refused. (hub#454)

### parachute-hub malformed-scope reject (HYGIENE) — ✅ LANDED (hub#455)

- [x] `src/api-mint-token.ts` — reject scope strings that *look* vault-shaped but are malformed (wrong segment count, etc.) rather than letting them slip past the attenuation check. Defensive hygiene around the `vault:<N>:<verb>` grammar. (hub#455)

### parachute-vault (PR-B — depends on PR-A) — ✅ LANDED (vault#397)

- [x] `src/mcp-install-interactive.ts` — remove the admin → legacy-pat auto-route; route admin to `mode=mint`, `scope=vault:admin`. (vault#397)
- [x] `src/cli.ts` — remove the `verb==="admin"` pre-flight reject in the mint path; fix the `--help` literal + `--scope` JSDoc that still described admin as legacy-pat-only; add an older-hub (pre-hub#449) hint on the mint 400 path. (vault#397)
- [x] Tests — update the cases pinning the old admin → pat behavior; add a `--help`-output regression test. (vault#397)

### parachute-vault C0 — read tag-scoping from the hub-JWT `permissions` claim — ✅ LANDED (vault#403, vault#407)

The prerequisite found during SPA scoping: vault's `authenticateHubJwt` hard-coded `scoped_tags: null` and `@openparachute/scope-guard` stripped the JWT `permissions` claim. Minting the SPA's (or manage-token's) tokens as hub JWTs without teaching vault to read tag-scoping from `permissions` would **silently drop tag-scoping** (every minted token → full-vault) — a security regression. C0 closes that.

- [x] `src/auth.ts` — `authenticateHubJwt` reads `permissions.scoped_tags` into `AuthResult.scoped_tags` (was hard-coded `null`). `parseScopedTagsFromPermissions` **fails closed**: present-but-malformed `scoped_tags` (non-array, empty `[]`, non-string members) throws `MalformedScopedTagsError` → request rejected (401), never coerced to `null`/`[]` (either would *widen* a token meant to be narrowed). Depends on scope-guard 0.4.0-rc.2 (hub#453). (vault#403)
- [x] Regression tests — a tag-scoped hub JWT enforces its allowlist on `query-notes`; malformed `scoped_tags` is rejected. (vault#403)
- [x] `src/routes.ts` — raw `/api/storage/<date>/<file>` attachment-binary endpoint is gated behind `noteWithinTagScope` (was served by filesystem path with only a path-traversal guard, so a `[work]`-scoped token could fetch a `#health` note's attachment bytes if it learned the UUID path). Confirmed by the adversarial audit (storage tag-scope bypass, P2 / C0). (vault#407)

### parachute-vault SPA tokens migration (was "PR-C") — ✅ LANDED (vault#406)

- [x] `web/ui/src/lib/tokens-api.ts` — mints via `session → /admin/host-admin-token → /api/auth/mint-token` (with `permissions.scoped_tags` for the tag-picker); list via hub `/api/auth/tokens`; revoke via hub `/api/auth/revoke-token` by jti. Legacy `pvt_*` retained read-only/revoke-only as a "Legacy tokens (pre-0.6.0)" section until the vault#282 hard-removal. (vault#406)
- [x] Tests — SPA mint/list/revoke against hub registry; tag-scoped mint round-trips through the `permissions` claim. (vault#406)

### parachute-vault manage-token MCP → hub-mint proxy — ✅ LANDED (vault#405)

Resolved by capability attenuation: once `vault:<N>:admin` can mint same-vault subtokens (ATTEN rule 3), `manage-token`'s only credential — the MCP caller's `vault:<N>:admin` bearer — is sufficient. No vault-local token type needed; vault#282 keeps its "delete the pvt_* validation path entirely" mandate.

- [x] `src/mcp-tools.ts` — `manage-token` forwards the MCP caller's bearer to hub's `/api/auth/mint-token`; revoke/list route to hub's registry; the minting ledger is **session-pinned** so the tool can list/revoke what it minted. The raw bearer is threaded through to the MCP tool layer. No `pvt_*` issued. (vault#405)

## Citation-fix references — ✅ DONE (vault#397)

The CLI cited the wrong retirement issue (`#288`) for pvt_*; the correct issue is **vault#282**.

- [x] `parachute-vault/src/mcp-install-interactive.ts` — `#288` → `#282` (×2 occurrences). (vault#397)
- [x] `parachute-vault/src/cli.ts` — `#288` → `#282` in the legacy-pat note + `--scope` JSDoc. (vault#397)
- Note: `parachute-vault/src/routes.ts:568` carries a *genuine* `#288` (date-filter param removal) — intentionally untouched.

## Doc references

- [x] `parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md` — reframed from PR-A-only into the full capability-attenuation model; fixed the stale `{access_token, token_type, expires_in}` response-shape examples (audit R8) → real `{jti, token, expires_at, scope, permissions?}`; recorded the locked decision + the Verified note. (this PR pair)
- [x] `parachute-patterns/research/auth-architecture-shape.md` §11.6 — subsection recording this decision as the admin-scope replacement path; cross-references the design doc. Coherence-checked + the superseded "tag-scoped write tokens still lack a hub-JWT home" caveat updated to point at C0 as the live mechanism. (this PR pair)
- [x] `parachute-patterns/patterns/tag-scoped-tokens.md` — updated: tag-scoping now rides the hub-JWT `permissions.scoped_tags` claim (C0, vault#403), vault enforces it fail-closed; raw `/api/storage` reads are tag-scope-gated (vault#407). Was stale ("hub JWTs don't carry tag-scoping / vault reads the allowlist from its own tokens row"). (this PR pair)
- [ ] Install / token docs — stop recommending `pvt_*`; recommend `parachute auth mint-token` and the mcp-install hub-mint path. Surfaces to sweep: `parachute.computer/install.njk`, any `parachute vault tokens` / mcp-install walkthroughs, vault README token sections. (TBD — bundled with the DROP)

## Operator-facing references

- [x] `parachute vault mcp-install` interactive output — the admin path now describes a hub-minted JWT, not a `pvt_*`. (vault#397)
- [x] Vault admin SPA tokens page copy — tokens are durable hub JWTs (revocable via hub registry), with legacy `pvt_*` rows shown read-only as "Legacy tokens (pre-0.6.0)". (vault#406)

## External references

- None. No npm package descriptions, GitHub repo descriptions, or published-package metadata change. The token *shape* operators receive changes (pvt_* → hub JWT) but no offsite surface names it. (scope-guard 0.4.0-rc.2 was published, but that's an internal dep, not an offsite-named surface.)

## Adversarial audit

The landed arc was audited adversarially: **5 findings, 0 P0/P1.** Outcome:

- 3 findings addressed inline during the arc (e.g. the raw `/api/storage` tag-scope bypass → vault#407; malformed vault-shaped scope strings → hub#455; fail-closed-on-malformed `scoped_tags` → vault#403).
- **2 remaining P2s — closed by the pending DROP:**
  1. **REST `pvt_*` launder path** — a `pvt_*` credential can still be presented on the REST surface while pvt_* validation exists. Closes when DROP removes the validation path (vault#282).
  2. **`pvt_*` persistence** — legacy `pvt_*` rows still live in the vault DB (read-only) until the hard-removal. Closes when DROP deletes issuance + validation entirely.

Both P2s exist *only because pvt_* still exists*; they have no fix short of the DROP, which is the planned terminal step.

## Relationship to vault#282

This migration is a **precondition** for vault#282 (pvt_* Phase-6 hard removal at vault 0.6.0), and it is now **fully met**. Every credential pvt_* used to provide has a hub-minted equivalent: read/write via the normal mint path; vault-admin via PR-A/ATTEN; same-vault subtokens via ATTEN rule 3 (manage-token, SPA); tag-scoping via the `permissions.scoped_tags` claim (C0). DROP is the only remaining step and is **gated on the human** — it's the one breaking change in the arc (vault rejects pvt_* with 401, deletes the validation path, becomes a pure resource-server).

- [ ] **DROP (vault#282)** — remove pvt_* issuance + validation entirely; verify no remaining pvt_* mint path before closing. Closes the 2 audit P2s. Pending human go.

## Open questions

- **~~Tag-scoped tokens don't yet ride in hub JWTs.~~ RESOLVED by C0 (vault#403, vault#407).** The `permissions.scoped_tags` claim (auth-architecture-shape §11.3) is the live mechanism: scope-guard surfaces it (hub#453), vault reads + enforces it fail-closed (vault#403), and the raw `/api/storage` read is gated too (vault#407). Tag-constrained tokens have a hub-JWT home; pvt_* removal at vault#282 strands nothing on the tag-scope axis. (No open questions remain on this arc.)

## Cross-references

- [`parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md`](../../parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md) — the architectural decision.
- [`../research/auth-architecture-shape.md`](../research/auth-architecture-shape.md) §11 — the AS/RS convergence and pvt_* retirement arc; §11.6 records this decision.
- [`../patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md) — hub is the sole minting surface; this keeps vault-admin on that surface.
- [`../patterns/governance.md`](../patterns/governance.md) — review discipline surrounding migrations.
- [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — run after the arc lands to catch missed pvt_* references.
