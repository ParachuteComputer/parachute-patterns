---
title: Hub-as-supervisor unification migration
date: 2026-06-01
status: active
originating-pr: parachute.computer#89 (design doc)
---

# Hub-as-supervisor unification migration

The shift: **retire the manager-less detached-daemon process model and run `parachute serve` (hub foreground + in-process Supervisor; modules = attached children) under a per-platform process manager everywhere** — systemd on a Linux VM, launchd on a Mac, the container runtime on Render/Fly.

Today the hub has two incompatible process models, and which one you get depends on the deploy substrate, not a deliberate choice: a manager-less detached daemon (`parachute start`/`expose`/`init` → detached+`unref`'d hub + independent module daemons, no supervisor) vs serve+supervisor (`parachute serve`, used only in containers). That split is the root of EC2≠Render, no-reboot-survival off-container, UI-module-management broken off-Render (`503 supervisor_unavailable`), and the stale-daemon-drift class of bugs.

Full design — target model, the resolved blockers/risks, the open decisions (D1–D4), and the phasing — is in [`parachute.computer/design/2026-06-01-hub-as-supervisor-unification.md`](../../parachute.computer/design/2026-06-01-hub-as-supervisor-unification.md).

This is the propagation checklist. It tracks every code/doc/operator surface the shift touches across the six phases; each phase PR checks its items off.

## Phase timeline

- **Phase 1** — `POST /api/modules/:short/{start,stop}` endpoints + a CLI module-ops client (reads `operator.token`, drives the running hub) + this migration file. **Additive, no cutover.** PRs: hub#TBD (code), patterns#TBD (this file). _[in progress]_
- **Phase 2** — generalize `connector-service.ts` → a `ManagedUnit`; **supervisor hardening: process-group spawn + `kill(-pgid)`, per-module log ring buffer, post-spawn port-readiness + structured start-error.** Blocks Phase 3 (the process-group fix must precede the cutover, or it regresses the EADDRINUSE-on-restart bug).
- **Phase 3** — `init` + `start/stop/restart <svc>` cutover onto the supervisor; status hub-row reads the platform manager.
- **Phase 4** — `expose` + `upgrade hub` cutover; the SPA `POST /api/hub/upgrade` + detached one-shot helper (so the no-CLI Render/Fly audience can upgrade the hub from the SPA).
- **Phase 5** — `migrate` detached→supervised cutover (ordering, orphan sweep, archive-guard, teardown, auto-offer) + retire the detached spawners.
- **Phase 6** — docs + test sweep.

## Code references

- [ ] hub:`src/api-modules-ops.ts` — add `start` (pure `supervisor.start`, NOT install) + `stop` handlers (P1)
- [ ] hub:`src/module-ops-client.ts` — new CLI client; reads `~/.parachute/operator.token` → loopback Bearer to module-ops (P1)
- [ ] hub:`src/supervisor.ts` — process-group spawn + `kill(-pgid)`; per-module log ring buffer; post-spawn port-readiness + structured start-error (P2)
- [ ] hub:`src/cloudflare/connector-service.ts` — generalize into a `ManagedUnit` (env block, install-without-start mode, hub naming) (P2)
- [ ] hub:`src/commands/lifecycle.ts` — repoint `start/stop/restart <svc>` onto the module-ops client (P3); retire `defaultSpawner` (P5)
- [ ] hub:`src/hub-control.ts` `ensureHubRunning` + its 4 call sites (`init.ts`, `expose.ts`, `expose-cloudflare.ts`, lifecycle start-hub) → "ensure the hub unit is up" (P3/P4); retire `defaultHubSpawner` (P5)
- [ ] hub:`src/commands/init.ts` — install + start the hub unit; guarantee an operator token exists (P3)
- [ ] hub:`src/commands/expose.ts` + `expose-cloudflare.ts` — decouple from hub lifecycle; `expose off` no longer stops the hub; connector → `ManagedUnit` (P4)
- [ ] hub:`src/commands/upgrade.ts` `hubTarget` — restart the unit not the process; + `POST /api/hub/upgrade` + detached helper for SPA-driven hub upgrade (P4)
- [ ] hub:`src/commands/migrate.ts` — detached→supervised cutover: write-unit → stop-detached → verify-port-free → start-unit ordering; per-port orphan sweep; archive-guard platform-manager check; `--teardown`; auto-offer (P5)
- [ ] hub:`src/commands/status.ts` `hubRow` — query the platform manager for the hub's state (P3)
- [ ] hub:`src/process-state.ts` — thin to readers-only after the cutover (P5)
- [ ] hub:`src/proxy-state.ts` — the Mode-2 pidfile fallback becomes dead once everything's supervised (P5)

## Doc references

- [ ] hub:`CLAUDE.md` — Architecture section + the `parachute start`/`serve` framing (P6)
- [ ] hub:`src/help.ts` — command help for `start`/`stop`/`restart`/`serve`/`init`/`expose`/`upgrade` (P6)
- [ ] hub:`src/supervisor.ts` header comment — the "on-box flow walks away…" two-model framing no longer holds (P6)
- [ ] parachute.computer:install + `deploy/*` pages — the EC2/Hetzner ≡ Render story; serve-under-systemd as the self-host path (P6)

## Operator-facing references

- [ ] hub:`README.md` "Service lifecycle" (≈:181-211) — **full rewrite**: retire the `run/<svc>.pid` + `logs/<svc>.log` state model + the `unknown`=externally-managed semantics; **reverse the "Migrating from launchd" subsection** (it currently tells operators to *remove* a launchd agent — we now *install* one); resolve the `parachute start --boot` roadmap line (this design is it); drop the "no launchd, no hunting for PIDs" selling point at :183 (P6)
- [ ] parachute.computer: any "no launchd / no daemon" copy on the public site (P6)

## External references

- (none significant — npm package descriptions unaffected)

## Notes

- `patterns/canonical-ports.md` (1939 hub-pin, no fallback) is load-bearing for the migration's port-race ordering (design §7.1) — respected, not changed.
- The cloudflared connector reboot-persistence work (hub#493) is the precedent the hub unit generalizes; the headless systemd-user linger gotcha (hub#494) applies to the hub unit too.
- Open owner decisions D1–D4 are recorded in the design doc; D4 settled 2026-06-01 (SPA-driven `upgrade hub` is first-class).
