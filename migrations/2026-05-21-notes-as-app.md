---
title: Notes-as-app migration
date: 2026-05-21
status: active
originating-pr: parachute.computer#54 (parachute-app design doc §16)
---

# Notes-as-app migration

The first migration tracked under this discipline (and the one that motivated it). Notes was always — conceptually — an "app that consumes a vault," not a backend service. parachute-app shipped 2026-05-21 with auto-bootstrap of `@openparachute/notes-ui`, which collapsed notes-daemon's role to a static-serve wrapper. The architectural shift: **the committed-core line moves from `vault + notes + scribe + hub` to `vault + app + scribe + hub`**, with Notes living as the canonical first app inside parachute-app.

This file is the propagation checklist. It is retroactive — written after the cleanup wave so future contributors see what "fully propagated" looks like for a real shift. The intent is to seed the migrations discipline with an exemplar.

## Why the shift

- **Notes was already a UI bundle.** notes-daemon was a thin Bun static server in front of the Vite build. The "module" in `parachute-notes` was the static server; the *product* was the React app.
- **Custom UIs needed a home.** Gitcoin Brain (and now Unforced Brain) were external UIs operators wanted hosted under their hub. The choices were: (1) every UI graduates to its own module, or (2) one supervisor hosts N UIs. (2) is parachute-app.
- **Once parachute-app existed, Notes had to be the first app.** If the canonical first-party UI — the one with deepest cross-cutting integration, longest history as own-module, highest bar to clear — didn't migrate, the architecture wasn't real. Notes-as-first-app is the proof-of-pattern.
- **The dev-rebuild caching frustration** ([notes#151](https://github.com/ParachuteComputer/parachute-notes/issues/151)) recurred enough that solving it at the platform level (smart cache headers, opt-in PWA, SSE live-reload) was worth the lift. parachute-app made the right default automatic.

Full architectural reasoning: [`parachute.computer/design/2026-05-21-parachute-apps-design.md`](../../parachute.computer/design/2026-05-21-parachute-apps-design.md) — specifically §16 (Notes migration) and §17 (phasing).

## Phase timeline

The shift unfolds across four phases. Phases 1 and 2 are landed; 3 and 4 are scheduled.

### Phase 1 — parachute-app v0.7 MVP (landed 2026-05-21)

- parachute-app ships as a new module: supervisor + per-UI meta.json + DCR-on-add + admin SPA at `/app/admin/`.
- `@openparachute/notes-ui` published alongside `@openparachute/notes` as a parallel build target — same source, no daemon, just the bundle + meta.json.
- `parachute-app add @openparachute/notes-ui` works alongside the existing `parachute install notes`. Operators can run either; cloud (TBD) will default to app.
- Originating PRs: app#1 (Phase 1.1 core hosting), app#2 (Phase 1.2 admin endpoints + DCR + admin SPA), app#3 (Phase 1.3 dev mode with SSE live-reload), app#4 (Phase 2.0 monorepo restructure + extract `@openparachute/app-client` + `required_schema`), app#7 (Phase 2.1 bootstrap-default-apps — auto-install notes-ui on first boot), app#8 (Phase 3.0 file-watcher + auto-rebuild), notes#152 (dual-publish notes-ui), notes#153 (notes-ui adopts `@openparachute/app-client`), notes#155 (notes-ui subclasses app-client VaultClient).

### Phase 2 — notes-daemon deprecation (landed 2026-05-22)

- notes-daemon marked deprecated: DEPRECATED.md, npm `deprecated` field, README banner.
- hub adds `/notes/*` → `/app/notes/*` 301 redirect so operator bookmarks keep working.
- hub wizard tile switches from "Install Notes" to "Install App." Curated-modules list keeps notes installable for backwards compatibility but recommends app.
- Originating PRs: notes#154 (deprecate notes-daemon), hub#316 (redirect), hub#324 (wizard fix), patterns#75 (refresh canonical-ports + governance + multi-writer-workspace).

### Phase 3 — notes-daemon retirement (~Q3 2026)

- notes-daemon `package.json` removed; `@openparachute/notes` (module package) ships its final RC chain.
- `parachute install notes` removed from hub's install path.
- Hub's `/notes/*` → `/app/notes/*` redirect runs for one more release window, then retires.
- Port 1942 reclaimed; reassignable to the next module needing a slot.

### Phase 4 — repo archive (post-1.0)

- Legacy redirect retired entirely.
- parachute-notes repo either archived (if it has no remaining role) or refactored to be the UI-bundle-only repo (`@openparachute/notes-ui` becomes its sole npm publish).
- Operators on legacy installs get a one-time migration notice on hub upgrade.

## Code references

Locations that consumed the old "Notes-as-module-installed-via-install-Notes" shape, and which needed updating as the shift propagated. Items are marked `[x]` when landed; `[ ]` when planned/pending.

### parachute-hub

- [x] `src/setup-wizard.ts` `INSTALL_TILE_PROPS` — first tile flipped from `notes` to `app`, with tagline "Host module for Parachute UIs — auto-installs Notes on first boot." (hub#324)
- [x] `src/api-modules.ts` `CURATED_MODULES` — list reshaped to `["vault", "app", "notes", "scribe", "runner"]`; `notes` retained as back-compat install path. (hub#324)
- [x] `src/service-spec.ts` `KNOWN_MODULES["app"]` — added with `package: "@openparachute/app"`, `canonicalPort: 1946`, `kind: "frontend"`, `canonicalPaths: ["/app", "/.parachute"]`, `extras.hasAuth: true`. (hub#324)
- [x] `src/service-spec.ts` `PORT_RESERVATIONS` — `1946 → parachute-app` added with status `assigned`. (hub#324)
- [x] `src/commands/setup.ts` `BLURBS` — `app` + `runner` entries added; `notes` blurb suffixed `(notes-daemon; superseded by app)`. (hub#324)
- [x] Hub `/notes/*` → `/app/notes/*` 301 redirect added in `hub-server.ts` with opt-out flag `hub_settings.notes_redirect_disabled`. (hub#316)
- [x] `web/ui` admin SPA install + upgrade UI surfaces `app` correctly. (hub#304, verified by hub#324 wizard test pass)
- [x] `src/services-manifest.ts` ServiceEntry hierarchical `uis` schema extension — sub-units under app's row carry per-UI displayName/iconUrl/path. (hub#315)
- [x] `parachute-hub/README.md` — port table + module list line (hub#325)
- [ ] `parachute-hub/src/service-spec.ts` — `notes` module tagline still reads `"Notes PWA backed by your vault."` (line ~296). Should reframe — notes-daemon is wrapper around notes-ui now. Caught by audit script post-cleanup.

### parachute-app

- [x] `parachute-app` module exists, ships `@openparachute/app`, registers `installDir` via standard module-protocol self-registration. (app#1, app#2)
- [x] `bootstrap-default-apps` step auto-installs `@openparachute/notes-ui` under `/app/notes` on first boot. (app#7)
- [x] `@openparachute/app-client` extracted as standalone npm package, carrying `VaultClient` + OAuth helpers. (app#4)
- [x] `meta.json` schema includes `required_schema` for app-side schema-ensure on first install. (app#4)
- [x] Phase 3.0 file-watcher + auto-rebuild for dev mode. (app#8)

### parachute-notes

- [x] `packages/notes-ui` build target added; publishes as `@openparachute/notes-ui`. (notes#152)
- [x] notes-ui adopts `@openparachute/app-client` (drops in-repo OAuth/vault code). (notes#153)
- [x] notes-ui `VaultClient` subclasses app-client's. (notes#155)
- [x] `packages/notes-daemon/DEPRECATED.md` lands with phased migration steps. (notes#154)
- [x] `packages/notes-daemon/package.json` carries npm `deprecated` field. (notes#154)
- [x] `packages/notes-daemon/README.md` carries deprecation banner. (notes#154)
- [x] Workspace + daemon `CHANGELOG.md` records the deprecation event. (notes#154)
- [ ] Phase 3: remove `packages/notes-daemon/` from the workspace; final RC chain for `@openparachute/notes` ships. (planned)
- [ ] Phase 4: archive repo or refactor to UI-only. (planned)

### parachute-patterns

- [x] `patterns/canonical-ports.md` — 1942 marked `deprecating`; 1944 (agent) marked `retired`; 1945 (runner) + 1946 (app) added; body updated to name vault/app/scribe/hub as committed-core. (patterns#75)
- [x] `patterns/governance.md` — `parachute-app` + `parachute-runner` added to branch-protected list; `parachute-notes` noted as protected through Phase 2-3 then archive at Phase 4. (patterns#75)
- [x] `guides/multi-writer-workspace.md` — "Three modules, one workspace" table refreshed: `parachute-agent` and old `parachute-notes` rows replaced with `parachute-runner` + `parachute-app`. (patterns#75)
- [x] `migrations/` directory + this file + README + audit script. (patterns#76 — this PR)
- [x] `guides/multi-writer-workspace.md` §8 — "parachute-agent vs your own cron" retargeted to parachute-runner. (patterns#76 — this PR)
- [x] `patterns/services-json-row-conventions.md` — canonicalized the row-naming rule that the duplicate-port bug revealed (patterns#77 — this PR)
- [x] `scripts/audit-canonical-refs.sh` — `self-register row name` block added to catch the bug shape going forward (patterns#77 — this PR)
- [x] `parachute-app#13` — app self-register row key fix (`name: "app"` → `name: ROW_NAME` derived from `manifestName`)
- [x] `parachute-runner#4` — runner self-register row key fix (mirror of app#13)

### parachute.computer (public site)

- [x] `install.njk` — Step 3 ("Want a UI for your notes?") rewritten: `parachute install app`; Notes auto-bootstrapped under `/app/notes/`. Multi-app context added (drop additional SPAs under same host).
- [x] `index.njk` aside — "Parachute App — the UI host module. Notes (now part of App) ships as the first canonical app… Install more custom UIs — Gitcoin Brain, Unforced Brain, your own — under the same host." Install snippet: `parachute install app`.
- [x] `deploy/render.njk` — "App (the UI host module, with Notes auto-bootstrapped as the first hosted app)" wording; admin-modules walkthrough mentions installing App auto-bootstraps Notes-UI.
- [x] `blog/2026-04-23-parachute-is-here.md` — 2026-05-22 update banner pointing to `parachute-app` design doc + noting consolidation to four committed-core modules. Historical install commands preserved verbatim; pointer to live install guide.
- [x] `design/2026-05-21-parachute-apps-design.md` — the design doc itself; the source of architectural truth.
- [ ] `since-launch.njk` — review for Notes-PWA framing; existing copy ("Notes header layout," "Per-vault hint") doesn't quote "Notes-the-daemon" so likely fine, but worth a pass when next updating. (planned, low priority — copy was about UX work, not architecture)

### Workspace docs

- [x] Workspace [`CLAUDE.md`](../../../CLAUDE.md) — committed-core table reshaped (vault/app/scribe/hub); `parachute-notes` row moved to deprecating; "Note on parachute-notes migration" paragraph added; "Note on FIRST_PARTY_FALLBACKS" updated to reflect self-registration + KNOWN_MODULES split. (local edit — workspace root is not a git repo)
- [x] Workspace `CLAUDE.md` — "When making architectural shifts" section pointing at this discipline. (this PR — local edit alongside the patterns commits)

## Doc references

Patterns + guides that quoted the old committed-core list or named notes-as-module.

- [x] `parachute-patterns/patterns/canonical-ports.md` — see Code references. (patterns#75)
- [x] `parachute-patterns/patterns/governance.md` — see Code references. (patterns#75)
- [x] `parachute-patterns/patterns/module-self-registration.md` — pre-existing reference says "all four committed-core modules self-register from their own…"; the count is still 4 post-shift (vault/app/scribe/hub), so the sentence remains accurate. Verified during audit; no edit needed.
- [x] `parachute-patterns/guides/multi-writer-workspace.md` — "Three modules, one workspace" table. (patterns#75)
- [x] `parachute-patterns/guides/multi-writer-workspace.md` §8 — "parachute-agent vs your own cron" → "parachute-runner vs your own cron." (this PR)
- [ ] `parachute-patterns/research/parachute-surface-direction.md` — references "Notes PWA" as the active-surface exemplar. Still accurate (Notes-as-app IS the active surface); no edit needed unless framing tightens up later. (no action)

## Operator-facing references

Public-facing surfaces operators read first.

- [x] `parachute.computer/install.njk` — see Code references. (committed in parachute.computer alongside the wider site refresh)
- [x] `parachute.computer/blog/2026-04-23-parachute-is-here.md` — banner update. (committed alongside the site refresh)
- [x] `parachute.computer/deploy/render.njk` — see Code references.
- [x] `parachute-hub/README.md` port table — refreshed to mark 1942 deprecating + 1946 app committed-core. (landed at the time of hub#324)
- [x] `parachute-notes/packages/notes-daemon/README.md` banner. (notes#154)
- [ ] `parachute.computer/roadmap.njk` — Notes line still says "Parachute Notes — browser-based companion for your vault. Installable PWA…" which remains accurate (Notes IS a PWA, it just runs under app's supervision now). No load-bearing change needed; small clarifying sentence could be added on next roadmap refresh. (low priority)
- [ ] `parachute.computer/since-launch.njk` — see Code references. (low priority — copy is UX-focused, not architecture-quoting)

## External references

Offsite surfaces.

- [x] npm `@openparachute/notes` — `deprecated` field set. (notes#154)
- [x] npm `@openparachute/app` — published. (app#1+)
- [x] npm `@openparachute/notes-ui` — published. (notes#152)
- [x] npm `@openparachute/app-client` — published. (app#4)
- [ ] GitHub repo description for `parachute-notes` — could add "(deprecating; merging into parachute-app)" suffix on the next pass. Not load-bearing. (low priority)
- [ ] GitHub repo description for `parachute-app` — verify it names "UI host module" prominently. (low priority)

## What the cleanup wave landed

Three days of propagation work (2026-05-21 → 2026-05-22), four repos touched, ~12 PRs across the arc. Items still pending are low-priority cosmetics; the load-bearing surfaces (wizard, install guide, blog banner, patterns docs) all landed within 24 hours of the architectural shift becoming real with parachute-app's MVP ship.

The bug that surfaced this discipline: hub#323 — Aaron walked the setup wizard on a fresh install and saw "Install Notes" instead of "Install App." The wizard tile was the last operator-facing surface still recommending notes-daemon. Fix landed as hub#324. The audit afterward found ~9 more stale references (the patterns docs, the multi-writer-workspace table) that hadn't been updated alongside the architectural design doc. None were operator-blocking; all were doc-quality issues. patterns#75 swept those.

The lesson: an architectural-decision PR (the parachute-app design doc) names "the four committed-core modules become vault + app + scribe + hub" — but that single sentence is quoted (sometimes verbatim) across patterns, site, hub README, workspace CLAUDE.md. Without a propagation checklist in the originating PR, downstream surfaces drift. The migrations discipline closes that gap.

## Cross-references

- [`parachute.computer/design/2026-05-21-parachute-apps-design.md`](../../parachute.computer/design/2026-05-21-parachute-apps-design.md) — the architectural decision (especially §16, §17).
- [`../patterns/governance.md`](../patterns/governance.md) — review discipline that surrounds migrations.
- [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — grep-based audit for the kinds of stale refs that motivated this migration doc.
- [`parachute-agent/DEPRECATED.md`](https://github.com/ParachuteComputer/parachute-agent/blob/main/DEPRECATED.md) — the 2026-05-20 retirement precedent that informed notes-daemon's DEPRECATED.md shape.
