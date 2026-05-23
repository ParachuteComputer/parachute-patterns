# Module surfaces

> Every committed-core module exposes the same canonical set of
> surfaces — HTTP API, admin UI, MCP server, health endpoint,
> self-registration. The `kind` taxonomy was the wrong axis. Modules
> aren't disjoint kinds; they're all the same shape with different
> content.

## The convention (TL;DR)

A committed-core module SHOULD expose:

| Surface | Path convention | Purpose |
|---|---|---|
| **HTTP API** | `/<short>/<rest>` (or `/<short>/<name>/<rest>` for multi-tenant modules like vault) | REST surface for direct programmatic access. |
| **Admin UI** | `/<short>/admin` (relative `managementUrl` in `module.json`; or admin SPA route inside hub) | Operator-facing web UI for configuring + managing the module. |
| **MCP server** | `/<short>/mcp` | LLM/agent integration via Model Context Protocol. |
| **Health endpoint** | `/<short>/health` (or whatever `health` in `module.json` declares) | Hub-supervised liveness probe. |
| **Self-registration** | writes own row to `~/.parachute/services.json` at boot | Per [`module-self-registration.md`](./module-self-registration.md). |

Not every surface is mandatory at v0.6 — but the design SHOULD assume
they all exist, even if some are stubbed. The pattern is
interoperability through uniform surface, not specialization through
disjoint kinds.

## Why — the constraint that produced it

The `kind: "api" | "frontend" | "tool"` field tried to discriminate
modules into disjoint categories. Reality, looking across the modules
that actually shipped:

- **vault** — API yes, admin SPA yes, MCP yes, health yes,
  self-register yes. So what "kind" is it?
