# Migration notes

Running log of pattern changes and the repos that need to follow. Newest
entries on top. Each entry: date, change, affected repos, status.

---

## 2026-04-26 — Hub is the OAuth issuer

**Change:** the hub origin is the canonical OAuth issuer for the
ecosystem. Vault still implements the OAuth endpoints, but advertises
the hub as `issuer` (and stamps it into token `iss` claims) whenever
the request reaches it via the hub origin. Falls back to the
vault-local URL on direct loopback. See
[`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md); pairs
with [`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md).

**Affected:**

- `parachute-vault` — already implements the contract. Reference:
  `resolveOAuthCoordinates` in `src/oauth.ts`, landed in
  [#147](https://github.com/ParachuteComputer/parachute-vault/pull/147)
  and refined in
  [#152](https://github.com/ParachuteComputer/parachute-vault/pull/152).
- `parachute-cli` (renaming to `parachute-hub` —
  [cli#55](https://github.com/ParachuteComputer/parachute-cli/issues/55))
  — derives the canonical hub origin in `src/hub-origin.ts` and passes
  it through as `PARACHUTE_HUB_ORIGIN` on `expose up` / `start`.
- `parachute-scribe`, `parachute-channel`, future modules — when they
  begin OAuth enforcement, validate `iss` against the hub origin (not
  their own URL). No code change needed before they implement OAuth.
- Phase B2 cutover (hub becomes IdP itself) tracked in
  [cli#58](https://github.com/ParachuteComputer/parachute-cli/issues/58)
  and
  [vault#169](https://github.com/ParachuteComputer/parachute-vault/issues/169).

**Status:** Phase 0+1 complete on 2026-04-23. Phase B2 in design.

---

## 2026-04-26 — Well-known discovery URLs follow RFC 8414 §3.1

**Change:** OAuth metadata for an issuer with a path component lives
at `<origin>/.well-known/<type>/<issuer-path>` (path-insertion), not
`<issuer>/.well-known/<type>` (path-append). Vault serves both for
client compatibility, but path-insertion is the canonical advertised
form. See
[`patterns/well-known-discovery-rfc.md`](../patterns/well-known-discovery-rfc.md);
pairs with [`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md).

**Affected:**

- `parachute-vault` — already conforms. Path-insertion routes added
  in [#149](https://github.com/ParachuteComputer/parachute-vault/pull/149)
  after the `/vault/<name>/` URL migration; path-append routes have
  been there since launch. Reference: top of `route()` in
  `src/routing.ts`.
- `parachute-hub` (renaming from `parachute-cli` —
  [cli#55](https://github.com/ParachuteComputer/parachute-cli/issues/55))
  — picks this up when the hub becomes the IdP itself in Phase B2
  ([cli#58](https://github.com/ParachuteComputer/parachute-cli/issues/58)).
  Hub origin has no path component, so insertion and append collapse
  to the same `/.well-known/<type>` URL — the distinction only
  matters for issuers with a path.
- `parachute-scribe`, `parachute-channel`, future modules — when they
  begin serving OAuth metadata, serve both shapes for any path-rooted
  issuer they advertise.

**Status:** complete for vault on 2026-04-23 (PR #149). Other modules
not yet OAuth-enforcing.

---

## 2026-04-26 — Mount-path convention documented

**Change:** new pattern doc
[`patterns/mount-path-convention.md`](../patterns/mount-path-convention.md).
Frontend modules are served at a subpath under the ecosystem origin
(today: `/notes/`), declared once via Vite `base` and read by everyone
through `import.meta.env.BASE_URL`. Three coordinated downstream
consumers — Vite asset URLs, React Router `basename`, PWA manifest
`scope` / `start_url` / `id`. Internal routes are mount-relative
(`/n/:id`, not `/notes/n/:id`); the router's basename does the
prefixing. OAuth redirect URIs read `BASE_URL` so the callback resolves
under the deployed mount. Override knob: `VITE_BASE_PATH`.

**Affected:**

- `parachute-notes` — reference implementation, already conformant.
  Refactor sequence: PR
  [#49](https://github.com/ParachuteComputer/parachute-notes/pull/49)
  (move `base` to `/notes`) → PR
  [#50](https://github.com/ParachuteComputer/parachute-notes/pull/50)
  (drop `/notes/` from internal routes) → PR
  [#54](https://github.com/ParachuteComputer/parachute-notes/pull/54)
  (deep-link shim for pre-refactor bookmarks). Architecture writeup at
  the top of `parachute-notes/CLAUDE.md` already forward-references
  this doc.
- Future Parachute frontends (PWAs / SPAs) — adopt the same shape: pick
  a stable slug, set Vite `base`, write mount-relative routes, mirror
  the manifest. Hub catalog (`/.well-known/parachute.json`) auto-renders
  any frontend module that publishes a `services.json` entry with
  `kind: "frontend"`.
- Third-party frontends — same contract. Standard SPA-under-subpath
  hygiene; nothing Parachute-specific.

**Status:** complete on 2026-04-26 for `parachute-notes`. Pattern doc
captures live behavior; no service-side changes required.

---

## 2026-04-25 — CLI is the port authority at install time

**Change:** `parachute install` now picks each service's port up front and
writes `PORT=<n>` into `~/.parachute/<svc>/.env`. Idempotent — an existing
`PORT` in `.env` wins, so re-installs and user-edited ports survive
upgrades. See [`patterns/cli-as-port-authority.md`](../patterns/cli-as-port-authority.md);
pairs with [`patterns/canonical-ports.md`](../patterns/canonical-ports.md).

**Affected:**

- `parachute-cli` — implemented in
  [#54](https://github.com/ParachuteComputer/parachute-cli/pull/54)
  (closes #53). Helper: `src/port-assign.ts`. Hook: `src/commands/install.ts`.
- `parachute-vault`, `parachute-notes`, `parachute-scribe`,
  `parachute-channel` — no service-side changes required. Each already
  reads `PORT` from env with a compiled-in fallback; the CLI's `.env`
  value is merged into the spawn env by `lifecycle.start`. Confirm the
  pattern on the next touch and add a comment if a service hard-codes its
  port instead of reading env.
- Third-party / future modules — same contract: read `PORT` from env, fall
  back compiled-in, no integration with the CLI required.

**Status:** complete for committed-core services on 2026-04-25.

---

## 2026-04-15 — `parachute-*` bin naming

**Change:** all Parachute executables adopt the `parachute-<module>` prefix
(see `naming/bins.md`). The umbrella `parachute` bin is reserved for
`@openparachute/cli`.

**Affected:**

- `parachute-vault` — renamed `parachute` → `parachute-vault` in
  [#134](https://github.com/ParachuteComputer/parachute-vault/pull/134) (2026-04-21).
- `parachute-scribe` — renamed `scribe` → `parachute-scribe` in
  [#9](https://github.com/ParachuteComputer/parachute-scribe/pull/9) (2026-04-22).
- `parachute-narrate` — not yet published; will ship as
  `parachute-narrate` from day one.
- `parachute-channel` — conformant (`parachute-channel`, `parachute-channel-bridge`).
- `parachute-agents` — conformant (`parachute-agent`, `parachute-agent-ui`).
- `tailshare` — exempt; not a Parachute-branded tool.

**Status:** complete for shipped modules. Narrate to follow on first publish.

---

## 2026-04-15 — parachute-patterns repo created

**Change:** this repo exists. Conventions that were implicit across the
ecosystem (naming, brand palette, agent schema, modularity principle, etc.)
are now written down.

**Affected:** every Parachute repo eventually needs a README link back to
this repo (`adoption/checklist.md`). Non-urgent — add as repos get touched.

**Status:** in progress.

---

## Template

```
## YYYY-MM-DD — <one-line change>

**Change:** what changed and why. Link to the pattern file.

**Affected:** which repos need to follow and what specifically each needs
to do.

**Status:** DRAFT | in progress | complete.
```
