---
title: Modular-UI architecture migration
date: 2026-06-09
status: active
originating-pr: parachute-patterns (this PR — protocol docs + migration file)
---

# Modular-UI architecture migration

The shift: **stop conflating three concerns in the hub admin** — module
discovery, a module's own config UI, and cross-module connections — and give
each a clean owner and a machine-readable contract.

- **Discovery** becomes **self-registration-driven** (`services.json` ∪
  `module.json` ∪ supervisor), not the hardcoded `CURATED_MODULES` whitelist.
  A `focus: "core" | "experimental"` tier de-emphasizes (never hides)
  exploration modules. **This fixes channel-not-installed** — channel runs,
  is proxied + supervised + self-registered, yet is administratively invisible
  today because it isn't in the whitelist.
- **A module's own config UI is module-owned + hub-linked.** Each module
  serves its config surface and declares `configUiUrl` in `module.json`; the
  hub renders one uniform config shell that frames / links it. The hub SPA
  never grows a bespoke per-module config view (the deprecated generic
  `ModuleConfig` form, and hub#624's per-module Channels view, are the
  anti-pattern this retires).
- **Connections are hub-native + general.** The hub — the only thing with
  cross-module authority — owns a general Connections surface wiring "when
  [event] → do [action]". Modules declare the `events` they emit and the
  `actions` they accept in `module.json`.

Full design — the three-concern model, the protocol extension, and the
per-phase plan (P1–P6) — is in
[`../design/2026-06-09-modular-ui-architecture.md`](../design/2026-06-09-modular-ui-architecture.md).

This is the propagation checklist. Every code/doc location the shift touches,
across hub + every module + the pattern docs. **All items start unchecked.**

## Protocol (patterns) — P1

- [ ] patterns:`patterns/module-json-extensibility.md` — document the new
  `module.json` fields (`focus`, `configUiUrl`, `configSchema`,
  `adminCapabilities`, `events`, `actions`) with descriptions + examples
  (this PR)
- [ ] patterns:`patterns/module-protocol.md` — note the module-owned config UI
  (`configUiUrl`) + the `events`/`actions` connection contract (this PR)
- [ ] patterns:`patterns/module-discovery.md` — self-registration as the single
  source of truth; the `focus` tier; retire the curated-whitelist model
  (this PR)
- [ ] patterns:`patterns/module-ui-declaration.md` — `configUiUrl` alongside
  `uiUrl` (discovery tile) + `managementUrl` (admin deep-link) (this PR)
- [ ] patterns:`migrations/2026-06-09-modular-ui.md` — this file (this PR)
- [ ] hub:`src/module-manifest.ts` — extend the manifest validator/types with
  the six new optional fields; route them through `composeServiceSpec`
  (P1 — hub)

## Discovery fix — retire `CURATED_MODULES` — P2

- [ ] hub:`src/api-modules.ts` — `CURATED_MODULES` retirement; `/api/modules`
  enumerates self-registered modules (`services.json` ∪ `module.json` ∪
  supervisor), not the whitelist; `focus` tier sorts/labels (core vs
  experimental) (P2 — hub)
- [ ] hub:install-action resolution — resolve installable name → package via
  `KNOWN_MODULES` / `module.json`, **not** the whitelist; demote
  `KNOWN_MODULES` to an install-time bootstrap index, not a visibility gate
  (P2 — hub)
- [ ] hub: Modules-screen SPA — render every self-registered module; surface
  the `focus` tier visually (core first, experimental de-emphasized but
  never hidden). **Verify channel now appears + is installable.** (P2 — hub)

## Config shell + retire the deprecated form — P3

- [ ] hub: hub-admin nav / shell — shrink the hub admin to genuinely hub-level
  things (users, OAuth, tokens, expose, vault provisioning, discovery,
  connections); module-specific config moves out of the hub SPA (P3 — hub)
- [ ] hub: **delete the deprecated generic `ModuleConfig` form** — module-owned
  config UI (framed / linked via `configUiUrl`) is the only pattern (P3 — hub)
- [ ] hub: uniform module-config shell — links to / frames each module's
  declared `configUiUrl` (P3 — hub)

## Per-module config UIs + `module.json` additions — P4

Each module emits the new `module.json` fields inside its npm artifact;
modules without a config surface today **build** one.