- **scribe** — API yes, admin (config endpoints) yes, MCP yes
  (scribe#48), health yes, self-register yes. Same set.
- **app** — API yes, admin SPA at `/app/admin` yes, MCP no
  (placeholder issue), health yes, self-register yes.
- **runner** — API yes, admin endpoints (Phase 1.2) yes, MCP no
  (placeholder issue), health yes, self-register yes.
- **hub** — API yes, admin SPA (the portal itself) yes, MCP no
  (placeholder issue), health yes, self-register N/A (hub doesn't
  register itself).

The kinds were all the same. The taxonomy was carving a smooth space
into artificial categories — every module exposes (or should expose)
the same set of capability surfaces; the difference is *content*, not
*kind*.

The right axis is: each module is a self-contained service that
exposes the canonical surfaces. Hub doesn't need to know "what kind"
— it proxies whatever paths the module declares and exposes the same
admin/discovery affordances uniformly across every module.

Aaron's framing (2026-05-22):

> Almost all of these are the same, in the ideal shape. Vault should
> have a UI, at least for configuring, it should have an API, it
> should be surfaced via MCP. Runner should too. App should too. All
> of these modules should be quite interoperable and have some
> underlying patterns. I'm not sure that how we're organizing them
> via `kind` is right, which is why we shifted.

## Current state (as of 2026-05-22)

| Module | API | Admin | MCP | Health | Self-reg |
|---|---|---|---|---|---|
| vault | yes | yes (`/vault/<name>/admin/`, per hub#172 migration) | yes | yes | yes |
| scribe | yes | yes (config endpoints + schema) | yes (scribe#48) | yes | yes |
| app | yes | yes (SPA at `/app/admin/`) | no — [parachute-app#15](https://github.com/ParachuteComputer/parachute-app/issues/15) | yes | yes |
| runner | yes | yes (admin endpoints, Phase 1.2) | no — [parachute-runner#5](https://github.com/ParachuteComputer/parachute-runner/issues/5) | yes | yes |
| hub | yes | yes (the admin SPA itself) | no — [parachute-hub#328](https://github.com/ParachuteComputer/parachute-hub/issues/328) | yes | N/A (hub is the supervisor; doesn't register itself) |

The three MCP gaps are tracked as issues against the respective repos.
They can land incrementally over months — the pattern doc is the
lighthouse, not a deadline.

## Reference implementation

Most complete: vault. Look at:

- [`parachute-vault/src/routing.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/routing.ts) — full REST API + MCP route dispatch
- [`parachute-vault/src/mcp-http.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/mcp-http.ts) — MCP server (the canonical example for a Parachute-module MCP)
- [`parachute-vault/web/ui/`](https://github.com/ParachuteComputer/parachute-vault/tree/main/web/ui) — admin SPA (the canonical example for a module-side admin UI)
- [`parachute-vault/.parachute/module.json`](https://github.com/ParachuteComputer/parachute-vault/blob/main/.parachute/module.json) — manifest declares paths + `managementUrl` + scopes
- [`parachute-vault/src/self-register.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/self-register.ts) — self-registration

scribe is a close second on every surface; the gap is just that its
admin UI is config-endpoint-based rather than a full SPA. Both shapes
satisfy the pattern.

## The kind-as-taxonomy mistake

`kind` had three values; reality has five-plus orthogonal capability
axes. Two specific things the taxonomy got wrong:

- **`kind: "frontend"`** was originally for "hub static-serves this
  module's dist." Today only the deprecating notes-daemon used it.
  Since parachute-app handles user UIs via its own HTTP server,
  hub-side static-serving for a `frontend` kind has no remaining
  consumer. If we ever need hub-side static-serving again, a
  per-module `staticServe: boolean` (or a `paths` entry that hub
  recognizes as a static mount) is the right shape — not a `kind`
  enum that pretends modules belong to disjoint families.
- **`kind: "tool"`** was indistinguishable from `kind: "api"` in
  routing. Hub treated them the same. The split was an artifact of
  trying to discriminate where there was no real distinction.

hub#327 (2026-05-22) dropped `kind` validation in hub's manifest
parser — the field is now pass-through, retained only so existing
manifests stay valid. parachute-app#14 corrected app from
`kind: "frontend"` to `kind: "api"` for back-compat. The retirement
of the field from module manifests proceeds in
[hub#301](https://github.com/ParachuteComputer/parachute-hub/issues/301)
Phase B/C/D.

## When this pattern applies

- **Committed-core modules** — yes, all five surfaces. Either ship
  them or carry an open issue tracking the gap.
- **Exploration-tier modules** (e.g., runner today, channel) —
  optional. If the module gets promoted to committed-core, expect
  these surfaces to land at or before promotion.
- **Apps (UI bundles inside parachute-app)** — different shape. Apps
  are the *opposite* of backend modules: they're consumers of vault +
  other backend modules. Apps don't expose API/MCP/admin themselves;
  they consume those from the modules they integrate with. The
  parachute-app host module exposes the canonical surfaces *on behalf
  of* the apps it serves.

## Migration path

We don't need to add MCP to every module right away. The pattern doc
captures the direction. Implementation tracks via issues, each landing
when its module's roadmap reaches it:

- [parachute-app#15](https://github.com/ParachuteComputer/parachute-app/issues/15) — add MCP server
- [parachute-runner#5](https://github.com/ParachuteComputer/parachute-runner/issues/5) — add MCP server
- [parachute-hub#328](https://github.com/ParachuteComputer/parachute-hub/issues/328) — add MCP server for hub's own operations
- [parachute-hub#301](https://github.com/ParachuteComputer/parachute-hub/issues/301) Phase B/C/D — drop `kind` from manifests + retire remaining hub-side references

These can land incrementally over months. The pattern doc is the
lighthouse — modules know which way they're heading.

## Related patterns

- [`module-protocol.md`](./module-protocol.md) — the runtime contracts
  every module implements (`/.parachute/info`, `/.parachute/icon.svg`,
  `/.parachute/config*`). Module-surfaces is the broader framing
  inside which module-protocol's contracts live.
- [`module-self-registration.md`](./module-self-registration.md) — how
  a module writes its services.json row at boot.
- [`services-json-row-conventions.md`](./services-json-row-conventions.md)
  — how the row identity is keyed (`manifestName`).
- [`canonical-ports.md`](./canonical-ports.md) — port assignments for
  the per-module HTTP-API surface.
- [`module-json-extensibility.md`](./module-json-extensibility.md) —
  the manifest shape that declares paths, `managementUrl`, scopes.
- [`module-ui-declaration.md`](./module-ui-declaration.md) — `uiUrl`
  for hub-origin-rendered tiles vs. `managementUrl` for module-origin
  admin links.
- [`trust-gradient-isolation.md`](./trust-gradient-isolation.md) — the
  auth gradient every surface shares.
- [`ssrf-safe-fetch.md`](./ssrf-safe-fetch.md) — for modules whose API
  surface fetches external URLs.
- [`runtime-tenancy-contract.md`](./runtime-tenancy-contract.md) — the
  third side of the contract triad: what hosts inject into tenants at
  runtime, mirroring this doc (what modules expose) and
  [`app-bundle-shape.md`](./app-bundle-shape.md) (what apps ship).

## History

- **2026-04-20** — original module-architecture design doc shipped
  with `kind: "api" | "frontend" | "tool"` taxonomy. See
  [`parachute.computer/design/2026-04-20-module-architecture.md`](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-04-20-module-architecture.md).
- **2026-05-21** — parachute-app design redrew committed-core;
  revealed kind-as-taxonomy was the wrong shape for app (had to pick
  `frontend`, then realized it should be `api`). See
  [`parachute.computer/design/2026-05-21-parachute-apps-design.md`](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-05-21-parachute-apps-design.md).
- **2026-05-22** — Aaron explicitly named the framing ("all modules
  should be quite interoperable and have some underlying patterns; I'm
  not sure that how we're organizing them via kind is right");
  [hub#327](https://github.com/ParachuteComputer/parachute-hub/pull/327)
  dropped `kind` validation; this pattern doc landed.
- **Forthcoming** —
  [hub#301](https://github.com/ParachuteComputer/parachute-hub/issues/301)
  Phase B/C/D will drop `kind` from all module.json files. As of this
  doc, [`module-protocol.md`](./module-protocol.md),
  [`module-json-extensibility.md`](./module-json-extensibility.md),
  and [`module-ui-declaration.md`](./module-ui-declaration.md) (which
  references `kind: "tool"` rendering) still document `kind` as
  required; they update once Phase B/C/D lands.
  Tracked at [hub#330](https://github.com/ParachuteComputer/parachute-hub/issues/330).
