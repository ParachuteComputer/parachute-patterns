---
title: Add Fly as peer self-host option (alongside Render)
date: 2026-05-26
status: active
originating-pr: parachute.computer#62 (Fly migration design doc)
---

# Add Fly as peer self-host option (alongside Render)

Adds Fly.io as a **peer self-host option** alongside the existing Render path. Both are first-class — operators pick the platform they prefer. Aaron's framing (2026-05-26): _"For now, this is a self-host offering alongside render."_

The design doc ([`parachute.computer/design/2026-05-26-fly-migration-path.md`](../../parachute.computer/design/2026-05-26-fly-migration-path.md)) sketches a four-phase arc where later phases (hosted offering on `parachute.cloud`) might eventually shift the substrate balance. This file tracks **Phase 1 only**: the work to make Fly a viable self-host choice. No primacy reordering between Render and Fly is implied.

## Why add Fly

- **Operator choice.** Some operators already have Fly orgs and would prefer to use them; some prefer Render's GUI-first ops; some want the lower cost. Offering both serves both.
- **Lock-in symmetry for future cloud option.** Fly volume snapshots are portable (`fly volumes snapshot create`, restorable into other orgs). When the hosted-on-cloud option arrives (Phase 2+, separate decision), the export-to-self-host primitive matters more on Fly than Render. This Phase 1 work makes Fly a viable target for that.
- **Cost shape.** Fly shared-cpu-1x 512MB iad is $3.34/mo all-in vs Render Starter $7/mo. Operator savings, not a forcing factor.
- **Non-driver: reliability.** Fly and Render both have intermittent edge-router issues (Fly `fly-proxy` regressions; Render `portdetectorv2` flap caught at [hub#399](https://github.com/ParachuteComputer/parachute-hub/issues/399)). This shift is not motivated by reliability.

## Phase 1 — add Fly self-host path

Aaron committed 2026-05-26 to Phase 1 only (Option A in the design doc): add the Fly track for self-hosters as a peer option. Explicit decision point at the end before any work on Phase 2 (hosted offering) starts.

### Exit criteria

A friend can fork `parachute-hub` + run `./scripts/deploy-to-fly.sh` + install vault from the admin SPA, in under 5 minutes, with the same UX as the Render path. Existing Render operators see no breakage; nothing about the Render path changes substantively.

## Code references

### parachute-hub

- [x] `fly.toml` — new file at repo root, alongside the existing `render.yaml`. Pinned to shared-cpu-1x 512MB / iad / 1GB volume at `/parachute`. **No hardcoded `app =`** so each operator's `fly launch` generates a unique slug. Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)
- [x] `src/hub-server.ts` — `parseArgs` reads `FLY_APP_NAME` and composes `https://${FLY_APP_NAME}.fly.dev` as peer fallback alongside `RENDER_EXTERNAL_URL` (new `flyDefaultOrigin` helper). Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)
- [x] `src/hub-server.ts` — `platformOrigin` in the bound-origins resolver reads the Fly value so browser POSTs with `<app>.fly.dev` Origin are trusted. Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)
- [x] `src/commands/serve.ts` — `resolveStartupIssuer` also extended with the Fly branch. Critical because this is the function that injects `PARACHUTE_HUB_ORIGIN` into every supervised module's env; without this, vault/scribe would get `undefined` issuer on Fly and reject every hub-minted token with iss-mismatch. (Reviewer catch on hub#420.) Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)
- [x] `src/setup-wizard.ts` — `detectAutoExposeMode` recognizes `FLY_APP_NAME` the same way it recognizes Render. Validates slug shape (no slashes — defensive). Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)
- [ ] `src/api-hub.ts` — `buildInfo` block exposes Fly equivalents alongside `RENDER_GIT_COMMIT` / `RENDER_GIT_BRANCH`. Fly sets `FLY_RELEASE_COMMAND` + `FLY_REGION` (different shape — decide what the admin "build info" panel actually surfaces). Deferred from hub#420 — safe to ship Phase 1 without it; admin SPA renders but shows blank build-info fields for Fly operators. Tracked-by: (pending PR)
- [x] `scripts/deploy-to-fly.sh` — flyctl install + `fly launch --copy-config --yes` wrapper. Idempotent: detects existing `app = "..."` in fly.toml on re-run and branches to `fly deploy`. Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)
- [x] `README.md` — restructured "Hosted self-deploy" section: both Render and Fly as equally-supported peers. Tracked-by: [hub#420](https://github.com/ParachuteComputer/parachute-hub/pull/420)

### parachute.computer

- [ ] `deploy/fly.njk` — new doc, sibling of `deploy/render.njk`, walkthrough for the Fly path. Same shape, same depth. Tracked-by: (pending PR)
- [ ] `deploy/index.njk` (or `/deploy` landing) — show both options as peers. Tracked-by: (pending PR)
- [ ] `deploy/render.njk` — no substantive change needed. Optionally add a "Or deploy on Fly →" pointer at the top. Tracked-by: (verify)

### parachute-patterns

- [ ] `patterns/bun-container-deploy.md` — references Render-specific URL examples (`parachute-hub.onrender.com`) and frames the deploy from a Render-primary perspective. Update opening tagline to mention Fly as a peer platform. Tracked-by: (pending PR)
- [ ] `patterns/release-ci.md` — "Matches Render auto-deploy semantics" rationale should mention `fly deploy` on push as the equivalent Fly pattern. Tracked-by: (pending PR)
- [ ] `patterns/canonical-ports.md` — no change expected (ports are platform-agnostic). Verify.
- [ ] `patterns/module-self-registration.md` — verify no platform-specific assumptions.

## Doc references

- [ ] `parachute.computer/design/2026-05-18-v06-deploy-architecture.md` — current doc names Render as the deploy target. Add companion note pointing at the Fly migration doc + reframe as "container substrate; Render OR Fly per operator preference." Tracked-by: (pending PR)

## Operator-facing references

- [ ] `parachute-hub/README.md` — Deploy section. Tracked-by: (pending PR)
- [ ] `parachute.computer/index.njk` — landing page CTA. Tracked-by: (verify if changes needed)
- [ ] `parachute.computer/roadmap.njk` — note Fly added as a peer target if roadmap items reference Render specifically. Tracked-by: (verify)

## External references

- [ ] npm package descriptions for `@openparachute/hub` — if they mention Render specifically, broaden. (Likely no mention; verify.)
- [ ] GitHub repo description for `parachute-hub` — if it mentions Render specifically, broaden.
- [ ] Existing blog posts on `parachute.computer/blog/` that name Render — leave historical posts intact; the next "shipping" post can mention Fly as an added option.

## Aaron's existing Render deploy

Aaron's `parachute-hub.onrender.com` is the live demo and stays on Render. Migration plan for Aaron specifically:

1. Phase 1 lands fly.toml + scripts.
2. Aaron OPTIONALLY runs `./scripts/deploy-to-fly.sh` to dogfood a Fly deploy alongside the Render one.
3. Both can coexist indefinitely.
4. No cutover required. Render demo URL stays as long as Aaron wants it.

## What this migration does NOT do

- Does not retire Render. `render.yaml` stays in the repo; operators on Render keep working unchanged.
- Does not reorder primacy — Render and Fly are presented as peer choices throughout. No "primary self-host path" framing.
- Does not change the local-install path (`parachute install ...` from npm). Local installs are platform-agnostic.
- Does not start work on Phase 2 (hosted offering on `parachute.cloud`). That requires a fresh commitment.
- Does not change vault/scribe/app self-registration shape. Modules are platform-agnostic.

## Audit

Run [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) after Phase 1 lands to verify no stale "Render is the path" framing leaked through.
