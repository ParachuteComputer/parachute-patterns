---
title: Hub-as-supervisor unification migration
date: 2026-06-01
status: complete
originating-pr: parachute.computer#89 (design doc)
---

# Hub-as-supervisor unification migration

> **Status: COMPLETE (2026-06-02).** All six phases are merged to `parachute-hub` `main`
> (P1–P5b code, P6 docs). The arc retires the manager-less detached-daemon model;
> supervised-under-a-platform-manager is now the only runtime.
>
> - **Code (P1–P5b):** hub#495 (P1) · hub#496 (P2a) · hub#497 (P2b) · hub#498 (P3a) ·
>   hub#499 (P3b) · hub#500 (P3c) · hub#502 (P4-cli) · hub#504 (P4-spa) ·
>   hub#507 (P5a) · hub#510 (P5b).
> - **Docs (P6):** hub#514 (hub `CLAUDE.md` / `README.md` / `help.ts` / `supervisor.ts` header) ·
>   parachute.computer Phase-6 site-docs PR (install + `deploy/*` pages) · this PR (tracker finalize).
> - **Design doc:** parachute.computer#89. **Migration file landed (P1):** patterns#112.
> - **Shipped to npm:** Phases 1–3 shipped to the `@rc` dist-tag as `hub@0.6.3-rc.1` (hub#501).
>   **Not yet done (gated on Aaron):** `@latest` stable release + the live-box detached→supervised migration.
> - **Deferred follow-ups (not part of the core arc):** hub#503 (cloudflare-off origin-clear) ·
>   hub#505 (depcheck dist DX) · hub#506 (D4 hub-upgrade 409-deadlock, pre-D4-deploy) ·
>   hub#508 (`resolveOperatorTokenIssuer` consolidation) · hub#509 (proactive iss-detection) ·
>   hub#511 / hub#512 (RFC 8707 resource→aud — real, but NOT the connector blocker, deferred) ·
>   hub#513 (warn at `expose --cloudflare` re Cloudflare bot protection).
> - **See also (post-arc propagation):** hub#580 (dual-lifecycle race — module's own
>   launchd/systemd unit vs the supervisor; field-hit on Linux + macOS) resolved via
>   hub PR #581 (light install + stale-unit sweep + port-squatter surfacing) and
>   vault PR #452 (init defaults autostart off under a hub) — the vault-side
>   propagation of this arc's "supervisor owns module lifecycles" decision.

The shift: **retire the manager-less detached-daemon process model and run `parachute serve` (hub foreground + in-process Supervisor; modules = attached children) under a per-platform process manager everywhere** — systemd on a Linux VM, launchd on a Mac, the container runtime on Render/Fly.

