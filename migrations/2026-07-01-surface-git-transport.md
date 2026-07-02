---
title: Surface Git Transport (hub-authenticated git push → built + served surfaces)
date: 2026-07-01
status: active
originating-pr: multi-PR arc — parachute-hub 0.7.5 rc chain / parachute-agent 0.2.4 / parachute-surface (surface-host) 0.3.8; this checklist file lands in parachute-patterns#132
---

# Surface Git Transport

**Shipped + live 2026-07-01** (hub `0.7.5`, surface-host `0.3.8`, agent
`0.2.4`; demo surface at `/surface/hello`). This file is the retroactive
propagation checklist — the code shipped across three repos before the
migration file existed; the design doc explicitly asks for this file
("Ship a `parachute-patterns/migrations/` file when this redraws the
grant-kind contract / the surface install path" — both happened).

## The shift

A surface is developed, lives, and serves **inside the parachute**: an
agent / human / remote session does a plain `git push
<hub>/git/<name>`, the **hub authenticates** it (a hub-issued JWT
carrying `surface:<name>:write` for push, `surface:<name>:read` for
fetch — write ⊇ read at the git endpoint), a post-receive notify wakes
**surface-host**, which builds the pushed *source* in a kernel-confined
sandbox and serves it at `/surface/<name>`. Four layers: vault
*declares* (`#surface` note) · git *transports* · hub *authenticates* ·
surface-host *serves*. Canonical design:
[`parachute.computer/design/2026-06-30-surface-git-transport.md`](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-06-30-surface-git-transport.md).

What this redraws canonically:

- **Scope vocabulary** gains a second enforced per-resource family:
  `surface:<name>:read|write` (after `vault:<name>:<verb>`), plus
  module-level `surface:admin` (the hub↔surface-host notify bearer +
  credential endpoint).
- **Grant-kind contract**: the agent grants system gains
  `kind: "surface"` (`wants: "surface:<name>:<read|write>"`) alongside
  `vault` / `service` / `mcp`.
- **Surface install path**: `git push` is how a surface ships; drop-a-
  bundle-in stays for bundled reference surfaces, GitHub becomes an
  *optional* mirror.

## Code references (shipped — recorded for the map, not for action)

### parachute-hub (0.7.5)

- [x] `src/git-transport.ts` — the authenticated git endpoint
      (`/git/<name>`): `requiredAccess()` (receive-pack → `write`,
      upload-pack / discovery → `read`), Bearer + Basic
      (`x-access-token`) extraction, `git http-backend` spawn,
      traversal defense.
- [x] `src/git-registry.ts` — surface→bare-repo registry.
- [x] `src/git-notify.ts` — post-receive notify to surface-host with a
      hub-minted `surface:admin` bearer (aud `surface`).
- [x] `src/surface-token.ts` — Phase-3a static deploy tokens:
      `parachute surface token mint|list|revoke` (scoped, registered,
      revocable `surface:<name>:<verb>` PAT-equivalent).
- [x] `src/grants-store.ts` — `kind: "surface"` in `ConnectionSpec` +
      surface `GrantMaterial` (the minted JWT) + the
      `connectionKey()` `surface:<target>:<access>` branch.
- [x] `src/admin-agent-grants.ts` — the `surface` approve path;
      spec-not-key reconcile (agent sends SPECS, hub re-derives keys
      with its own `connectionKey()`).

### parachute-agent (0.2.4)

- [x] `src/grants.ts` — `kind: "surface"` parse
      (`parseOneWant`: `surface:<name>:<read|write>`, slug-validated,
      verb required) + its own `connectionKey()` branch + the
      **`GIT_ASKPASS` injection channel** (token reaches git without
      landing in argv/env-visible remotes) + egress auto-allow for the
      hub git origin.

### parachute-surface / packages/surface-host (0.3.8)

- [x] `src/git-deploy.ts` — receive the notify, clone/checkout, drive
      the build, atomically flip the served tree (surface-name
      validation via its `SURFACE_NAME_RE`).
- [x] `src/build-sandbox.ts` — kernel-confined build
      (`@anthropic-ai/sandbox-runtime` Seatbelt/bubblewrap; build
      workspace lives under `os.tmpdir()`, NOT the home tree — the
      0.3.8 lesson).
- [x] `src/surface-discovery.ts` — `#surface` note discovery →
      canonical surface name (the `/git/<name>` + `/surface/<name>`
      segment; duplicate names: first declaration wins).
- [x] `src/admin-routes.ts` — admin surface for deployed surfaces.
- [x] `.parachute/module.json` — `scopes.defines: ["surface:read",
      "surface:write", "surface:admin"]`.

## Doc references

- [x] `patterns/oauth-scopes.md` — `surface:<name>:read|write` +
      `surface:admin` scope family; per-surface narrowing named as the
      second enforced shape; `write ⊇ read` inheritance note; where-
      applies entry. *(PR: parachute-patterns#132 — this batch)*
- [ ] `parachute.computer/design/2026-06-30-surface-git-transport.md` —
      header still says "Status: DRAFT for review"; flip to
      SHIPPED/ACTIVE with the shipped-versions note (hub 0.7.5,
      surface-host 0.3.8, agent 0.2.4; Phase 3a shipped 2026-07-01).
      *(PR: — parachute.computer, pending)*
- [ ] `patterns/module-json-extensibility.md` / grant-pattern docs — a
      line that the grant-kind vocabulary is `vault | service | surface
      | mcp` (surface added by this arc), if/when those docs enumerate
      kinds. *(pending — audit when the agent-grants pattern doc is
      written)*
- [ ] Workspace `CLAUDE.md` — no entry names Surface Git Transport yet;
      add to the parachute-surface / hub rows when the table is next
      touched. *(parachute-workspace, pending)*

## Deferred phases (not regressions — tracked in the design doc §12)

- [ ] **Phase 3b/3c** — the *human* login paths:
      `git-credential-parachute` interactive loopback-PKCE + the
      headless-auth decision (device-flow, RFC 8628, if chosen). The
      Phase-3a static deploy token is the seam these extend.
- [ ] **Phase 4** — surface-dev agent role; rollback UX; optional
      GitHub mirror; (stretch) generalize hub-authenticated git beyond
      surfaces.

## Known cross-repo seams (contract-test follow-ups)

These are the places where two implementations must agree byte-for-byte
— the exact class that bit us on the service/vault grant keys
(agent#96/hub#674). Flagged here so they get cross-repo contract tests,
not just per-repo unit tests:

- [ ] **Dual `connectionKey()` impls** — hub
      `src/grants-store.ts`/`admin-agent-grants.ts` vs agent
      `src/grants.ts` each derive `surface:<target>:<access>`. The
      spec-not-key reconcile (hub re-derives from SPECS) contains the
      blast radius, but a shared fixture of `(spec → key)` pairs run
      against BOTH impls is the real guard. *(issue: file against hub +
      agent)*
- [ ] **Surface-name derivation in 3 places** — hub
      `src/git-transport.ts` (`SURFACE_NAME_RE` + `.git`-suffix strip),
      surface-host `src/git-deploy.ts` (`SURFACE_NAME_RE`) +
      `src/surface-discovery.ts` (canonical-name parse), agent
      `src/grants.ts` (surface-slug validation in `parseOneWant`). All
      must accept/reject the same names or a pushable-but-not-servable
      (or grantable-but-not-pushable) surface appears. Shared
      name-fixture contract test. *(issue: file against hub + surface +
      agent)*

## External references

- [ ] npm package descriptions (`@openparachute/hub`, surface-host) —
      mention the git-push deploy path when next touched. *(low
      priority)*

## Cross-references

- [`../patterns/oauth-scopes.md`](../patterns/oauth-scopes.md) — the
  scope family this arc added.
- [`2026-06-25-multi-origin-iss-set.md`](./2026-06-25-multi-origin-iss-set.md)
  — the iss-set tolerance that keeps git pushes working when the box is
  reached via multiple URLs.
- [`../patterns/hub-module-boundary.md`](../patterns/hub-module-boundary.md)
  — the substrate-provides / module-specifies seam the transport
  follows (hub owns the git primitive; surface-host + the `#surface`
  note declare their use of it).
