---
title: Render → Fly self-host migration (Phase 1)
date: 2026-05-26
status: active
originating-pr: parachute.computer#62 (Fly migration design doc)
---

# Render → Fly self-host migration (Phase 1)

Migrates the **canonical self-host path** from Render to Fly.io. Render support is preserved (`render.yaml` stays in the repo) — this shift recommends Fly as the primary path, with Render as an alternative for operators already on it.

The full migration arc has four phases; this file tracks **Phase 1 only** (~2 weeks of work). Phases 2 (hosted offering via `parachute.cloud`), 3 (public launch), and 4 (Render sunset) are scoped in the design doc but require fresh commitment to start.

Full architectural reasoning: [`parachute.computer/design/2026-05-26-fly-migration-path.md`](../../parachute.computer/design/2026-05-26-fly-migration-path.md).

## Why the shift

- **Lock-in symmetry.** Render disks have no portable snapshot export. Fly volumes do (`fly volumes snapshot create`, restorable into other orgs). The escape hatch matters for self-hosters and matters more when a hosted offering is on the table.
- **Substrate alignment.** A future hosted offering (`parachute.cloud`, Phase 2+) runs the same image on the same platform as self-host. One CI pipeline, one bug-fix path, one ops model.
- **Cost shape.** Fly shared-cpu-1x 512MB iad is $3.34/mo all-in vs Render Starter $7/mo. The delta funds the hosted offering's margin.
- **Non-driver: reliability.** Fly and Render both have intermittent edge-router issues (Fly `fly-proxy` regressions; Render `portdetectorv2` flap caught at [hub#399](https://github.com/ParachuteComputer/parachute-hub/issues/399)). This shift is not motivated by reliability.

## Phase 1 — self-host on Fly

Aaron committed 2026-05-26 to Phase 1 only (Option A in the design doc): spike the Fly track for self-hosters, with explicit decision point at the end before committing to Phase 2 (hosted offering).

### Exit criteria

A friend can fork `parachute-hub` + run `./scripts/deploy-to-fly.sh` + install vault from the admin SPA, in under 5 minutes, with the same UX as the Render path.

## Code references

### parachute-hub

- [ ] `fly.toml` — new file at repo root, alongside the existing `render.yaml`. Pinned to shared-cpu-1x 512MB / iad / 1GB volume at `/parachute`. Tracked-by: (pending PR)
- [ ] `src/hub-server.ts:263` — `canonicalOrigin` resolver recognizes `FLY_APP_NAME` (composes `https://${FLY_APP_NAME}.fly.dev` as a peer to the existing `RENDER_EXTERNAL_URL` branch). Tracked-by: (pending PR)
- [ ] `src/setup-wizard.ts:236` — auto-skip-expose step recognizes Fly the same way it recognizes Render (platform routes URL publicly without operator action). Tracked-by: (pending PR)
- [ ] `src/api-hub.ts:145` — Fly equivalents for `RENDER_GIT_COMMIT` + `RENDER_GIT_BRANCH` (Fly sets `FLY_RELEASE_COMMAND`, `FLY_REGION` — different shape; decide what the admin "build info" panel actually needs). Tracked-by: (pending PR)
- [ ] `scripts/deploy-to-fly.sh` — new wrapper that detects `flyctl`, installs if missing, runs `fly launch --copy-config --yes`, prints the URL. Tracked-by: (pending PR)
- [ ] `README.md` — Deploy-to-Fly as the primary path; Render moves to alternative. Tracked-by: (pending PR)

### parachute.computer

- [ ] `deploy/render.njk` — soften framing from "the canonical self-host path" to "one of two paths"; cross-link to Fly. Tracked-by: (pending PR)
- [ ] `deploy/fly.njk` — new doc, sibling of `deploy/render.njk`, walkthrough for the Fly path. Tracked-by: (pending PR)
- [ ] `deploy/index.njk` (if it exists; else `/deploy` landing) — show both options, Fly first. Tracked-by: (pending PR)

### parachute-patterns

- [ ] `patterns/canonical-ports.md` — no change expected (ports are platform-agnostic). Verify.
- [ ] `patterns/module-self-registration.md` — verify no platform-specific assumptions.

## Doc references

- [ ] `parachute.computer/design/2026-05-18-v06-deploy-architecture.md` — current doc names Render as primary self-host path. Add companion note pointing at the Fly migration doc + note that Phase 1 recommends Fly. Tracked-by: (pending PR)

## Operator-facing references

- [ ] `parachute-hub/README.md` — Deploy section. Tracked-by: (pending PR)
- [ ] `parachute.computer/index.njk` — landing page CTA. Tracked-by: (verify if changes needed)
- [ ] `parachute.computer/roadmap.njk` — note the substrate shift if roadmap items reference Render. Tracked-by: (verify)

## External references

- [ ] npm package descriptions for `@openparachute/hub` — if they mention Render, update. (Likely no mention; verify.)
- [ ] GitHub repo description for `parachute-hub` — if it mentions Render, update.
- [ ] Any existing blog posts on `parachute.computer/blog/` that name Render — leave historical posts intact, but the next "shipping" post should name Fly as canonical.

## Aaron's existing Render deploy

Aaron's `parachute-hub.onrender.com` is currently the live demo. Migration plan:

1. Phase 1 lands fly.toml + scripts.
2. Aaron runs `./scripts/deploy-to-fly.sh` to provision `parachute-hub.fly.dev` (or chosen subdomain).
3. Smoke-test the Fly deploy end-to-end (wizard, install vault, install scribe, OAuth flow).
4. Decision: keep both running, or cut over (Render disk → Fly volume migration).
5. If cutting over: `sqlite3 hub.db ".backup ..."` from Render SSH, restore into Fly volume.

Aaron's call on cutover timing; both deploys can coexist indefinitely.

## What this migration does NOT do

- Does not retire Render. `render.yaml` stays in the repo; operators on Render keep working.
- Does not change the local-install path (`parachute install ...` from npm). Local installs are platform-agnostic.
- Does not start work on Phase 2 (hosted offering). That requires a fresh commitment.
- Does not change vault/scribe/app self-registration shape. Modules are platform-agnostic.

## Audit

Run [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) after Phase 1 lands to verify no stale Render-as-only-path references remain in unexpected places.