- [ ] vault:`.parachute/module.json` — declare `configUiUrl` (existing admin
  SPA) + `focus: "core"`; conform (P4 — vault)
- [ ] scribe:`.parachute/module.json` — declare `configUiUrl` (existing admin
  HTML) + `focus: "core"`; conform (P4 — scribe)
- [ ] surface:`.parachute/module.json` — declare `configUiUrl` (existing
  admin) + `focus: "core"` (it's committed-core); conform (P4 — surface)
- [ ] channel: **build** a config/admin UI (manage channels / transports)
  served by the channel module; `.parachute/module.json` declares
  `configUiUrl` + `focus: "experimental"` (P4 — channel)
- [ ] runner: **build** a config/admin UI (job listing / config) served by
  runner; `.parachute/module.json` declares `configUiUrl` (P4 — runner)

## Connections — general surface + per-module declarations — P5

- [ ] hub: general **Connections** surface — build / list / remove connections;
  the hub orchestrates provisioning via each action's `provision` block
  (vault actions use the runtime trigger-registration API from vault#469)
  (P5 — hub)
- [ ] hub: **reframe hub#624's Channels view** into a Connection — the
  channel-add flow becomes `vault.note.created (filter: tag
  #channel-message/inbound) → channel.message.deliver` (sink is the channel
  **action**, never the `message.received` event), not channel-specific config
  (P5 — hub)
- [ ] vault:`.parachute/module.json` — declare `events`
  (`note.created` / `note.updated` / `note.deleted`) + `actions`
  (`note.create`); wire action `provision` to the trigger API (P5 — vault)
- [ ] scribe:`.parachute/module.json` — declare `events`
  (`transcription.complete`) + `actions` (`transcribe`) (P5 — scribe)
- [ ] channel:`.parachute/module.json` — declare `events` (`message.received` /
  `message.sent`) + `actions` (`message.deliver` — the inbound sink, with a
  `provision` block that registers a vault runtime trigger webhooking the
  channel's inbound endpoint with a hub-minted `channel:send` bearer)
  (P5 — channel)

## Integrate, e2e, deploy — P6

- [ ] hub + modules: end-to-end — install channel via the discovery screen;
  open each module's config UI via the hub shell; build a vault-backed-channel
  Connection through the general Connections surface; deploy live + prove
  (P6 — hub + modules)

## Doc references

- [ ] patterns:`patterns/module-surfaces.md` — confirm the canonical
  capabilities framing still holds with `configUiUrl` added (audit; update if
  it enumerates UI fields)
- [ ] hub:`CLAUDE.md` / `README.md` — describe self-registration-driven
  discovery + the hub-admin shrink (drop any "curated modules" framing)
  (P2/P3 — hub)
- [ ] parachute.computer: any public copy describing the Modules screen,
  module config, or "what the hub admin does" (P6 — parachute.computer)
- [ ] run [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh)
  after the code lands — catch any missed `CURATED_MODULES` / "whitelist" /
  hardcoded-config-view references

## Operator-facing references

- [ ] hub: the Modules screen itself is the primary operator-facing surface —
  experimental modules now visible (channel, runner); covered by P2 + P4

## External references

- (none significant — npm package descriptions unaffected; `module.json`
  additions are additive + back-compatible, so unmigrated modules keep
  working)

## Notes

- **Additive + back-compatible at every step.** All six `module.json` fields
  are optional; default behavior is unchanged for unmigrated modules. A module
  with no `focus` is treated as `"experimental"`; one with no `configUiUrl`
  gets no config-shell link; one with no `events`/`actions` has no Connections
  surface. P-phases can land independently.
- **`KNOWN_MODULES` survives** as an install-time bootstrap index (name →
  installable package), demoted from a visibility gate. This mirrors the
  earlier `FIRST_PARTY_FALLBACKS` → bootstrap-only trajectory
  ([workspace `CLAUDE.md`](../../CLAUDE.md) "Note on hub's
  `FIRST_PARTY_FALLBACKS`").
- **Vault trigger API dependency.** P5's vault `actions` provisioning rides on
  the runtime trigger-registration API (vault#469) — already shipped; this arc
  consumes it.
- Every PR is reviewer-gated + gate-green; **no NUL/binary files** (this arc
  has been bitten once).
