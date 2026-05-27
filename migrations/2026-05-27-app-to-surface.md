---
title: app → surface rename (full, clean migration)
date: 2026-05-27
status: active
originating-pr: parachute-patterns#102
---

# app → surface rename

The "app" name was always a placeholder. The 2026-05-26 team meeting surfaced the rename: "surface" is what we actually mean — a lens / projection / front-end into a vault, not a self-contained "app." Aaron's call: clean migration, no `/app/*` back-compat redirects, full rename including the GitHub repo.

Confidence to do it clean: nobody is on it except Aaron's local install + his Render demo. He'll re-install as `surface` after the migration lands.

## Scope

- npm package `@openparachute/app` → `@openparachute/surface`
- npm package `@openparachute/app-client` → `@openparachute/surface-client`
- GitHub repo `parachute-app` → `parachute-surface` (GitHub redirects the old URL)
- Module identifier in services.json: `parachute-app` → `parachute-surface`
- Mount path: `/app` → `/surface`
- Bin: `parachute-app` → `parachute-surface`
- Canonical port table: row name `parachute-app` → `parachute-surface` (port 1946 unchanged)
- Hub `KNOWN_MODULES`/`FIRST_PARTY_FALLBACKS`/install-spec entries
- Hub admin SPA copy + module catalog labels
- Patterns + site doc references

## What's NOT renamed

- The `notes-ui` package and bundled-app slot stays named `notes-ui`. Notes is an app/surface; it doesn't carry the parent term in its name.
- The `uis` field in module.json (or whatever the host module calls its hosted-app registry) — defer that rename; it's internal-only and not user-facing.

## Code references

### parachute-app (becomes parachute-surface)

- [ ] `packages/app-host/` → `packages/surface-host/` directory rename. Tracked-by: (pending)
- [ ] `packages/app-host/package.json`: `name: @openparachute/app` → `@openparachute/surface`, `bin: parachute-app` → `parachute-surface`. Tracked-by: (pending)
- [ ] `packages/app-host/bin/parachute-app.ts` → `bin/parachute-surface.ts`. Tracked-by: (pending)
- [ ] `packages/app-host/.parachute/module.json`, `info`: name/displayName/etc fields. Tracked-by: (pending)
- [ ] `packages/app-client/` → `packages/surface-client/` directory rename. Tracked-by: (pending)
- [ ] `packages/app-client/package.json`: `name: @openparachute/app-client` → `@openparachute/surface-client`. Tracked-by: (pending)
- [ ] `packages/notes-ui/package.json`: dep `@openparachute/app-client` → `@openparachute/surface-client`. Tracked-by: (pending)
- [ ] Source-code identifiers: any internal `app*` symbol that's user-visible (config keys, paths, etc.) becomes `surface*`. Tracked-by: (pending)
- [ ] Root monorepo package.json + bun workspace paths. Tracked-by: (pending)
- [ ] README + docs in repo. Tracked-by: (pending)
- [ ] GitHub repo rename (last, after package work merges): `ParachuteComputer/parachute-app` → `ParachuteComputer/parachute-surface`. Tracked-by: (post-merge)

### parachute-hub

- [ ] `src/service-spec.ts` `KNOWN_MODULES` entry `app` → `surface`. manifestName `parachute-app` → `parachute-surface`. installPath `/app` → `/surface`. Tracked-by: (pending)
- [ ] `src/service-spec.ts` `FIRST_PARTY_FALLBACKS` entry: same. Tracked-by: (pending)
- [ ] `src/service-spec.ts` `RETIRED_MODULES`: add `parachute-app` with replacement `parachute-surface` so existing operator rows get auto-cleaned on read. Tracked-by: (pending)
- [ ] `src/notes-redirect.ts`: legacy `/notes/*` → `/app/notes/*` redirect retargets to `/surface/notes/*`. Tracked-by: (pending)
- [ ] `src/setup-wizard.ts`: any references to `app` as install slug, tile copy. Tracked-by: (pending)
- [ ] `src/commands/install.ts` + service-spec install path: `parachute install app` → `parachute install surface`. Tracked-by: (pending)
- [ ] Admin SPA (`web/ui/src/`): user-visible "App" → "Surface" across module catalog, install flow, status displays. Tracked-by: (pending)
- [ ] `src/help.ts`: command help text. Tracked-by: (pending)
- [ ] Tests across all of these. Tracked-by: (pending)

### parachute-patterns

- [ ] `patterns/canonical-ports.md`: row name + commentary. Tracked-by: (pending — this PR)
- [ ] `patterns/module-self-registration.md`: examples that name `parachute-app`. Tracked-by: (pending)
- [ ] `patterns/governance.md`: committed-core list. Tracked-by: (pending)

## Doc references

- [ ] `parachute.computer/design/2026-05-21-parachute-apps-design.md`: full doc reframe — title says "apps" but body should adopt "surface" vocabulary. Tracked-by: (pending)
- [ ] `parachute.computer/design/2026-05-18-v06-deploy-architecture.md`: references to app module. Tracked-by: (pending)
- [ ] Workspace `CLAUDE.md`: parachute-app row. Tracked-by: (pending)
- [ ] `parachute-notes/DEPRECATED.md`: refers to parachute-app as replacement. Tracked-by: (pending)

## Operator-facing references

- [ ] `parachute-hub/README.md`: install instructions, module list. Tracked-by: (pending)
- [ ] `parachute.computer/install.njk`: section 3 (the "Want a UI for your notes?" copy). Tracked-by: (pending)
- [ ] `parachute.computer/deploy/render.njk` + `deploy/fly.njk`: walkthrough references to `app`. Tracked-by: (pending)
- [ ] `parachute.computer/roadmap.njk` + `docs.njk`: any direct references. Tracked-by: (pending)

## External references

- [ ] npm: deprecate `@openparachute/app` and `@openparachute/app-client` with a "moved to @openparachute/surface*" message. Tracked-by: (post-rename publish)
- [ ] GitHub repo description for new `parachute-surface`. Tracked-by: (post-rename)

## Operator-state migration

The `RETIRED_MODULES` entry for `parachute-app` is the load-bearing piece: existing operators (Aaron's local + the Render demo) will load services.json on hub boot, the GC drops the stale `parachute-app` row with a console warning naming `parachute-surface` as the replacement, and the operator re-runs `parachute install surface` to add the row back under the new name. This mirrors the agent → app retirement pattern from 2026-05-20.

Aaron's local install will need: `parachute stop app` (to free the process holding port 1946), then `parachute install surface`. The existing `/parachute/modules/node_modules/@openparachute/app/` package directory can be deleted manually or left — `bun add @openparachute/surface` writes alongside.

## Audit

Run [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) after the rename lands to catch missed `parachute-app` references in unexpected places. Update the audit script's grep patterns if needed.
