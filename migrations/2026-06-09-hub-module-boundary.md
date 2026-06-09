# Migration: the hub–module boundary (thin hub / module-owned lifecycle)

**Decided:** 2026-06-09 (Aaron — "make sure we have an aligned direction, and
then chart a path and build this"). **Pattern:**
[`patterns/hub-module-boundary.md`](../patterns/hub-module-boundary.md).
**Grounding:** 7-repo multi-agent audit + 5-lens adversarial design review
(10 blocking / 17 serious findings, all folded below), 2026-06-09.

The shift: vault's instance-lifecycle UX moves into vault's own surface at
**`/vault/admin/`** (completing the `channel/admin` · `scribe/admin` ·
`surface/admin` · `vault/admin` symmetry); the hub keeps the identity
transactions and gains the missing **delete cascades**; the seam mechanisms
get hardened; the docs stop contradicting each other.

**Sequencing law (version skew on real boxes):** hub and vault upgrade
independently (both rc chains in flight). Order: **Phase A docs → hub wave 1
(B0+B1+B2h+B4h+route) → vault wave (B2v+B3+manifest) → hub wave 2 (B5,
feature-detected) → C → D.** Every hub-side semantic change ships with a
one-release compat shim for the old vault manifest.

## Phase A — docs (this PR)

- [ ] `patterns/hub-module-boundary.md` — the charter (new; includes the
      panel-added sections: lifecycle-symmetry definition + registered-mint
      rule, per-module-view definition, trust-statement XSS honesty, the
      vault-only-identity Known gap, the corrected third-party test)
- [ ] this file (new)
- [ ] `patterns/oauth-scopes.md` — (a) provisioning re-framed: hub owns the
      *transaction*, the module's surface owns the UX; (b) fix the internal
      synonym-vs-enforced contradiction on `vault:<name>:<verb>` (enforced is
      current truth); (c) mark the pvt_* paragraph superseded (consistent
      with token-auth.md's banner); (d) move `agent:*` scopes to a
      retired-scopes note
- [ ] `patterns/module-ui-declaration.md` — **full rewrite of §Resolution
      rules + §Multi-instance + §Rules + vault examples** (they teach the
      mount-prefixing of `"/admin/"` that B4 retires); resolve the
      provisioning-ownership contradiction with oauth-scopes; document the
      resolveManagementUrl-family per-instance-relative contract
- [ ] `patterns/module-json-extensibility.md` — §managementUrl resolution
      semantics rewritten to match B4 (leading-`/` = origin-absolute)
- [ ] `patterns/module-surfaces.md` — remove the standing license for
      "admin SPA route inside hub" as a valid module admin-UI shape (the
      hub#624 failure mode); add hub-module-boundary to Related
- [ ] `patterns/design-system.md` — §admin-SPA verb/title tables +
      §Circle-1 surface list: retire `/admin/vaults` create-form refs, add
      `/vault/admin/`
- [ ] `patterns/token-auth.md` — supersession banner (pvt_* module-as-issuer
      retired; hub-minted JWTs per tag-scoped-tokens.md + 2026-05-28
      migration)
- [ ] `design/2026-06-09-modular-ui-architecture.md` — amend the "genuinely
      hub-level" list: vault *provisioning UX* is NOT hub-level; the
      transaction endpoint is
- [ ] `migrations/2026-06-09-modular-ui.md` — cross-link note
- [ ] `adoption/migration-notes.md` — entry for this shift
- [ ] run `scripts/audit-canonical-refs.sh` with `uiUrl` / `managementUrl` /
      `/admin/vaults` added to the sweep before merging

## Phase B — vault lifecycle (the flagship)

### Hub wave 1 (one hub release; lands FIRST)

- [ ] **B0 (prerequisite): register the connections engine's long-lived
      mints.** `admin-connections.ts` mints two 90-day tokens (channel reply
      token `vault:<v>:write` + webhook bearer) via `signAccessToken` with NO
      `recordTokenMint` — no registry row → unrevocable until expiry, and
      `teardownConnection` deletes channel's *copy*, not the credential.
      Fix: record both mints (`created_via: "connection_provision"`), persist
      the jtis on the ConnectionRecord, make teardown revoke them. Existing
      connections are NOT auto-rotated (settled in hub#637): legacy records
      are flagged `legacy: true` on the list wire shape and their unregistered
      mints ride to original expiry — re-create a connection to get revocable
      credentials. Charter rule: any mint with TTL beyond ~10 min MUST be
      registered. (hub)
- [ ] **B1 hub: `DELETE /vaults/<name>`** (host:admin Bearer; explicit
      `confirm: "<name>"` body). Mechanics: shell to
      `parachute-vault remove --yes` (module CLI stays the source of truth,
      mirroring create). Cascade, enumerated (the lifecycle-symmetry
      checklist):
      - registry sweep: revoke every tokens-row whose scopes name the vault —
        **split + exact-match scope segments, never SQL `LIKE`** (`_` in
        vault names is a LIKE wildcard);
      - grants: **rewrite** each grant's scope list removing
        `vault:<name>:*` entries; drop the row only when empty (a row can
        name multiple vaults — dropping it over-revokes);
      - `user_vaults` rows for the vault;
      - **invites**: invalidate unredeemed invites pinned to the vault
        (redemption would resurrect the name);
      - connections: tear down records whose source/sink is the vault
        (now revoking the B0-registered jtis), AND scan channel's
        `/api/channels` for legacy pre-connections vault-backed entries
        referencing it;
      - **daemon eviction**: the running vault daemon caches open store
        handles — rmSync alone leaves the "deleted" vault serving from the
        open fd. v1: supervisor-restart vault as a cascade step; the
        boundary-conformant daemon eviction endpoint is E9. Verify with a
        live test (delete → immediately replay a pre-delete request);
      - **last-vault semantics**: vault boot auto-creates `default` when
        `listVaults()===0` — deleting the last vault would silently resurrect
        it (with a fresh global API key). Design decision: `DELETE /vaults`
        **refuses last-vault deletion** (409 + guidance; CLI is the escape
        hatch). Sidesteps the resurrection class and protects against
        fat-finger disasters; the `auto_create: false` marker for CLI users
        is the vault wave's `cmdRemove` improvement;
      - services.json + store eviction in one move: the cascade's
        supervisor-restart re-runs vault's boot `selfRegister`, which
        rebuilds paths from `listVaults()` — dropping the deleted path AND
        evicting the cached store handle. Vault's `cmdRemove` additionally
        gains its own `selfRegister` refresh (vault wave) so the CLI-only
        path stops going stale. Proxy + well-known read per-request, so the
        removal is live post-restart.
      Documented bound: ≤10-min unregistered interactive mints ride to
      expiry. (hub + vault)
- [ ] **B2 hub: reserved-name consolidation.** Hub has TWO validators —
      `admin-vaults.ts` `RESERVED_VAULT_NAMES={list,new,assets}` (POST
      /vaults only) and `vault-name.ts` `RESERVED_NAMES={list}` (used by the
      **setup wizard and invite redemption** — a non-admin invite redeemer
      can name a vault `admin` today and capture the new mount; `new`/
      `assets` squats are the same pre-existing drift). Collapse to ONE set
      `{list, new, assets, admin}` in `vault-name.ts`; `admin-vaults.ts`
      imports it. DELETE accepts reserved names (so a squatted `admin` vault
      can be removed). (hub)
- [ ] **B4 hub: URL-resolution unification + compat shim.** Adopt standard
      semantics — `http(s)://` verbatim · leading-`/` = origin-absolute
      verbatim · relative = mount-joined — in **all three resolver
      families**, same release:
      - `api-modules.ts` `resolveModuleUrl` (two test pins at ~:530-577 and
        ~:739-790 encode the old semantics and invert);
      - `well-known.ts` `buildWellKnown`'s vault uiUrl branch — it currently
        REQUIRES leading-`/` and always mount-joins (flip the guard:
        relative becomes the valid per-instance form; leading-`/` passes
        through; emit a daemon-level `configUiUrl` once, not per instance);
      - the `resolveManagementUrl` triplet (`hub-server.ts`,
        `account-vault-admin-token.ts` — incl. its hardcoded `"/admin/"`
        fallback → `"admin/"` — and `web/ui/src/lib/api.ts`): document the
        per-instance-relative contract; audit `hub.ts`
        `loadServiceUiMetadata` as a fourth consumer.
      **Compat shim (one release):** the literal legacy `"/admin/"` family on
      a *vault* entry mount-joins with a deprecation warning, removed after
      vault's new manifest reaches @latest. Old-hub + new-vault is a known
      cosmetic 404 (links only, no auth impact) — documented. (hub)
- [ ] **B-route hub: the daemon-level mount.** Route `/vault/admin` +
      `/vault/admin/*` to the vault module's port — resolve the
      `parachute-vault` services row directly via
      `findServiceByShort(services, "vault")` (the channelEntry shape),
      **BEFORE `findVaultUpstream`**, applying the same
      publicExposure/loopback cloak as `proxyToVault`. Vault must **NOT**
      self-register `/vault/admin` in paths[] — every consumer deriving
      instance names from paths (`vaultInstanceNameFor`, well-known fan-out,
      `findExistingVault`, mint allowlists, the users vault-picker) would
      fabricate a phantom vault named `admin`. Gated on the B2 reservation.
      (hub)

### Vault wave (one vault release; lands SECOND)

- [ ] **B2 vault: validators.** Add the consolidated reserved set to vault's
      `vault-name.ts` AND `cmdCreate`'s separate inline check. Boot-time loud
      warning (server boot / selfRegister already calls `listVaults()`) when
      a vault named `admin`/`new`/`assets` exists, naming the shadowing
      consequence + recovery. Recovery procedure (no rename command exists):
      `parachute-vault export <dir> --vault admin → create <newname> →
      import <dir> --vault <newname> → remove admin --yes`. (vault)
- [ ] **B3 vault: the `/vault/admin/` surface.** Sub-items, all required:
      - `routing.ts`: daemon-level `/vault/admin` branch **before**
        `isAdminSpaPath`, reusing `serveAdminSpa` with its own prefix-strip;
        the bare-mount 301-to-trailing-slash must fire for the new mount
        (else relative assets resolve to `/vault/assets/...`). Don't merge
        the regexes — `/vault/admin/admin` must not boot per-vault mode for
        name="admin";
      - `web/ui` `mount.ts`: detect `/vault/admin` FIRST → basename
        `/vault/admin`, null mounted-vault; `main.tsx`: skip the per-vault
        mint in multi-vault mode; `App.tsx`: a third route tree (multi-vault
        home);
      - **data plane**: list from `/.well-known/parachute.json` `vaults[]`
        (public, CORS `*` — the exact read hub's VaultsList uses today, so
        the pattern moves wholesale); per-vault usage via the authed
        `/vault/<name>/.parachute/usage` with per-vault minted bearers. The
        daemon's `/vaults`/`/vaults/list` are NOT reachable through the hub
        and `/vaults` rejects hub JWTs — do not use them;
      - **create**: drives hub `POST /vaults` with a host-admin Bearer
        minted from the session cookie (the NewVault flow, relocated);
        **delete**: drives B1 with the confirm body;
      - **per-vault deep-links are full-document navigations**
        (`<a href="/vault/<name>/admin/">`, origin-absolute) — React Router
        `Link` under basename `/vault/admin` mangles them, and the SPA's
        token cache is one-vault-per-document. Amend `web/ui/CLAUDE.md`'s
        no-leading-slash rule with this carve-out in the same PR;
      - reuse `SignInBanner` (incl. the non-admin "go to your account" case)
        in multi-vault mode; direct-on-:1940 (no hub) degrades to a
        read-only banner (no well-known doc, no session);
      - `module.json`: `uiUrl`/`managementUrl: "admin/"` (relative →
        per-instance, behavior preserved under B4) + `configUiUrl:
        "/vault/admin/"` (origin-absolute → the daemon-level home).
      (vault)

### Hub wave 2 (lands THIRD, feature-detected)

- [ ] **B5 hub: slim the SPA.** Remove `NewVault.tsx` + the Home vault
      special-case (hub#635's in-shell `/vaults` card — superseded; vault's
      module card now behaves exactly like channel/scribe/surface via
      `config_ui_url`). **Feature-detect**: only redirect `/vaults` +
      `/vaults/new` → `/vault/admin/` when `/api/modules` reports vault's
      `config_ui_url === "/vault/admin/"`; otherwise render the legacy list
      (protects boxes whose vault predates B3). Also: re-point the legacy
      301s (`/vault`, `/vault/new`) directly at the new target (no
      redirect-into-404 chains); repoint/drop the nav "Vaults" link; update
      the wizard vault-step fine-print + the hub-server dispatch comment;
      rewrite the five `Home.test.tsx` cases pinning the old special-case
      (+ pin the disabled-card fallback when `config_ui_url` is null).
      **Zero-instances empty state** (wizard-skip leaves vault installed
      with no instances and no daemon — hub#607): keep a hub-side "create
      your first vault" affordance that deep-links the re-enterable
      `/admin/setup` vault step (bootstrap exception). Wizard + invite
      redemption keep `provisionVault`; Users page keeps per-user vault
      assignment (identity view). (hub)

## Phase C — seam hardening (REORDERED: C2 first)

- [ ] **C1 hub: CSRF belt** on cookie-gated `/admin/*` JSON POST/DELETE
      (hub#632) — confirmed no CSRF token / no Origin check today on
      `/admin/connections` + `/admin/channels`. Lands BEFORE the channel
      teardown work builds on those endpoints. (B1/B3's `/vaults` endpoints
      are Bearer-gated and CSRF-immune — Phase B does not block on this.)
      (hub)
- [ ] **C2 channel: delete symmetry.** Deleting a vault-backed channel from
      channel's admin page also drives hub `DELETE /admin/connections/<id>`
      (which, post-B0, revokes the registered jtis + deregisters the vault
      trigger). Daemon's `DELETE /api/channels` stays mechanics-only; the
      page composes both. (channel)
- [ ] **C3 runner: working auth + config.** Config page mints `runner:admin`
      via `/admin/module-token/runner` (scribe pattern — every data call
      401s behind auth today; the admin-ui comment claiming hub injects
      Authorization is wrong); add the config write form + link-to-vault
      flow (channel pattern) for `vault_token`; fix the stale `pvt_*` schema
      text + README's retired generic-config-form flow. (runner)
- [ ] **C4 surface: session→mint sign-in** replacing the pasted-bearer
      TokenSetup (its planned Phase 1.3; scribe pattern). (surface)
- [ ] **C5 hub: re-gate the generic module-token mint** on self-registration
      (services.json row + readable module.json) instead of
      `isKnownModuleShort` — closes the charter-test gap for third-party
      modules; the forged-short concern is answered by "registered row +
      manifest exists" (same-disk write = already-trusted). (hub)

## Phase D — residue retirement

- [ ] D1 hub: retire `/admin/channels` + `admin-channels.ts` + SPA helpers
      (superseded by Connections; ensure the legacy-channel scan from B1
      lands first)
- [ ] D2 hub: `NO_UI_FOLLOWUPS` stale entries (scribe, runner) + stale
      comments; generalize or retire the Connections `CHANNEL_ADD_PRESET`
      (module-specific hub-SPA code — the per-module-view test fails it)
- [ ] D3 hub: retire channel's `FIRST_PARTY_FALLBACKS` entry once its
      module.json declaration is confirmed complete
- [ ] D4 parachute.computer: supersession banners on the 2026-04-20
      module-architecture + hub-as-portal design docs (point at
      hub-module-boundary)

## Phase E — tracked, not built now (file issues)

- [ ] E1 scribe shared-secret → hub-minted `scribe:transcribe` JWTs (failed
      migration = scribe silently open; needs care)
- [ ] E2 scribe install-time provider config → scribe-owned first-boot UX
- [ ] E3 vault vestigial owner-password/TOTP retirement (gated on hub
      expose-preflight scoring hub credentials — the inverse holdover)
- [ ] E4 services.json registration API (multi-host/cloud)
- [ ] E5 hub guarantees RFC 7592 client DELETE (surface DCR orphans)
- [ ] E6 `/admin/channel-token` vs generic mint (chat UI needs read+send,
      not admin — decide when a second module needs a non-admin UI mint)
- [ ] E7 generic instance-scope API (`<short>:<instance>:<verb>` grammar +
      picker + attenuation + per-instance mint + assignment — extract from
      the vault precedent; unblocks third-party multi-instance modules with
      per-instance identity)
- [ ] E8 default CSP on proxied module pages (defense-in-depth for the
      stored-XSS-in-module-surfaces threat the trust statement names)
- [ ] E9 vault daemon store-eviction endpoint (replaces the B1
      supervisor-restart cascade step)
- [ ] E10 `/login` on a no-admin box renders JSON 503 instead of a
      finish-setup page (pre-existing; surfaced by the B3 empty-state review)

## Status (2026-06-09 — built, deployed, live-verified same day)

| Item | PR | State |
|---|---|---|
| Phase A (charter + migration + doc alignment) | patterns#120, #121 | **merged** |
| B0, B1, B2h, B4, B-route (hub wave 1) | hub#637 | **merged** |
| B2v, B3 (vault wave — `/vault/admin/`) | vault#473 | **merged** |
| B5 (hub wave 2 — SPA slim, feature-detected) | hub#645 | **merged** |
| C1 (Origin belt — closes hub#632) | hub#638 | **merged** |
| C2 (channel delete symmetry) | channel#46 | **merged** |
| C3 (runner auth + config form) | runner#17 | **merged** |
| C4 (surface session→mint; fixed pre-existing aud break) | surface#86 | **merged** |
| C5 + D1 + D2 + D3 (mint re-gate · retire /admin/channels · preset generalization · channel FALLBACK) | hub#646 | **merged** |
| D4 (design-doc supersession banners) | parachute.computer#106 | **merged** |
| E1–E10 | scribe#74 #75 · vault#474 #475 #476 · hub#639 #640 #641 #642 #643 #644 | issues filed |

Live verification (local fabric, 2026-06-09): `/vault/admin/` 200 through the
hub (bare → 301), per-vault SPA + data plane unaffected, legacy
`/vault`/`/vault/new` 301s re-pointed, well-known fans one correctly-resolved
per-instance tile per vault under the new semantics, the compat shim dormant
(new manifest live), `/admin/channels` retired, `DELETE /vaults` gated, all
module admin pages 200.
