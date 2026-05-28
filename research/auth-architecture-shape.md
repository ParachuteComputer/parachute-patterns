# Auth architecture — current shape, industry survey, candidate futures

**Status:** research input for the auth-architecture rethink Aaron asked for on 2026-05-09
**Date:** 2026-05-09
**Companion to:** `patterns/hub-as-issuer.md`, `patterns/oauth-scopes.md`, `patterns/token-auth.md`, `patterns/oauth-dcr-approval.md`, `patterns/service-to-service-auth.md`
**Brief:** Aaron flagged that the auth surface has accumulated complexity faster than mental coherence. Specific concerns: "if there's no operator we can just use tokens right?", "you have to login via OAuth with notes and other things, and sometimes just adding the token is the right call", "vault and hub have two different token setups… whole thing feels a little messy", "real risks in long-lived bearer tokens." This doc maps the current state, surveys how mature systems handle the equivalent problem, and lays out three candidate architectures with trade-offs.

**Status update (2026-05-09 evening):** Aaron and team-lead converged on a direction. **Hub becomes the sole authorization server; vault, agent, scribe become resource servers.** See §11 for the decision shape. Migration tracker: [parachute-hub#212](https://github.com/ParachuteComputer/parachute-hub/issues/212). The decision adopts Option B's operator-surface-unification premise and extends it with a structural separation Aaron requested. §§1–10 below preserve the pre-decision research as it stood.

Sources are cited inline by URL or `repo/path:line`. Where docs are silent or contradictory, that's called out.

---

## 1. TL;DR

1. **Today there are five distinct token shapes coexisting.** `parachute_hub_session` cookie (24h, sliding gate for the operator's own browser), hub-issued OAuth access JWT (15min, RFC 7591 DCR + PKCE consent), hub-issued refresh JWT (30d, rotation-on-use), `~/.parachute/operator.token` (365d JWT, mode 0600, on-box service accounts), `pvt_*` per-vault bearer (no expiry, vault-DB-resident, hash-only storage). Plus the legacy `SCRIBE_AUTH_TOKEN` shared-secret on the s2s axis. Five-ish primitives is more than the problem requires; some of them are also live workarounds for each other (`parachute_hub_session` cookie auto-approves the DCR that the operator-bearer was supposed to). [`parachute-hub/src/operator-token.ts:21-37`, `parachute-hub/src/sessions.ts:18-19`, `parachute-vault/src/token-store.ts:115-119`, `parachute-hub/src/jwt-sign.ts:32-33`]

2. **Notes' UI today only does OAuth — there is no bearer-paste path.** [`parachute-notes/src/app/routes/AddVault.tsx:31-51`] The user enters a hub URL and the SPA immediately calls `beginOAuth(...)` which discovers AS metadata, runs DCR, redirects to `/oauth/authorize`. A user with a freshly-minted `pvt_*` from `parachute vault tokens create` cannot paste it into Notes. The "App not yet approved" friction Aaron's cousin hit was a direct consequence of this: cross-origin DCR can't auto-approve, and there's no fallback path.

3. **Vault and hub do have two different token systems, by design.** Vault's `pvt_*` is a legacy/PAT path (per-vault DB row, hash-stored, no JWT — survives standalone-vault deployments without a hub). Hub-issued JWTs are the OAuth path (signed by hub's JWKS, validated by vault, audience-bound to one vault). They share the **scope vocabulary** (`vault:<name>:<verb>`) but not the **storage**, **lifetime**, or **revocation** mechanism. [`parachute-vault/src/auth.ts:153-238`] The split is functional but the operator surface — "I have a token, where do I paste it?" — sees both shapes without ergonomic unification.

4. **Hub-issued access tokens are 15-minute, refresh tokens are 30-day with RFC 6749 §6 rotation + family revocation.** [`parachute-hub/src/jwt-sign.ts:32-33`, `parachute-hub/src/oauth-handlers.ts:1043-1090`] This is the modern standard. The OAuth refresh story is solid; the worry is the **other** long-lived token: `operator.token` is 365 days, file-stored, **un-revocable at the issuer** (the docstring says "treat like an SSH private key"). That's the load-bearing leak risk Aaron flagged.

5. **`pvt_*` tokens have no expiry by default and no revocation list at the hub.** [`parachute-vault/src/token-store.ts:151-191`] Scope-narrowed (verb + tag-allowlist + per-vault binding), hashed-on-disk, but live forever unless the operator explicitly revokes by display ID. Industry peers split: GitHub fine-grained PATs default 1-year expiry [GitHub docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens), Linear personal API keys can scope but are similarly indefinite-by-default [Linear docs](https://linear.app/docs/api-and-webhooks), Capacities is "all-or-nothing, full data access, no expiry" [Capacities docs](https://docs.capacities.io/developer/api). The mature consensus pulled by recent OAuth security BCP: long-lived bearers want sender-constraining or rotation, not nothing.

6. **The mature ecosystem converged on N-tier credential models, not 1-tier.** GitHub ships three (PAT classic, PAT fine-grained, GitHub Apps with installation tokens). Notion ships two (internal "installation token", external OAuth). Slack ships four (bot, user, app-level, configuration tokens). Supabase ships two-and-a-half (publishable anon + secret service-role + per-user RLS-scoped JWT). [Supabase blog](https://supabase.com/blog/jwt-signing-keys) None of the serious peers is "one token shape rules them all." The pluralism is doing real work — agents-vs-humans, first-party-vs-third-party, dev-vs-prod each get tuned to their threat model.

7. **The OAuth-as-default-for-first-party question has a current answer in the IETF: there's a draft for it.** [draft-ietf-oauth-first-party-apps](https://datatracker.ietf.org/doc/draft-ietf-oauth-first-party-apps/) introduces an `/authorize-challenge` endpoint specifically because **for first-party apps, the browser redirect is friction without security gain**. The draft is explicit that this is *only* for first-party (the hub knows the SPA, the SPA knows the hub) — third-party clients still need full redirect flow. This is the right shape conceptually for "Notes is talking to its own hub" but no production library implements it yet at the server side; we'd be early.

8. **The "first-party / third-party" distinction is industry-canonical and we don't draw it cleanly today.** Notes IS first-party (hub-installed, operator-trusted, ships in the same release train) but presents to hub like any third-party: same DCR endpoint, same consent screen, same approval gate. Notion separates them ("internal connections" = static token, "public connections" = OAuth) [Notion docs](https://developers.notion.com/docs/authorization). GitHub installs first-party Apps with implicit trust. Anytype gives the desktop app a 4-digit pairing code instead of OAuth [Anytype docs](https://developers.anytype.io/docs/guides/get-started/authentication/). We have the operator-bearer auto-approve path that *could* play this role, but we don't use it for SPAs — we use it for `parachute install <module>` instead.

9. **Multi-vault scoping is solved, multi-vault auth UX isn't.** [`parachute-vault/src/scopes.ts:122-135`, vault#241, vault#258] `vault:<name>:<verb>` scopes exist; per-vault token-DB binding exists; the consent screen has a vault picker for unnamed `vault:<verb>` requests; tag-allowlist intersection works. What's missing is the operator's mental model: "I have a token, what does it grant?" — answered by JSON shapes today, not surfaces.

10. **Most agents and SPAs in the ecosystem already use OAuth; only the CLI uses the operator bearer.** Agent SPA, Notes SPA, anything claude.ai connects to via DCR — all OAuth. The CLI shell-outs (`parachute auth mint-token`) and on-box services (`parachute install vault` self-registering) are the bearer-token path. So the practical question Aaron is asking — "is OAuth-by-default right for first-party SPAs?" — is exactly Notes (and any future first-party PWA/SPA we ship). Agent's answer is "yes today, and it works because Notes and agent are SPA-shaped browser apps already inside an OAuth-natural context."

---

## 2. Current state — module-by-module

### 2.1 Hub — `parachute-hub`

The hub is the OAuth issuer ([`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md)) and the only module that runs auth endpoints natively today. Five primitives live here.

| Surface | Storage | Validates against | Lifetime | Used by |
|---|---|---|---|---|
| `parachute_hub_session` cookie | `sessions` table in `~/.parachute/hub.db` | row lookup by SID | 24h absolute | Operator's browser at `/admin/login` and `/oauth/authorize` consent screen |
| Hub user's password | `users` table, argon2 hash | `verifyPassword` | n/a (rotation via `parachute auth set-password`) | Login form posts; never on the wire post-login |
| Hub-issued **access** JWT | Stateless (signed by JWKS keypair) | hub's own keys + `iss` match | **15 min** | Browsers carry it, SPAs send it as `Authorization: Bearer …`, vault validates via `validateHubJwt()` |
| Hub-issued **refresh** JWT | `tokens` table, hash-by-jti | row lookup + family revocation | **30 days**, rotation-on-use | OAuth clients exchange for new access tokens |
| `operator.token` (long-lived JWT) | `~/.parachute/operator.token`, mode 0600, plaintext | hub's own keys + `iss` match | **365 days**, **un-revocable at issuer** | `parachute install <module>` self-registering DCR clients; `parachute auth mint-token`; CLI shell-outs |
| OAuth client row (DCR registration) | `clients` table | row lookup by `client_id` | n/a; `pending → approved` lifecycle; deletion is direct DB edit | Every SPA + connector that ever ran `/oauth/register` |
| OAuth grant row (consent skip) | `grants` table | row lookup by `(user_id, client_id)` | n/a; cleared by `parachute auth revoke-grant` | Skip-consent on subsequent flows |

**Key calls:**

- `signAccessToken(...)` ([`parachute-hub/src/jwt-sign.ts`]) — `ACCESS_TOKEN_TTL_SECONDS = 15 * 60`, scope claim is whitespace-separated, audience is inferred from the highest scope (`vault:work:write` → `aud=vault.work`).
- `mintOperatorToken(...)` ([`parachute-hub/src/operator-token.ts:59-74`]) — `OPERATOR_TOKEN_TTL_SECONDS = 365 * 24 * 60 * 60`, scopes hard-coded to `["hub:admin", "parachute:host:admin", "vault:admin", "scribe:admin", "channel:send"]` (broad). Audience defaults to `"operator"`. The docstring says "Treat operator.token like an SSH private key" — a leaked file stays valid until TTL elapses; the hub doesn't track operator-token JTIs.
- `handleRegister(...)` ([`parachute-hub/src/oauth-handlers.ts:1305-1393`]) — DCR with the four-path approval gate. Operator-bearer path auto-approves; cookie+same-origin path auto-approves; cross-origin always lands `pending`.
- `handleApproveClientPost(...)` ([`parachute-hub/src/oauth-handlers.ts:706-757`]) — the inline-approve button (#208/#209) added 2026-05-09 to reduce friction Aaron's cousin hit.

**Design observations:**

- The operator-token's broad scope set is a footgun. A leaked `operator.token` carries `parachute:host:admin` (provision new vaults), `vault:admin` (broad vault scope — vault rejects it on hub-JWTs because it requires resource-narrowing, but the broad form is still in the claim), `hub:admin` (manage signing keys), `scribe:admin`, `channel:send`. That's "everything." [`parachute-hub/src/operator-token.ts:31-37`]
- The operator-token's un-revocability at the issuer is also a footgun. Revocation requires the operator to (a) know the file is leaked, (b) rotate the signing key (`parachute auth rotate-key`), which retires every OAuth-issued JWT in the same blast radius for 24h. The docstring is honest about this; the *exposure* is the issue.
- `parachute auth mint-token --scope <scope>` lets the operator mint short-lived narrow JWTs against the operator identity. This is a good escape hatch (90d default, 365d cap) but requires shell access and an existing `operator.token` to sign against.
- The four DCR auto-approve paths ([`patterns/oauth-dcr-approval.md`](../patterns/oauth-dcr-approval.md)) are the right shape — they do real work cleanly. The deliberate non-fix on cross-origin auto-approve is documented and well-reasoned.

### 2.2 Vault — `parachute-vault`

Vault dual-validates two token shapes per request: JWT-shaped (`eyJ…`) goes through `validateHubJwt()`, anything else hits `resolveToken()` against the per-vault `tokens` SQLite table. [`parachute-vault/src/auth.ts:161-238`]

| Surface | Storage | Validates against | Lifetime | Used by |
|---|---|---|---|---|
| `pvt_*` per-vault token | per-vault `tokens` table, sha256 hash | hash-by-row | None by default; optional `expires_at` | `parachute vault tokens create` flow; legacy YAML keys; CLI scripts; pasted into MCP clients |
| Hub-issued JWT | Stateless | hub JWKS + `iss` match + `aud=vault.<name>` | inherits hub's 15min | Notes SPA, agent SPA, anything OAuthed |
| Legacy YAML keys | `vault.yaml` / `config.yaml` `api_keys` array, sha256 hash | array scan + `verifyKey` | None | Pre-v7 deployments; deprecation warning logged on use |

**Key calls:**

- `authenticateVaultRequest(req, vaultConfig, vaultDb)` ([`parachute-vault/src/auth.ts:161-238`]) — extracts the bearer (header / `x-api-key` / `?key=` query), branches on shape:
  - JWT-shaped → `validateHubJwt(token, {expectedAudience: "vault.<name>"})`. Rejects broad `vault:<verb>` scopes — hub JWTs MUST be resource-narrowed. [`parachute-vault/src/auth.ts:253-284`]
  - `pvt_*`-shaped → `resolveToken(vaultDb, token)`. Per-vault binding (v16): if the token row carries `vault_name = <name>`, that must match the request's vault.
  - Falls through to YAML key check; if hit, logs a one-time deprecation warning.
- `scopes.ts` — `hasScopeForVault(granted, vaultName, requiredVerb)` enforces `admin ⊇ write ⊇ read` plus vault-name match for narrowed scopes. Broad `vault:<verb>` is allowed for `pvt_*` tokens (since the DB row is itself per-vault) but rejected for hub JWTs (which need named scopes).
- Tag-allowlist (`scoped_tags` JSON column) is a v0.5 feature — intersect with the OAuth scope at query time. [`parachute-vault/src/token-store.ts:99-109`, `patterns/tag-scoped-tokens.md`]

**Design observations:**

- The two-shape resolver is straightforwardly correct. Where it's awkward is the **operator's** view of "what tokens do I have." Two storage surfaces: hub admin SPA + `parachute vault tokens` CLI.
- `pvt_*` tokens default to no expiry. The operator must explicitly add `--expires-at` (which the create command does support — but doesn't default).
- The `/.well-known/oauth-authorization-server` discovery doc on vault returns the **hub** as issuer when `PARACHUTE_HUB_ORIGIN` is set; otherwise it returns vault itself. [`patterns/hub-as-issuer.md`] This is RFC 8414 compliant on both sides.
- Vault is the only module that issues `pvt_*` tokens. The pattern says future modules with a "user-facing PAT" should follow the same shape ([`patterns/token-auth.md`]); none have yet.

### 2.3 Notes — `parachute-notes`

**The load-bearing read.** Notes' UI is OAuth-only today. There is no bearer-paste flow, no "I have a token already" path.

**The user journey:**

1. User opens Notes (PWA or browser at `<hub>/notes/`).
2. They land on `AddVault.tsx`; they're prompted for a "Hub URL" — typed manually or seeded from `?url=` or the origin probe.
3. On submit, the SPA calls `beginOAuth(normalized)` ([`parachute-notes/src/lib/vault/oauth.ts:43-93`]), which:
   - Fetches `<hub>/.well-known/oauth-authorization-server` (RFC 8414 metadata).
   - Calls `<hub>/oauth/register` (RFC 7591 DCR), with `credentials: "include"` to ride the session cookie for same-origin auto-approve. Cross-origin: client lands `pending`.
   - Generates PKCE verifier/challenge + state; stashes `PendingOAuthState` in `sessionStorage`.
   - Redirects browser to `<hub>/oauth/authorize?...&scope=vault:read vault:write&...`.
4. Hub renders consent (or hits "App not yet approved" if cross-origin DCR hadn't matched origin).
5. Operator approves; hub redirects back to `<hub>/notes/oauth/callback?code=...&state=...`.
6. `OAuthCallback.tsx` calls `completeOAuth(code, state)`; SPA POSTs to `<hub>/oauth/token` with PKCE verifier; receives `{access_token, refresh_token, expires_in, scope, services, vault}`.
7. Token + services catalog stored in `localStorage` keyed by vault id (`lens:token:<id>`, `lens:services:<id>`) for backwards compat (the `lens:` prefix predates the Lens→Notes revert and is intentionally preserved). [`parachute-notes/src/lib/vault/storage.ts:5-12`]
8. SPA refreshes access token from `refresh_token` on 401 from any `/api/*` call. If refresh fails (revoked / rotated past us), `RefreshHttpError` surfaces and the user gets bounced to re-auth.

**There is no UI affordance for pasting a `pvt_*` token directly.** No "advanced" toggle, no `?token=...` URL param, no fallback path. The only way to get into Notes is the OAuth dance. This is the architectural choice Aaron is questioning.

**Why it ended up here:**

- Notes was built against vault's standalone-OAuth surface (Phase 0+1 of `hub-as-issuer.md`) before the hub was the issuer. The pattern was always OAuth.
- The DCR auto-approve work (#199, #200, #208, #209) reduced friction *within the OAuth flow*; the question of whether the OAuth flow is the right flow at all wasn't reopened.
- The operator's mental model from the CLI side (`parachute vault tokens create` → here is a `pvt_…`) doesn't have a UI to paste it into.

**Token storage:**

- All tokens in `localStorage` (synchronous; visible to any same-origin script). `pendingOAuth` is in `sessionStorage` (cleared on tab close).
- DCR client_id cached in `localStorage` keyed by issuer origin. [`parachute-notes/src/lib/vault/storage.ts:118-128`] Re-registered when `redirect_uri` changes.
- No IndexedDB use for credentials; the IndexedDB usage is the offline-sync queue (not in scope here).

### 2.4 Agent — `parachute-agent`

Agent has **two** auth surfaces: the host SPA web UI (browser, OAuth) and the per-session container (env-injected, hub-token).

**SPA path** ([`parachute-agent/web/ui/src/lib/auth.ts`]):

- Identical OAuth flow shape to Notes: discovery via `<spa>/api/discovery` → DCR via `<hub>/oauth/register` → PKCE-S256 redirect → token exchange → 15-min access, 30d refresh.
- Bootstrap scopes are `agent:admin agent:write` (no vault scopes by default — vault is a "per-agent-group action, not the SPA's identity"). [`auth.ts:18-26`]
- Per-vault flows (operator wants to manage tokens on a specific vault from the agent SPA) extend with `extraScopes=[vault:<name>:admin]` in `beginLogin()` — re-runs the OAuth flow with the narrow scope appended. This is the parachute-agent#56 re-consent pattern.
- Tokens stored in `localStorage` keyed by hub origin. `clearTokens()` drops the token but keeps the cached `client_id` (DCR is one-shot per origin).

**Container path** ([`parachute-agent/src/container-runner.ts`]):

- `PARACHUTE_HUB_ORIGIN=...` is injected into every spawned container so containers can call back into hub-fronted services (`${PARACHUTE_HUB_ORIGIN}/scribe/...`, `${PARACHUTE_HUB_ORIGIN}/vault/...`).
- The bearer the container uses for those calls is operator-side configuration: AES-GCM-encrypted secrets in the central DB (`master.key` at `~/.parachute/agent/master.key`), assigned per agent-group, injected at session-spawn time as env vars. [`parachute-agent/CLAUDE.md` "Secrets / Credentials"]
- This means: today, the canonical way for an agent container to get a hub-validated token is **the operator bakes a long-lived hub-issued JWT into a secret named `VAULT_TOKEN` (or similar)**. There is no "hub mints a per-session JWT for this agent group" flow.

**Design observations:**

- The agent SPA is a textbook first-party SPA: same install, same release train, same operator. The OAuth shape works because the SPA is naturally browser-shaped.
- The container path is the **service-to-service** axis ([`patterns/service-to-service-auth.md`]), but it's smuggled in as user-OAuth tokens via a secrets store. There's no "agent identity" — it's the operator's own token replayed.

### 2.5 Scribe — `parachute-scribe`

Scribe is the simplest module by auth surface.

- `SCRIBE_AUTH_TOKEN` env var (set by `parachute-hub/src/auto-wire.ts` at install time): if a presented bearer matches, grants `scribe:transcribe scribe:admin`. Constant-time compare. Loopback-only.
- JWT path: if the bearer is JWT-shaped, validate against hub JWKS via `validateHubJwt()`, lift scopes from the claim. [`parachute-scribe/src/auth.ts:54-73`]
- Open mode (`SCRIBE_AUTH_TOKEN` unset) skips auth entirely with full scopes. Used for dev / loopback-trusted setups.
- `/health` and `/.parachute/info` are auth-exempt by convention.

**Design observations:**

- Cleanest seam in the ecosystem: `validateToken(token)` returns `{valid, scopes, mode}`. JWT-aware today; ready for full hub-JWT cutover when shared-secret retires.
- The open-mode-by-default pre-launch was the right call for "just works locally"; the `auto-wire` step provisions the secret on install so it's not actually open in shipping deployments.

### 2.6 Channel + others

- `parachute-channel` has minimal auth surface today (telegram bridge that reads its own bot token from env). Not on the hub-issued-JWT path yet. `channel:send` scope declared but not enforced.

---

## 3. The five-token zoo, mapped

Combining the per-module tables, here's the full surface as the operator perceives it:

| Token | Where minted | Where stored | Where presented | Default lifetime | Revocation |
|---|---|---|---|---|---|
| **Hub session cookie** | `/admin/login` POST | `sessions` row + browser cookie | Operator's browser only | 24h absolute | DELETE row / cookie expiry |
| **Hub access JWT** | `/oauth/token` | Stateless | OAuth client → any module via `Bearer` | **15 min** | Wait for expiry (no `tokens` row to delete since stateless) |
| **Hub refresh JWT** | `/oauth/token` | `tokens` table (one row, family-keyed) | OAuth client → `/oauth/token` | **30 days**, rotation-on-use | Family revocation on replay; `/oauth/revoke`; `parachute auth revoke-grant` |
| **`operator.token`** | `parachute auth set-password` / `rotate-operator` | `~/.parachute/operator.token` (0600) | `parachute install`, on-box CLI shell-outs | **365 days** | **Issuer-side: none.** Rotate signing key (24h JWKS overlap) |
| **`pvt_*` per-vault** | `parachute vault tokens create` | per-vault `tokens` table (hashed) | MCP clients, scripts, anywhere bearer fits | None (operator must set `--expires-at`) | Row delete via CLI or admin SPA |
| **Service shared secret** (`SCRIBE_AUTH_TOKEN`) | `auto-wire` at install | `~/.parachute/vault/.env` + `~/.parachute/scribe/config.json` | Vault → scribe loopback | None | Manual rotation, restart both |
| **OAuth client row** | `/oauth/register` (RFC 7591 DCR) | `clients` table | Doesn't authenticate; gates which `client_id`s are allowed to flow | n/a | Direct DB edit (no CLI today) |
| **OAuth grant row** | Consent submit | `grants` table | Skip-consent on subsequent flows | n/a | `parachute auth revoke-grant` |

Notes / agent SPAs **only** present hub-issued JWTs to vault. CLI shell-outs **only** present `operator.token` JWTs. `pvt_*` exists for **scripts and MCP clients** (Claude Web / Code / etc. paste into config). Each row has a coherent niche; the issue is the matrix is dense and non-obvious.

---

## 4. Industry survey

### 4.1 Notion — internal vs public connections

[Notion authorization](https://developers.notion.com/docs/authorization) draws the canonical line between **internal connections** (single-workspace, static "installation access token", created in the Creator dashboard) and **public connections** (multi-workspace, OAuth 2.0 with auth-code + refresh tokens).

- **Internal token = paste-the-bearer.** Workspace owner clicks Create, copies the token, pastes it into their own script. No OAuth dance. No consent screen for the internal owner against their own workspace — they *are* the consent.
- **Public token = full OAuth + refresh.** Bot/installation tokens stored under `bot_id`; refresh tokens for rotation.
- **Page-level access is opt-in regardless of token type.** Both flows require explicit page sharing — the auth is a permission to *try*, not blanket access.

The lesson: Notion explicitly preserved the "I'm the owner, just give me a token" path even after they shipped OAuth. They did not collapse the two; they let internal coexist as the right shape for "one-person scripting against my own workspace."

### 4.2 GitHub — three credential types, three threat models

[GitHub PAT docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) ship three shapes deliberately:

- **PAT classic** — broad-scope, `repo` / `admin:org` / etc., legacy. Auto-removed after 1 year of inactivity.
- **PAT fine-grained** — single-org, repo-scoped (or "all repos / public repos / specific repos"), 50+ permission keys at `read | write | admin`. **Recommended for personal use.** Org admins can require approval before the PAT can hit org resources.
- **GitHub Apps** — long-lived integrations, **installation tokens** (short-lived, JWT-flavored, minted from app-private-key signing). Org-scoped or repo-scoped at install. Can act on behalf of users via OAuth on top.

The framing GitHub uses: **PATs are intended to access GitHub resources on behalf of yourself.** OAuth Apps are user-delegated third-party. GitHub Apps are organizational integrations with minimal privilege escalation. The three solve disjoint problems and they're **deliberately non-collapsed**.

### 4.3 Linear — OAuth + per-key scoped PATs

[Linear API docs](https://linear.app/docs/api-and-webhooks): OAuth 2.0 with refresh (24h access, refresh-rotation since 2026-04-01) **and** Personal API Keys created at Settings > Account > Security & Access. The PAT shape:

- Choose full-access OR Read / Write / Admin / Create issues / Create comments narrow.
- Optionally scope to specific teams in the workspace.
- Admins can disable member-created PATs entirely.
- Once created, the key is shown once.

The PAT *also* respects the user's underlying access — a member's PAT can never grant beyond what the member can do. This is the "subset rule" already in vault's `validateMintedScopes` ([`parachute-vault/src/scopes.ts:169-198`]).

### 4.4 Slack — four token types, granular scopes since 2020

[Slack token types](https://docs.slack.dev/authentication/tokens):

- **Bot tokens** (`xoxb-…`) — bot identity, decoupled from any user. Survives users leaving the workspace.
- **User tokens** (`xoxp-…`) — act on behalf of a user; expire with user session.
- **App-level tokens** (`xapp-…`) — span all workspaces an app is installed in; admin-shaped.
- **Configuration tokens** — for editing app manifests via API.

Granular scopes are the post-2020 Slack story: instead of `chat:write` granting "everything chat-related," scopes split into `chat:write`, `chat:write.public`, `chat:write.customize`. Apps request only what they need; the consent screen renders the precise list.

### 4.5 Anytype — pairing-code over OAuth

[Anytype API auth](https://developers.anytype.io/docs/guides/get-started/authentication/) doesn't do OAuth. It does a **challenge-based pairing**:

1. Client supplies an app name → server returns `challenge_id`.
2. Anytype desktop pops a 4-digit code modal.
3. Client posts `challenge_id + 4-digit code` → gets a bearer API key.
4. Bearer used in `Authorization: Bearer <key>` for all subsequent calls.

This is a clean **first-party-by-construction** pattern: the user proves they're at the desktop *and* at the client by entering the 4-digit code. No browser redirect, no consent screen, no DCR. The Raycast extension uses this; CLI tools use this. It's recognizably a descendant of pre-OAuth pairing (Google Auth one-time codes, Spotify Connect device pairing).

### 4.6 Capacities — opaque PAT, all-or-nothing

[Capacities API](https://docs.capacities.io/developer/api): bearer token created in Settings > Capacities API, all-or-nothing scope, RFC 6750 shape. **No traditional OAuth scopes.** No multi-level permissions. Single-user app, single-vault model — the simplification works because the threat model is narrow ("a script I wrote on my laptop").

### 4.7 Logseq — local HTTP API with bearer

[Logseq HTTP API](https://github.com/logseq/docs/blob/master/db-version.md): enable HTTP server in settings, generate a token in Authorization tokens panel, pass as `Authorization: Bearer <token>`. localhost-only by default. Single bearer per server, no OAuth, no consent — just "the user is at the desktop, they made a token, they pasted it."

### 4.8 Tana — per-workspace API token, paste-into-env

[Tana Input API](https://tana.inc/docs/input-api): generate a token at Settings > API Tokens for a chosen workspace; pass as bearer to the input endpoint. MCP integrations stash it in `TANA_API_TOKEN` env. No OAuth surface for the input API. Tana is cloud-only, so the token IS the auth — no operator-vs-third-party distinction needed.

### 4.9 Obsidian — filesystem, no API

Useful contrast: [Obsidian community plugins](https://obsidian.md/help/Plugins/Community+plugins) — Obsidian has no first-class HTTP API. Plugins access the filesystem directly because the user trusts the plugin via install. Third-party services that want Obsidian data either install a community plugin (Local REST API plugin, etc., which then have their own per-user tokens) or work via filesystem sync. **The "no API at all" path is a real choice** that some users prefer for security.

### 4.10 Supabase — anon vs service vs per-user JWT, three-axis

[Supabase API keys](https://supabase.com/docs/guides/api/api-keys) (2025 redesign, [JWT signing keys post](https://supabase.com/blog/jwt-signing-keys)):

- **Publishable / anon key** — exposed in frontend, RLS-enforced, no privilege.
- **Service role key** — backend-only, bypasses RLS, full data access. Asymmetric JWT signing for safer rotation.
- **Per-user JWT** — issued by Supabase Auth, carries `is_anonymous` and other claims, used by RLS policies via `auth.uid()`.

The pattern is **identity-bearing JWT + row-level policy enforcement**. The token shape is uniform; the *capability* differs by claim. This is the model Parachute could move toward but doesn't — vault's enforcement is at the audience-and-scope level, not row-level.

### 4.11 OAuth 2.0 for First-Party Applications draft

[draft-ietf-oauth-first-party-apps-02](https://datatracker.ietf.org/doc/draft-ietf-oauth-first-party-apps/): a 2024-2025-era IETF draft introducing an `/authorize-challenge` endpoint specifically because **for first-party native apps, the browser redirect is friction without security gain**. The draft is explicit:

> The specification applies **only to first-party applications**. Using this specification in scenarios other than those described may lead to unintended security and privacy problems.

It explicitly discourages use in browser-based SPAs (XSS risk, less friction reduction). For native apps where the AS and the app belong to the same brand, the dance becomes:

1. App POSTs to `/authorize-challenge` with credentials directly.
2. AS responds with auth code or "needs MFA / other step" challenge.
3. App handles the challenge in-app (passkey, OTP, etc.).
4. App exchanges the code for tokens at `/oauth/token` — same shape as authorization-code-grant.

The reason this matters for Parachute: it's the IETF acknowledging the exact discomfort Aaron has. **The browser redirect for first-party is *known* friction; the standards body has a draft.** No production library implements it server-side yet, so we'd be early — but the conceptual model is on the standards track.

### 4.12 OAuth 2.0 Security BCP — long-lived bearer threat model

[draft-ietf-oauth-security-topics-29](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics-29): the current OAuth 2.0 Security Best Current Practice. Key relevant guidance:

- **§4.14: refresh tokens for public clients MUST be sender-constrained or use refresh-token rotation.** Hub already does rotation.
- **Sender-constrained access tokens** (DPoP, mTLS) are recommended over plain bearers for high-value tokens. We don't do this today; the audience-binding is the partial substitute.
- **Audience-restricted tokens** are recommended; vault enforces `aud=vault.<name>` already.
- The expanded threat model (A1-A5: web attackers, network attackers, attackers reading auth responses / requests / acquiring access tokens) is explicit. Long-lived plain bearers are the worst case in this model.

**The `operator.token` is the worst-case token by this taxonomy.** 365 days, plain bearer, file-on-disk, broad scopes, un-revocable at issuer.

---

## 5. Comparison table — how do they handle key questions?

| System | Where do API tokens live? | First-party vs third-party | Default for "just me on my laptop"? | Lifetime story | Solo-user story |
|---|---|---|---|---|---|
| **Notion** | Server row keyed by `bot_id` (public) or workspace (internal) | Explicit split: internal connection (paste-bearer) vs public connection (OAuth) | **Internal connection — paste-bearer.** No browser redirect. | OAuth has refresh; internal is indefinite | Excellent — internal is the supported path |
| **GitHub** | Server (PAT) + per-installation-token-mint (Apps) | PAT for self / OAuth for user-delegated / App for org integration | **PAT fine-grained.** No browser redirect for personal scripts. | PATs have explicit expiry, default 1y; App tokens 1h | Excellent — PAT is the primary flow |
| **Linear** | Server row | OAuth for apps; PAT for personal | **PAT scoped to teams + verbs.** | OAuth refresh 1d; PAT indefinite | Good — PAT is supported, scoped |
| **Slack** | Server, per-token-type | Four shapes for four threat models | Bot or user token via OAuth install | Granular, user-token expires with session | Mixed — OAuth-first, but apps can hold long-lived bot tokens |
| **Anytype** | Encrypted local storage on client side | One path: pairing-code-then-bearer | **Pairing-code → bearer.** First-party by construction. | Bearer indefinite; revoke at desktop | Excellent — designed for it |
| **Capacities** | Single bearer, in app storage | Single shape, full access | **Bearer paste, full access.** | Indefinite, manually rotated | Excellent — single-user-by-default |
| **Logseq** | localhost token, single value | Single bearer, localhost-only | **Bearer paste.** No browser. | Indefinite | Excellent |
| **Tana** | Per-workspace token | Single shape | **Bearer paste, env-dropped.** | Indefinite | Excellent |
| **Obsidian** | Filesystem (no central API) | Plugin trust = install trust | **No API surface.** Plugins via install. | n/a | Excellent — "just files" |
| **Supabase** | JWT signing key (anon + service); per-user JWT via Auth | anon + service + per-user-RLS = three axes | Service-role key for backend; user JWT for frontend | Anon: rotated; per-user: hours-with-refresh | Good — for backend-script use, service-role is a paste-bearer |
| **Parachute (today)** | `pvt_*` per-vault DB row + hub-issued JWT (stateless, refresh-stored) + `operator.token` (file) | Implicit via approve-gate; first-party uses `operator.token` for install but OAuth for SPA | **OAuth dance via Notes.** No paste-bearer UI. | Refresh 30d; access 15min; `operator.token` 365d; `pvt_*` indefinite | **Friction.** No "I'm just on my laptop" path |

The pattern is striking: **every mature peer with a "self-hosted, single-user" mode preserves a paste-bearer path.** Notion calls it internal, GitHub calls it PAT, Anytype calls it pairing-code, Logseq/Tana/Capacities just calls it "the token." OAuth is the path for *third-party* clients in every one of these, and the consent screen is preserved for that case. None of them OAuth-for-first-party as the default.

---

## 6. The design questions Aaron is pulling on

After the survey, the questions Aaron raised take a sharper shape.

### 6.1 Should vault and hub have unified or separate token systems?

**Separate, today** — `pvt_*` lives in vault's per-vault DB (hash-stored, no JWT, scope-narrowed at issue); hub-issued JWTs are stateless-signed with hub's JWKS.

**Trade-offs:**

- **Separate (current):** vault can deploy standalone (no hub). The pvt_* mechanism is straightforward — scope, revoke, rotate are local to vault. But the operator sees two token shapes.
- **Unified to hub-as-issuer-only:** vault validates hub-JWTs only, no `pvt_*`. Cleaner mental model but couples vault to a running hub for any auth — the standalone-vault path breaks. **Conflicts with the "no operator → just use tokens" framing**, because the deepest "no operator" case is a vault-only deploy with no hub.
- **Unified the other direction (everything is `pvt_*`-shaped):** even hub mints `pvt_*`-style opaque tokens. Discards the JWT properties (audience-binding, signing, statelessness) and forces every callee to do a row lookup. Throws out the OAuth ecosystem.

**My read** (not a decision): the separate-by-design split is correct *as architecture*; what's wrong is the operator's view. The fix isn't "unify the storage" — it's "give the operator one place to reason about all their tokens."

### 6.2 What's the right primary path for first-party SPAs?

This is the central question. Today: **OAuth-by-default**. Aaron is questioning whether that's right.

**Options:**

- **(A) OAuth-by-default, paste-bearer fallback.** Notes still does OAuth as the primary path; an "I have a token" advanced toggle accepts a `pvt_*` paste. Notion's pattern. Lowest disruption; preserves the consent-aware OAuth dance for the case it makes sense (cross-origin, multi-user, third-party-feeling deploys).
- **(B) Paste-bearer-by-default, OAuth advanced.** Flip the default. Notes' connect screen leads with "Paste a vault token from `parachute vault tokens create`," and an "Or sign in via OAuth" link does the dance. Capacities/Logseq pattern. Lowest friction for solo operator; requires the operator to know how to mint a token.
- **(C) Pairing-code (Anytype-style).** Notes generates a 4-digit code, displays it; operator types it into `parachute auth pair-app` (or admin SPA), which signs a JWT and returns it. No browser redirect; no DCR. Beautiful UX for first-party-ness; requires shipping a new endpoint pair (`/pair-challenge`, `/pair-redeem`). Anytype uses this for Raycast and CLI; Parachute would use it for Notes / agent SPA / MCP-client install.
- **(D) Auto-issued first-party token at install time.** `parachute install notes` provisions a `pvt_*` token via the operator path, writes it into Notes' settings note. Notes-on-first-load reads it and skips auth setup entirely. Operator never sees it. **Lowest friction, lowest awareness.** The agent does this for container secrets already.
- **(E) Implement OAuth 2.0 for First-Party Apps draft.** Browserless OAuth dance with `/authorize-challenge`. Conceptually the cleanest answer to Aaron's discomfort but very early — no production server libraries implement it.

**Trade-offs:**

| | First-run friction | Operator awareness | Cross-origin works? | Third-party still works? | Implementation cost |
|---|---|---|---|---|---|
| (A) OAuth+paste fallback | Medium (one click on consent for first-party; advanced toggle for paste) | Medium | Yes | Yes | Low — UI work in Notes |
| (B) Paste+OAuth advanced | High first time (operator must mint token) but zero per-flow | High (operator handles token) | Yes if pasted | Yes | Low — UI work in Notes |
| (C) Pairing-code | Low (4 digits) | High | Yes (loopback only on hub side) | No (third-party stays OAuth) | Medium — new endpoints, UI |
| (D) Auto-issue at install | Zero | Low (operator unaware) | n/a (no first-run) | Yes (third-party stays OAuth) | Medium — install-step work, settings-note plumbing |
| (E) First-Party Apps draft | Low | Medium | Yes | Yes | High — early-adopter implementation |

### 6.3 What's the right primary path for third-party clients?

**OAuth, full stop.** claude.ai connectors only do OAuth + DCR + PKCE [Claude support](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers). The consent screen + approval gate is genuine value for adversarial registration. Every option above leaves OAuth in place for third-party.

The question is whether OAuth should *also* be the path for first-party. The industry answer is uniformly **no**; the "first-party uses bearer" default is the consensus.

### 6.4 Long-lived bearer tokens — what's the threat model?

Two long-lived bearers exist today: `operator.token` (365d, file, broad scopes, un-revocable) and `pvt_*` (no expiry by default, hashed in DB, scope-narrowed, revocable).

**Threat surfaces:**

- **`operator.token` exfiltration via filesystem read.** A malicious npm postinstall, a process that runs as the operator user, a forgotten `cat ~/.parachute/operator.token` in shell history. The 0600 permission protects from other unix users, not from same-user processes.
- **`pvt_*` exfiltration via copy-paste.** Pasted into a script's source, leaks to GitHub. Common pattern; GitGuardian-class scanners detect `pvt_` prefix.
- **Browser localStorage exfiltration via XSS.** Any same-origin script can read `lens:token:<id>` etc. Notes' tokens (15min access, 30d refresh) are the surface. XSS is a real threat for any SPA.
- **Cloud / shared deployment.** Shifts every threat. The single-user-on-laptop assumptions don't hold.

**Mitigations the ecosystem already has:**

- Hub access tokens are 15 minutes — the XSS-stolen access token is a 15-minute window.
- Refresh tokens rotate on use; replay revokes the family.
- DCR approval gate keeps adversarial clients from registering silently.
- Vault's tag-allowlist and per-vault-binding scope `pvt_*` damage.

**Mitigations the ecosystem doesn't have:**

- `operator.token` revocation. The only path is `parachute auth rotate-key`, which retires every JWT for 24h.
- `pvt_*` default expiry. Operator must explicitly set `--expires-at`.
- DPoP / mTLS sender-constraining. Standard in OAuth Security BCP recommendations.
- Session-cookie-style sliding expiration on refresh tokens.

**Defaults question:** for a single-user-on-laptop install, the current bearer story is reasonable. For multi-user or cloud, it's not. The architecture should let the **operator pick the threat-model intensity** — not impose one default everywhere.

### 6.5 Refresh token mechanism — do we have one? Should we?

**Yes, we have one** — RFC 6749 §6 with rotation + family revocation, 30-day refresh, 15-minute access. [`parachute-hub/src/oauth-handlers.ts:991-1090`] This is correct and modern.

**The question is about the OTHER long-lived tokens.** If a first-party SPA gets an auto-issued token at install (option D in §6.2), what's the rotation story? Some options:

- Make it an OAuth refresh-token-style rotation pair, so every browser load rotates.
- Make it a `pvt_*` with a forced 90-day expiry.
- Don't rotate; treat install-time tokens as session-shaped (lost laptop = re-install).

### 6.6 Multi-user and future deployment shapes

Today: single operator per hub (`single-user mode is the default; pass --allow-multi to add more`, [`parachute-hub/src/commands/auth.ts`]).

Cloud-shape research ([`parachute-cloud/`](../../parachute-cloud), [`parachute.computer/design/2026-04-20-cloud-offering-sketch.md`](../../parachute.computer/design/2026-04-20-cloud-offering-sketch.md)) talks about multi-tenant. Auth implications:

- Per-tenant signing keys (so a tenant's tokens can't be replayed across tenants).
- Per-tenant DCR client lists.
- Per-tenant `operator.token`-equivalent for tenant-admin paths.

Multi-user-on-one-host (family of two installations) is a smaller scope — same hub, multiple users with `--allow-multi`. Auth shape works but the consent screen, tag-allowlist, and admin SPA all need multi-user awareness that isn't fully there.

### 6.7 Operator vs agent identity

Today the operator and the agent share identity — the agent SPA gets an OAuth JWT signed against the operator's user. There's no first-class "agent identity" with its own credential lifecycle.

In the GitHub Apps shape, the agent would have its own identity (GitHub-App-equivalent) with installation tokens (1h TTL, minted from app private key signing). This gives:
- Distinct revocation (revoke agent without logging out operator).
- Distinct scope vocabulary (`agent:*` mints can be different shape than user-OAuth scopes).
- Audit trail separation.

We don't have this. The agent's container path uses the operator's tokens via the secrets store ([§2.4](#24-agent--parachute-agent)).

### 6.8 Cross-vault / multi-vault scenarios

**Solved:** scope vocabulary (`vault:<name>:<verb>`), per-vault token-DB binding (vault#258), tag-allowlist intersection (vault#241), audience-binding on hub-issued JWTs (`aud=vault.<name>`).

**Not solved at the operator-experience level:** "I have a token, what does it grant?" UI. The admin SPA's token-list view is per-vault; cross-vault listing exists at hub level but isn't a first-class affordance.

---

## 7. Three candidate architectures

These are sketches, not designs. Each is a coherent shape; each makes different trade-offs. **I lean toward (B) but it's Aaron's pick.**

### 7.1 Option A — keep current shape, fix the operator surface

**One-line summary:** Don't change the architecture. Make the operator's view of "what tokens exist" coherent.

**Shape:**

- Notes still does OAuth-by-default for SPA connect.
- `pvt_*` and hub-issued JWTs continue to coexist as today.
- Add an "advanced: paste a token" UI option in Notes for the script-user case.
- Build a single token-management surface in the admin SPA: list every `pvt_*`, every active OAuth grant, every operator-token, every refresh-token family. Revoke from one place.
- Default `pvt_*` to 1-year expiry (matching GitHub fine-grained PATs).
- Add an `operator.token` revocation list at the hub (track JTIs for issued operator tokens; reject revoked ones at validation).

**Migration cost:** Low. Each piece is independent. Ship in parts.

**Gives up:** the deeper question of whether OAuth-as-default-for-first-party is right.

### 7.2 Option B — promote a paste-bearer path to first-class for first-party

**One-line summary:** Notes leads with paste-a-vault-token; OAuth becomes the third-party / cross-origin path.

**Shape:**

- Notes' AddVault screen has two equal-weight options: "Paste a vault token" (default, leftmost) and "Sign in via OAuth" (advanced or for cross-origin).
- `parachute install notes` (or the first-run flow) auto-mints a scoped `pvt_*` and writes it into Notes' local settings — operator opens Notes to a fully-connected state. Modeled on Notion's internal-connection token.
- Third-party clients (claude.ai connectors, anything with cross-origin) still use the OAuth dance. The DCR approval gate stays.
- `operator.token` retains its role for `parachute install` flows; the broad-scope leak risk is addressed by:
  - Adding a JTI-revocation list at the hub.
  - Splitting `operator.token` into a narrower scope set; the broad form becomes opt-in for cases that genuinely need cross-vault provisioning.
- Vault and hub keep their separate token systems but the operator surface unifies — admin SPA shows all tokens; CLI has one `parachute auth list-tokens` that walks both.

**Why this is the lean:**

- It matches the industry consensus (Notion, GitHub, Linear, Capacities, Logseq, Anytype, Tana — every peer with single-user-self-hosted as a real use case).
- It removes the "App not yet approved" friction Aaron's cousin hit, because the OAuth dance becomes opt-in not default.
- It preserves the OAuth + consent for the case where it's doing real work (third-party, multi-user, cross-origin).
- It's the smallest semantic shift — vault already has `pvt_*`; we just give it a UI front door in Notes.

**Migration cost:**

- Moderate. Notes UI work (AddVault redesign, paste-token field, validation, error messaging). Hub install-step work (auto-mint at install, write to Notes settings note). Admin SPA work (cross-token-list view).
- Operators with existing OAuth-connected Notes installs continue to work (the OAuth path stays). New installs default to paste-bearer-with-auto-mint.
- Documentation needs to reframe: "OAuth is for cross-origin and third-party; same-origin first-party uses tokens."

**Gives up:**

- The browserless OAuth ceremony for first-party. Some power-users may prefer the explicit consent-screen-every-time flow; (A) preserves it, (B) makes it opt-in.
- Some consent-screen affordances (vault picker, scope review) only show on the OAuth path. Paste-bearer assumes the operator picked the right scope at mint time.

### 7.3 Option C — pairing-code as the unifying primitive

**One-line summary:** Anytype-style 4-digit pairing for first-party clients (Notes, agent SPA, MCP setup), OAuth retained for third-party.

**Shape:**

- Hub adds `/auth/pair-challenge` (returns `challenge_id` + 4-digit code, displays code in admin SPA / `parachute auth pair --show-code`) and `/auth/pair-redeem` (challenge_id + code → JWT).
- Notes' connect flow: "Open Parachute admin and enter this code: 1234." User types in admin SPA, code validated, JWT returned to Notes via the polling endpoint or relay.
- `parachute mcp install` (CLI tool for adding Parachute MCP to Claude Code) generates a code, prompts operator: "Enter `parachute auth pair 4815` in another terminal." Operator types it; CLI gets JWT, writes to Claude config.
- Third-party (claude.ai connectors) still does OAuth.
- `pvt_*` continues to exist as the script / scheduled-task path.
- `operator.token` retains its install-time role.

**Why this is interesting:**

- It's the most ergonomic *for first-party*. No browser redirects, no consent screens, no localStorage shuffling. The 4-digit pairing is the operator's "I'm here, I see this" signal.
- It works **identically** for browser SPAs, terminal CLIs, and MCP clients. One mechanism for every first-party-shaped client.
- Anytype validates this in production; Raycast extension users genuinely prefer it to OAuth dances.

**Migration cost:**

- High. New endpoints. New SPA UI. New CLI command. Polling / WebSocket for the "waiting for pair" state. Code-display surface in admin SPA. Documentation.
- Existing OAuth flows can stay (Notes still works); pairing is additive.

**Gives up:**

- Standardness — pairing-code isn't an IETF spec. We'd be inventing the protocol shape (Anytype's choices are reasonable but not blessed).
- Complexity for a UX win. The OAuth flow already exists and works.
- Doesn't solve the third-party case at all (we'd still maintain full OAuth).

---

## 8. Migration considerations

For (A) — incremental, no migration. Each piece ships standalone.

For (B):
- **Phase 1:** Add paste-bearer UI in Notes alongside OAuth. Both work. Operators who want to switch can.
- **Phase 2:** Auto-mint at `parachute install notes` (or on first hub start with notes installed). Pre-write the `pvt_*` into Notes' settings note. New installs land connected.
- **Phase 3:** Reframe docs — paste-bearer is the first-party path, OAuth is the third-party path.
- **No deprecation needed** for OAuth; it stays for cross-origin / third-party.

For (C):
- **Phase 1:** Ship `/auth/pair-*` endpoints + admin SPA code-display surface.
- **Phase 2:** Add Notes' "enter pairing code" flow alongside OAuth.
- **Phase 3:** `parachute mcp install` adopts pairing for first-party MCP setup.
- **Long deprecation tail** if/when OAuth-for-first-party retires (probably never; keep both).

---

## 9. Open questions — Aaron's calls

> **Update 2026-05-09:** Q4 (operator.token rework) and the standalone-vault / revocation-latency questions implicit elsewhere now have answers — see §11. Q4 ships independently as [hub#213](https://github.com/ParachuteComputer/parachute-hub/issues/213); standalone vault is preserved via library factoring (§11.7); revocation goes via a hub-published revocation list with sub-minute latency (§11.6). Q1, Q2, Q3, Q5, Q6 remain live or are subsumed by the §11 direction.

1. **Brand positioning: "your data on your machine" vs "your data on a managed service."** Auth implications differ:
   - "On your machine" — single-user, paste-bearer or pairing-code is the natural shape; OAuth ceremony is *uncharacteristic friction*.
   - "On a managed service" — multi-user, OAuth + consent screens is *expected ceremony*.
   The brand we're shipping into determines which default is right. Today's product positioning is mostly the first; the architecture defaults are mostly the second. That's the seam Aaron is feeling.

2. **"Just works" for novices vs "operator-controlled" for power users — which is the default?**
   - If novice-default: option (B) Phase 2 auto-mint wins. Operator-installs-Notes → opens-Notes → connected. Zero friction. Operator never sees a token unless they need to revoke.
   - If power-user-default: option (A) plus a paste-bearer fallback. Operator mints tokens explicitly; Notes connects via OAuth-or-paste; no auto-issue magic.
   This is a values call.

3. **How much OAuth ceremony do third-party connectors actually require?** A real test against claude.ai would inform — probably worth doing before committing to a path. claude.ai's expectation is full DCR + PKCE [Claude support](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers); we ship that today; the question is whether the consent screen's vault-picker and scope-review do real work for that user, or whether it's Notion-internal-style "the operator owns both ends" that feels like ceremony.

4. **Is there an `operator.token` rework that's worth doing regardless of the bigger choice?**
   - Add JTI revocation list (`tokens` row, family-style); enable `parachute auth revoke-operator-token <jti>`.
   - Split the broad scope set: `parachute auth rotate-operator --scope-set install` mints with just the install-time scopes (`hub:admin`, narrow vault scopes); `--scope-set full` for the current 5-scope blanket. Defaults to install.
   - Default 90 days, max 365.
   These mitigate the worst-case-bearer concern in §4.12 without committing to a bigger architectural change.

5. **Should `pvt_*` default to expiring?** GitHub PAT fine-grained max is 1 year and unbounded is opt-in. We default to no expiry. Defaulting to 1 year (matching GitHub) is a small, low-risk change that brings us into the consensus.

6. **Where does the operator see "all my tokens" today?** Two surfaces (hub admin SPA, `parachute vault tokens list`) covering different subsets. Worth unifying into one CLI + one admin view, regardless of which architecture wins.

---

## 10. Recommendations (light-touch, not a decision)

If Aaron asked me what to ship next, ordered by ROI:

1. **Auto-mint at install for Notes (option B Phase 2 piece).** Removes the connect-screen friction entirely for the same-host case. Most "App not yet approved"-class issues stop happening. Doesn't lock us into anything bigger.
2. **Paste-bearer UI in Notes (option B Phase 1 piece).** Even without auto-mint, gives operators with `pvt_*` tokens an obvious paste path. ~50 lines of UI + plumbing.
3. **`operator.token` JTI-revocation list and 90-day default (regardless of bigger choice).** The leak-risk worst case is the leverage point.
4. **`pvt_*` default expiry of 1 year.** Joins the GitHub consensus. Existing tokens grandfathered.
5. **Cross-token admin SPA view.** "Show me everything authenticating against this hub." Operator awareness compounds every other security feature.

These five are independent, additive, and don't require a top-level architectural choice. If Aaron wants to take a bigger swing, **option B** is what I'd lean toward — but it's built on top of these five, not instead of them.

---

## 11. The decision (2026-05-09)

Aaron and team-lead converged on the architectural direction this evening. The decision adopts Option B's premise (consolidate the operator surface; lean into industry consensus on N-tier credential pluralism) and extends it with a structural separation that none of A/B/C captured directly: **the auth-server / resource-server split is made formal across the ecosystem.**

Migration tracker: [parachute-hub#212](https://github.com/ParachuteComputer/parachute-hub/issues/212).

### 11.1 The shape

**Hub becomes the sole authorization server. Vault, agent, scribe become resource servers.**

- Every token in the ecosystem is minted by hub. Every resource server validates against hub's JWKS + revocation list.
- Vault's local `pvt_*` path is deprecated and removed. The only minted-credential surface is hub.
- Standalone vault (the no-hub deployment) is preserved as a future option via library factoring — see §11.7.
- The operator's mental model collapses to one: "tokens come from hub."

This formalizes what was already structurally true — hub already issues OAuth JWTs that vault validates ([`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md)). The change is making it the *only* path and retiring `pvt_*`.

### 11.2 Scope vocabulary

Two shapes, depending on whether the resource has multiple instances:

- **Multi-instance:** `<module>:<instance>:<verb>` — `vault:default:read`, `vault:default:write`, `agent:wovenboulder:invoke`. Mirrors today's `vault:<name>:<verb>` shape ([`parachute-vault/src/scopes.ts:122-135`]) and extends it ecosystem-wide.
- **Singleton:** `<module>:<verb>` — `parachute:host:admin`, `hub:user:profile`. For surfaces where the instance dimension doesn't apply.

The verb stays close to today's vocabulary (`read` / `write` / `admin` / `invoke`). Agent and scribe inherit the pattern as they migrate; their existing scope shapes become aliases or get rewritten in lockstep with the registry rollout.

### 11.3 Rich constraints live in a custom JWT claim, not in scope strings

The `scope` claim stays standard OAuth (space-separated coarse capabilities). Fine-grained shape — tag-allowlist, field-scope, future per-record constraints — moves into a custom `permissions` claim:

```json
{
  "iss": "https://hub.parachute.computer",
  "sub": "operator",
  "aud": "vault.default",
  "scope": "vault:default:write agent:wovenboulder:invoke",
  "permissions": {
    "vault": {
      "default": {
        "write_tags": ["health", "food"]
      }
    }
  },
  "jti": "...",
  "exp": ...
}
```

**Why this shape:** GitHub fine-grained PATs use the same model — coarse capability in standard scope, fine-grained constraint in a parallel structured field. Standard OAuth tooling (resource servers, JWT validators, audit log readers) keeps working against the `scope` claim. Resource servers that *care* about fine-grained constraints read `permissions` after they pass the scope check.

This subsumes today's vault `scoped_tags` mechanism ([`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md)) — `scoped_tags` becomes `permissions.vault.<instance>.write_tags` in the JWT. The auth-check semantics ([`patterns/tag-scoped-tokens.md` §Storage details]) are unchanged; the storage is "in the JWT claim that hub minted" instead of "in the vault token row hub never sees."

### 11.4 Hub gains a token registry table

Hub already has a `clients` table for OAuth registrations. This adds a sibling: `tokens`.

| Column | Purpose |
|---|---|
| `jti` | Primary key. Set on mint, embedded in JWT, used for revocation lookup. |
| `subject` | The operator / agent / service the token represents. |
| `scope` | Standard OAuth scope claim, persisted for admin display. |
| `permissions` | JSON, persisted for admin display. |
| `issued_at` | Mint timestamp. |
| `expires_at` | Hard expiry from JWT `exp`. |
| `revoked_at` | Nullable; set when revoked. Drives the revocation list (§11.6). |

Backs both the admin UI (§11.5) and the revocation list (§11.6).

### 11.5 Hub admin UI for token management

**`/admin/tokens` route.** Lists every issued token with human-readable scope rendering (uses [`parachute-hub/src/scope-explanations.ts`](https://github.com/ParachuteComputer/parachute-hub) — same surface that powers the OAuth consent screen). Per-row actions: revoke (sets `revoked_at`, propagates to the revocation list), inspect (shows full claim shape).

This is the operational substrate that makes hub-as-sole-AS workable. Without it, "all tokens come from hub" creates a single-pane-of-glass *requirement* without delivering one.

### 11.6 Revocation list

**Hub publishes the set of revoked `jti`s.** Resource servers fetch on a ~60s TTL and check on every token validation. Sub-minute revocation latency.

- Endpoint shape: simple `GET /revoked.json` returning `{ jtis: [...], generated_at: "..." }`. Cacheable, signed-or-trusted-via-TLS (the revocation list itself doesn't need OAuth gating; published-once-public is fine).
- Resource servers (vault, agent, scribe) cache for 60s, refetch on miss, fail-open if hub is unreachable (preserve availability) or fail-closed (trade availability for security) — that's a per-RS knob.

Aaron explicitly chose **"fast revocation matters"** over "expiry-based is fine." The §4.12 `operator.token` "un-revocable at issuer" leak-risk pattern goes away across the ecosystem — every minted token can be killed in <60s.

> **Update 2026-05-28 — admin-scope replacement → general capability attenuation; arc LANDED.** The pvt_* removal (Phase 6, vault#282) had one unmet precondition: `vault:<name>:admin` had no headless hub-mint path. Hub's `POST /api/auth/mint-token` refused it via the non-requestable-scope guard, so `parachute vault mcp-install` and the vault admin SPA tokens page fell back to minting pvt_*. **Approved decision (option 1):** relax the guard to mint `vault:<name>:admin` **when, and only when, the calling bearer carries `parachute:host:admin`** — a privilege *de-escalation* (vault-pinned admin descends from box-wide admin), so it's principled, not a loosening. A `parachute:host:auth`-only bearer still cannot mint vault-admin. The CLI uses `operator.token`; the SPA uses the existing `session → /admin/host-admin-token → mint-token` chain (no new endpoint). This carve-out then **generalized into capability attenuation** — *any bearer may mint OR revoke a token whose authority is a subset of its own* (`canGrant` in `parachute-hub/src/scope-attenuation.ts`): host:auth→requestable, host:admin→`vault:<N>:admin`, `vault:<N>:admin`→same-vault subtokens. Minted tokens are durable (90d default, 365d max), audience-bound, `vault_scope`-pinned, and ride this revocation list. This closes the admin gap **and** lets manage-token + the SPA proxy to hub instead of issuing pvt_*, so vault#282 can retire pvt_* **entirely** — vault becomes a pure resource-server. **The §11.3 `permissions` claim is now live too:** tag-scoped tokens ride the hub JWT in `permissions.scoped_tags`, scope-guard 0.4.0-rc.2 surfaces it (hub#453), and vault enforces it fail-closed (vault#403/#407, "C0") — so the tag-scope axis strands nothing at vault#282 either. **Landed across hub (#449/#452/#453/#454/#455) + vault (#397/#403/#405/#406/#407); only the breaking DROP (vault#282) remains, gated on the human.** Adversarial audit: 5 findings, 0 P0/P1 (the 2 residual P2s are closed-by-DROP). Full design: [`../../parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md`](../../parachute.computer/design/2026-05-28-operator-mintable-vault-admin.md); propagation checklist: [`../migrations/2026-05-28-operator-mintable-vault-admin.md`](../migrations/2026-05-28-operator-mintable-vault-admin.md).

### 11.7 Standalone vault preserved via library factoring

The auth-server logic (mint, registry, revocation, scope-explanation) extracts into a library — `auth-server` — modeled on how [`scope-guard`](https://github.com/ParachuteComputer) was extracted from per-module reimplementation into a shared dep.

- Hub embeds `auth-server` as its production deployment surface.
- A standalone vault deployment (no hub in the picture) embeds `auth-server` directly. The vault becomes its own AS+RS.
- The library factoring is the contract: the operator's mental model "tokens come from one auth server" stays consistent — that AS is hub in the standard deployment, and vault-itself in the standalone deployment.

Not for now. Documented as the path that keeps the option open. Recorded here so future-us doesn't re-decide.

### 11.8 CLI relocates

```
parachute vault tokens create  →  parachute auth mint-token --scope=vault:default:read,...
```

Hub becomes the auth surface in operator vocabulary. The `parachute auth` namespace (already partially present per §2.1) becomes the canonical home for every minted-credential operation: mint, list, revoke, inspect.

A migration helper ships in the same CLI release: `parachute auth migrate-pvt-tokens` walks each vault's local `pvt_*` rows, prompts the operator to remint as hub-issued JWTs with equivalent scope + permissions claims, then drops the `pvt_*` row. Idempotent; safe to re-run.

### 11.9 Migration phases

Sketched in [hub#212](https://github.com/ParachuteComputer/parachute-hub/issues/212):

1. **Hub gains token registry + mint API.** Both `pvt_*` and JWT validation paths stay live. New tokens land as JWT-by-default; `pvt_*` becomes the legacy path.
2. **Hub gains admin UI** (`/admin/tokens` route, list + revoke).
3. **Hub gains revocation list** (`GET /revoked.json` endpoint, populated from `tokens.revoked_at`).
4. **Vault, agent, scribe gain revocation-list consultation** (poll on 60s TTL, check on every token validation).
5. **CLI relocation + migration helper** (`parachute auth mint-token` becomes canonical; `parachute auth migrate-pvt-tokens` lifts existing `pvt_*` rows into hub-issued JWTs).
6. **Vault `pvt_*` deprecated then removed.** The `pvt_*` column + validation path goes away once the migration helper has run across the operator base.

Phases 1–4 are additive; the system stays operational throughout. Phase 5 is the operator-facing flip. Phase 6 is the cleanup.

### 11.10 `operator.token` quick-fix is independent

The 365-day, broad-scope, un-revocable `operator.token` shape is the worst-case bearer per [draft-ietf-oauth-security-topics-29](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics-29) and worth shipping a hardening fix on its own — independent of the larger AS/RS migration.

Tracked at [hub#213](https://github.com/ParachuteComputer/parachute-hub/issues/213). Roughly: shorten to 90-day default (max 365), split scope sets (`install` narrow vs `full` blanket), add JTI revocation. None of this blocks or is blocked by hub#212; ship in parallel.

### 11.11 Why this over the original A/B/C

- **Option A (keep current shape, fix operator surface)** doesn't address the structural duplication — vault and hub continue to mint independently. The "two token systems" complaint Aaron flagged stays.
- **Option B (paste-bearer first-class for first-party)** addresses the operator-UI complaint but leaves the AS/RS axis tangled — vault still mints `pvt_*`, hub still mints JWT, the "where do tokens come from" answer stays "depends." The convergence keeps Option B's first-party-paste premise (paste a hub-minted JWT; UI affords this) while making the AS/RS split formal.
- **Option C (pairing-code)** stays available as a future first-party flow on top of hub-as-sole-AS. Pairing-code becomes one of several mint surfaces hub exposes, not a replacement for the AS/RS shape.
- **Cross-module token composition** is structurally impossible without a single AS. A token that grants `vault:default:read` AND `agent:wovenboulder:invoke` requires one issuer that knows both; that's hub.
- **Standalone vault** stays viable via §11.7's library factoring, so the "no-hub deployment" use case isn't sacrificed.

---

## Sources

### Parachute internals (file:line)
- `parachute-hub/src/operator-token.ts:21-37, 59-74` — operator token mint, scopes, TTL.
- `parachute-hub/src/sessions.ts:18-19, 93-106` — session cookie shape.
- `parachute-hub/src/jwt-sign.ts:32-33` — `ACCESS_TOKEN_TTL_SECONDS = 15*60`, `REFRESH_TOKEN_TTL_MS = 30d`.
- `parachute-hub/src/oauth-handlers.ts:1305-1393` — DCR + four-path approval gate.
- `parachute-hub/src/oauth-handlers.ts:706-757` — inline approve button (#208/#209).
- `parachute-hub/src/oauth-handlers.ts:991-1090` — refresh token rotation + family revocation.
- `parachute-hub/src/scope-explanations.ts:35-69, 107-129` — first-party scopes, non-requestable scopes.
- `parachute-vault/src/auth.ts:161-238, 253-284` — dual-shape resolver, hub-JWT validation.
- `parachute-vault/src/scopes.ts:122-135, 169-198` — `hasScopeForVault`, `validateMintedScopes`.
- `parachute-vault/src/token-store.ts:99-109, 115-119, 151-191` — `pvt_*` shape, scoped_tags column.
- `parachute-notes/src/lib/vault/oauth.ts:43-93` — Notes OAuth dance.
- `parachute-notes/src/lib/vault/discovery.ts:14-42, 49-92` — RFC 8414 + 7591 calls.
- `parachute-notes/src/lib/vault/storage.ts:5-12, 118-128` — token + DCR storage in localStorage.
- `parachute-notes/src/app/routes/AddVault.tsx:31-51` — connect flow (no paste-bearer).
- `parachute-agent/web/ui/src/lib/auth.ts:18-26, 167-200, 380-398` — agent SPA OAuth.
- `parachute-agent/src/container-runner.ts` (`PARACHUTE_HUB_ORIGIN` injection).
- `parachute-scribe/src/auth.ts:54-73` — JWT-aware shared-secret seam.

### Patterns repo
- [`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md)
- [`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md)
- [`patterns/token-auth.md`](../patterns/token-auth.md)
- [`patterns/oauth-dcr-approval.md`](../patterns/oauth-dcr-approval.md)
- [`patterns/service-to-service-auth.md`](../patterns/service-to-service-auth.md)
- [`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md)
- [`patterns/dev-auto-user.md`](../patterns/dev-auto-user.md)
- [`research/cloudflare-hosted-vault.md`](./cloudflare-hosted-vault.md)
- [`research/tag-scoped-tokens-survey.md`](./tag-scoped-tokens-survey.md)
- [`research/tana-deep-dive.md`](./tana-deep-dive.md)

### Industry references
- [Notion — Authorization](https://developers.notion.com/docs/authorization) — internal vs public connections.
- [GitHub — Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) — classic vs fine-grained, GitHub Apps.
- [Linear — API and Webhooks](https://linear.app/docs/api-and-webhooks) — OAuth + Personal API Keys, Linear scopes.
- [Linear — OAuth 2.0](https://linear.app/developers/oauth-2-0-authentication) — refresh-rotation since 2026-04-01.
- [Slack — Token types](https://docs.slack.dev/authentication/tokens) — bot / user / app-level / configuration.
- [Anytype — Authentication](https://developers.anytype.io/docs/guides/get-started/authentication/) — challenge-based pairing.
- [Anytype — Create API Key](https://developers.anytype.io/docs/reference/2025-05-20/create-api-key/) — API endpoint reference.
- [Capacities — API](https://docs.capacities.io/developer/api) — single bearer, all-or-nothing.
- [Logseq DB Mode — HTTP API](https://github.com/logseq/docs/blob/master/db-version.md) — local bearer, localhost-only.
- [Tana — Input API](https://tana.inc/docs/input-api) — per-workspace bearer.
- [Supabase — API Keys](https://supabase.com/docs/guides/api/api-keys) — anon / service / per-user JWT.
- [Supabase — JWT Signing Keys](https://supabase.com/blog/jwt-signing-keys) — 2025 redesign with asymmetric signing.
- [Supabase — Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security) — RLS-as-auth-shape.
- [Obsidian — Community Plugins](https://obsidian.md/help/Plugins/Community+plugins) — filesystem-only, no API.
- [draft-ietf-oauth-first-party-apps-02](https://datatracker.ietf.org/doc/draft-ietf-oauth-first-party-apps/) — OAuth for first-party native apps.
- [draft-ietf-oauth-security-topics-29](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics-29) — OAuth Security BCP, threat model.
- [Claude support — Building custom connectors via remote MCP servers](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers) — claude.ai's OAuth + DCR expectation.
- [Logto blog — Why you should deprecate ROPC](https://blog.logto.io/deprecated-ropc-grant-type) — password grant deprecation reasoning.
- [oauth.net — Password Grant](https://oauth.net/2/grant-types/password/) — formal deprecation in OAuth 2.1.