Today the hub has two incompatible process models, and which one you get depends on the deploy substrate, not a deliberate choice: a manager-less detached daemon (`parachute start`/`expose`/`init` → detached+`unref`'d hub + independent module daemons, no supervisor) vs serve+supervisor (`parachute serve`, used only in containers). That split is the root of EC2≠Render, no-reboot-survival off-container, UI-module-management broken off-Render (`503 supervisor_unavailable`), and the stale-daemon-drift class of bugs.

Full design — target model, the resolved blockers/risks, the open decisions (D1–D4), and the phasing — is in [`parachute.computer/design/2026-06-01-hub-as-supervisor-unification.md`](../../parachute.computer/design/2026-06-01-hub-as-supervisor-unification.md).

This is the propagation checklist. It tracks every code/doc/operator surface the shift touches across the six phases; each phase PR checks its items off.

## Phase timeline

- **Phase 1** ✅ — `POST /api/modules/:short/{start,stop}` endpoints + a CLI module-ops client (reads `operator.token`, drives the running hub) + this migration file. **Additive, no cutover.** PRs: **hub#495** (code), **patterns#112** (this file). _Done._
- **Phase 2** ✅ — generalize `connector-service.ts` → a `ManagedUnit`; **supervisor hardening: process-group spawn + `kill(-pgid)`, per-module log ring buffer, post-spawn port-readiness + structured start-error.** Blocks Phase 3 (the process-group fix must precede the cutover, or it regresses the EADDRINUSE-on-restart bug). PRs: **hub#496** (2a — supervisor hardening), **hub#497** (2b — `ManagedUnit`). _Done._
- **Phase 3** ✅ — `init` + `start/stop/restart <svc>` cutover onto the supervisor; status hub-row reads the platform manager. PRs: **hub#498** (3a — `ensureHubUnit` + `init` installs the hub unit + mint-on-init), **hub#499** (3b — `start/stop/restart` cutover + fresh-box operator-token closure), **hub#500** (3c — `status` reads the platform manager + supervisor). _Done._
- **Phase 4** ✅ — `expose` + `upgrade hub` cutover; the SPA `POST /api/hub/upgrade` + detached one-shot helper (so the no-CLI Render/Fly audience can upgrade the hub from the SPA). PRs: **hub#502** (4-cli — expose decouple D3 + `upgrade hub` restarts the unit), **hub#504** (4-spa — `POST /api/hub/upgrade` + detached helper + SPA card, D4). _Done._
- **Phase 5** ✅ — `migrate` detached→supervised cutover (ordering, orphan sweep, archive-guard, teardown, auto-offer) + retire the detached spawners. PRs: **hub#507** (5a — `migrate --to-supervised` cutover + archive-guard fix + auto-offer), **hub#510** (5b — retire detached spawners + collapse the dual-dispatch bridge). _Done._
- **Phase 6** ✅ — docs + test sweep. PRs: **hub#514** (hub docs), **parachute.computer** site-docs PR (install + `deploy/*` pages), **this PR** (tracker finalize). _Done._

## Code references

- [x] hub:`src/api-modules-ops.ts` — add `start` (pure `supervisor.start`, NOT install) + `stop` handlers (P1 — hub#495)
- [x] hub:`src/module-ops-client.ts` — new CLI client; reads `~/.parachute/operator.token` → loopback Bearer to module-ops (P1 — hub#495)
- [x] hub:`src/supervisor.ts` — process-group spawn + `kill(-pgid)`; per-module log ring buffer; post-spawn port-readiness + structured start-error (P2a — hub#496)
- [x] hub:`src/cloudflare/connector-service.ts` → `src/managed-unit.ts` — generalized into a `ManagedUnit` (env block, install-without-start mode, hub naming) (P2b — hub#497)
- [x] hub:`src/commands/lifecycle.ts` — repoint `start/stop/restart <svc>` onto the module-ops client (P3b — hub#499); retire `defaultSpawner` + collapse dual-dispatch (P5b — hub#510)
- [x] hub:`src/hub-control.ts` `ensureHubRunning` + its 4 call sites (`init.ts`, `expose.ts`, `expose-cloudflare.ts`, lifecycle start-hub) → "ensure the hub unit is up" via `src/hub-unit.ts` `ensureHubUnit` (P3a — hub#498; P4-cli expose decouple — hub#502); retire `defaultHubSpawner` (P5b — hub#510)
- [x] hub:`src/commands/init.ts` — install + start the hub unit; guarantee an operator token exists (mint-on-init) (P3a — hub#498)
- [x] hub:`src/commands/expose.ts` + `expose-cloudflare.ts` — decouple from hub lifecycle; `expose off` no longer stops the hub; connector → `ManagedUnit` (P4-cli D3 — hub#502)
- [x] hub:`src/commands/upgrade.ts` `hubTarget` — restart the unit not the process (P4-cli — hub#502); + `POST /api/hub/upgrade` + detached helper for SPA-driven hub upgrade (P4-spa D4 — hub#504)
- [x] hub:`src/commands/migrate.ts` — detached→supervised cutover: write-unit → stop-detached → verify-port-free → start-unit ordering; per-port orphan sweep; archive-guard platform-manager check; `--teardown`; auto-offer (P5a — hub#507)
- [x] hub:`src/commands/status.ts` `hubRow` — query the platform manager for the hub's state via `queryHubUnitState` (P3c — hub#500)
- [x] hub:`src/process-state.ts` — thinned to readers-only after the cutover (P5b — hub#510)
- [x] hub:`src/proxy-state.ts` — the Mode-2 pidfile fallback retired once everything's supervised (P5b — hub#510)

## Doc references

- [x] hub:`CLAUDE.md` — Architecture section + the `parachute start`/`serve` framing (P6 — hub#514)
- [x] hub:`src/help.ts` — command help for `start`/`stop`/`restart`/`serve`/`init`/`expose`/`upgrade` (P6 — hub#514)
- [x] hub:`src/supervisor.ts` header comment — the "on-box flow walks away…" two-model framing no longer holds (P6 — hub#514)
- [x] parachute.computer:install + `deploy/*` pages — the EC2/Hetzner ≡ Render story; serve-under-systemd as the self-host path (P6 — parachute.computer site-docs PR)

## Operator-facing references

- [x] hub:`README.md` "Service lifecycle" (≈:181-211) — **full rewrite**: retire the `run/<svc>.pid` + `logs/<svc>.log` state model + the `unknown`=externally-managed semantics; **reverse the "Migrating from launchd" subsection** (it currently tells operators to *remove* a launchd agent — we now *install* one); resolve the `parachute start --boot` roadmap line (this design is it); drop the "no launchd, no hunting for PIDs" selling point at :183 (P6 — hub#514)
- [x] parachute.computer: any "no launchd / no daemon" copy on the public site (P6 — parachute.computer site-docs PR)

## External references

- (none significant — npm package descriptions unaffected)

## Notes

- `patterns/canonical-ports.md` (1939 hub-pin, no fallback) is load-bearing for the migration's port-race ordering (design §7.1) — respected, not changed.
- The cloudflared connector reboot-persistence work (hub#493) is the precedent the hub unit generalizes; the headless systemd-user linger gotcha (hub#494) applies to the hub unit too.
- Open owner decisions D1–D4 are recorded in the design doc; D4 settled 2026-06-01 (SPA-driven `upgrade hub` is first-class).
- **rc ship:** Phases 1–3 shipped to the npm `@rc` dist-tag as `hub@0.6.3-rc.1` (hub#501). The `@latest` stable release and the live-box detached→supervised migration are gated on Aaron and not yet done as of finalize (2026-06-02).
- **Deferred follow-ups (filed during the arc, not part of the core unification):** hub#503 (cloudflare-off origin-clear) · hub#505 (depcheck dist DX) · hub#506 (D4 hub-upgrade 409-deadlock — to land before the D4 deploy) · hub#508 (`resolveOperatorTokenIssuer` consolidation) · hub#509 (proactive iss-detection) · hub#511 / hub#512 (RFC 8707 resource→aud binding — a real OAuth correctness item, but NOT the connector blocker it was first suspected to be; deferred) · hub#513 (warn at `expose --cloudflare` about Cloudflare bot protection on the connector path). **See also:** hub#580 / hub PR #581 / vault PR #452 (vault init hub-default-off — the vault-side item of the dual-lifecycle race this arc's model implies; field-confirmed on Linux + macOS).
