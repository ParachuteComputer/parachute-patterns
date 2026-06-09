# Modular UI architecture — discovery, module-owned config, hub-native connections

**Status:** design → build (2026-06-09). Workspace-wide architecture shift. Aaron-mandated, comprehensive.
**Repos:** parachute-patterns (protocol), parachute-hub (discovery + shell + connections), parachute-vault, parachute-scribe, parachute-channel, parachute-runner, parachute-surface (per-module config UIs + events/actions).

> **Superseded in part (2026-06-09, same day).** The hub–module boundary
> charter ([`../patterns/hub-module-boundary.md`](../patterns/hub-module-boundary.md))
> extends this doc and amends one item: this doc's "genuinely hub-level"
> list included *vault provisioning* wholesale. The charter splits it —
> the provisioning **transaction** (`POST /vaults` / `DELETE
> /vaults/<name>`, host-admin-gated identity transaction) is hub-level;
> the provisioning **UX** is module-owned (vault's daemon-level surface
> at `/vault/admin/`). Everything else here stands. Migration:
> [`../migrations/2026-06-09-hub-module-boundary.md`](../migrations/2026-06-09-hub-module-boundary.md).

## The problem

Three different concerns got conflated into "the hub admin", and the result is awkward + inconsistent:

1. **Module discovery/install is gated by a hardcoded whitelist.** `CURATED_MODULES = ["vault","scribe"]` (hub `api-modules.ts`) decides what the Modules screen shows. The channel module is running, proxied, supervised, and self-registered in `services.json` — yet it's **administratively invisible and can't be installed** because it isn't in that constant. Three registries disagree (`CURATED_MODULES` vs `services.json` vs `FIRST_PARTY_FALLBACKS`/`KNOWN_MODULES`): a module can be running but invisible.
2. **Module config UIs get hard-coded into the hub admin SPA.** The deprecated generic `ModuleConfig` form was the old anti-pattern; the new Channels view (hub#624) is a fresh instance. The hub admin SPA shouldn't grow a bespoke React view per module.
3. **There's no machine-readable contract for "a module owns a config surface at X."** `module.json` has `uiUrl`/`managementUrl` but no `configUiUrl`/`configSchema`/capabilities, and no `events`/`actions`. The good half-pattern (vault + scribe serve their own admin UI; hub links via `managementUrl`) is inconsistent and under-declared.

## The model — three clean concerns

| Concern | Owner | Mechanism |
|---|---|---|
| **Discovery / install / lifecycle** | Hub | Driven by **self-registration** (`services.json` + `module.json`), NOT a whitelist. A `focus` tier de-emphasizes (never hides) exploration modules. |
| **A module's own config/admin UI** | The **module** | Module serves it + declares `configUiUrl` (+ `configSchema`, `adminCapabilities`) in `module.json`. The hub renders a consistent **shell** that links to / frames the module-owned surface. Never hard-coded in the hub SPA. |
| **Connections (cross-module wiring)** | Hub | The hub is the only thing with cross-module authority (mint tokens, register triggers). A **general Connections surface** wires "when [event] in [module] → do [action] in [module]" (the sink is always an `action`, never an `event`). Modules declare the `events` they emit + `actions` they accept. "Add a vault-backed channel" is the first connection (`vault.note.created` → `channel.message.deliver`), not channel-specific config. |

The hub admin shrinks to genuinely hub-level things: users, OAuth, tokens, expose, the vault-provisioning *transaction* (`POST /vaults` / `DELETE /vaults/<name>` — the provisioning *UX* is vault's own surface; see [`../patterns/hub-module-boundary.md`](../patterns/hub-module-boundary.md)), **module discovery**, and **connections**. Everything module-specific is module-owned and hub-linked.

## The protocol extension (`module.json`)

The contract everything builds on. Add (all optional, additive — back-compatible):

```jsonc
{
  // ... existing: name, displayName, tagline, port, paths, health, startCmd,
  //               uiUrl, managementUrl, stripPrefix, scopes ...

  "focus": "core" | "experimental",        // discovery tier (default "experimental" for unlisted)
  "configUiUrl": "/scribe/admin",           // where the module's OWN config surface lives (hub links/frames it)
  "configSchema": { /* JSON Schema */ },    // optional: declarative config (promote the unused field)
  "adminCapabilities": ["config","credentials","logs"],  // optional metadata

  // --- Connections ---
  "events":  [ { "key": "note.created", "title": "...", "filterSchema": {...} } ],   // what this module EMITS
  "actions": [ { "key": "message.deliver", "title": "...", "inputSchema": {...},
                "provision": { /* how the hub wires this action — e.g. register a vault trigger */ } } ]
}
```

Defined in `parachute-patterns/patterns/module-json-extensibility.md` (+ `module-protocol.md`), typed in hub `module-manifest.ts`.

## Per-phase plan

- **P1 — Protocol** (patterns + hub `module-manifest.ts`): add the fields above to the schema/spec/types. No behavior yet.
- **P2 — Discovery fix** (hub): the Modules screen + `/api/modules` enumerate self-registered modules (`services.json` ∪ `module.json` ∪ supervisor), not `CURATED_MODULES`. `focus` tier sorts/labels (core vs experimental); install action resolves via `KNOWN_MODULES`/`module.json` package, not the whitelist. **Fixes channel-not-installed.** Keep one source of truth; the other registries become bootstrap-only.
- **P3 — Config shell** (hub): a uniform module-config shell that links to / frames each module's `configUiUrl`; delete the deprecated generic `ModuleConfig` form. Module-owned UI is the only pattern.
- **P4 — Per-module config UIs:**
  - **vault** — has an admin SPA; declare `configUiUrl` + `focus:"core"`; conform.
  - **scribe** — has admin HTML; declare `configUiUrl` + `focus:"core"`; conform.
  - **surface** — has admin; declare + conform.
  - **channel** — BUILD a config/admin UI (manage channels/transports) served by the channel module; declare `configUiUrl` + `focus:"experimental"`. (Distinct from the *connection* of adding a vault-backed channel, which is P5.)
  - **runner** — BUILD a config/admin UI (job listing/config) served by runner; declare `configUiUrl`.
- **P5 — Connections** (hub + every module): the general Connections surface (build/list/remove connections); modules declare `events`/`actions`; the hub orchestrates provisioning via each action's `provision` block (vault actions use the runtime trigger API from vault#469; the channel-add flow becomes `vault.note.created (filter: tag #channel-message/inbound) → channel.message.deliver`, the sink being the channel **action** that delivers an inbound message + wakes the session). Reframe hub#624's Channels view into this. First-class events to declare: vault `note.created`/`note.updated`/`note.deleted`; scribe `transcription.complete`; channel `message.received`/`message.sent`. First-class actions: channel `message.deliver`; vault `note.create`; scribe `transcribe`.
- **P6 — Integrate, e2e, deploy, prove.**

## Migration

This is an architectural shift quoting `CURATED_MODULES`, the hub admin nav, and the module protocol across repos → a `parachute-patterns/migrations/2026-06-09-modular-ui.md` propagation checklist ships alongside, tracking every code/doc location.

## Principles (hold the line)

- **Self-registration is the single source of truth for discovery.** Whitelists become bootstrap-only or die.
- **Modules own their config UIs.** The hub frames/links; it never hard-codes a per-module config view.
- **Connections are hub-native + general.** No per-module-pair hard-coding; everything flows from declared `events`/`actions`.
- **Additive + back-compatible** at every step; default behavior unchanged for unmigrated modules.
- **Every PR reviewer-gated + gate-green; no NUL/binary files** (bitten once this arc).
