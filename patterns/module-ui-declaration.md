# Module UI declaration

Services declare their user-facing UI URL in `module.json`; hub renders
one discovery tile per declaring service.

> **Status: target convention, not yet implemented.** Hub's discovery
> page today hardcodes which services have UIs in a JS
> `SERVICE_LABELS` map at the top of
> [`parachute-hub/src/hub.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/hub.ts)
> (`notes`, `scribe`, `agent`) plus a vault-name filter that suppresses
> vault entries. Titles, descriptions, ordering, and which-services-have-UIs
> are baked in; only the mount `path` is read from `services.json`. This
> doc captures the convention so the hardcoding can retire — services
> declare their UIs, hub renders dynamically.

## Convention

Every module that has a user-facing UI **declares its UI URL in
`module.json`** as a top-level optional field:

```json
{
  "name": "parachute-notes",
  "uiUrl": "/notes",
  "displayName": "Notes",
  "tagline": "Browse your vault content."
}
```

The hub's discovery page reads `uiUrl` (via the well-known doc) and
renders one tile per service that declares it — `displayName` as the
title, `tagline` as the description, `uiUrl` as the link target. Modules
that omit `uiUrl` are still registered (still appear in
`/.well-known/parachute.json`, still routable for API consumers); they
just don't render a clickable card on discovery.

## Shape

```ts
uiUrl?: string;  // path under the hub origin, leading "/"
```

Resolution rules:

- **Path form** — `uiUrl: "/notes"`. `uiUrl` is a path on **hub's
  origin** (not the module's). Hub renders the link as
  `<hub-origin>${uiUrl}` regardless of where the module itself is
  hosted. Leading `/` required; no trailing slash. Hub is the renderer
  of the discovery page; clicks happen from hub, so the relative path
  resolves there. This is **distinct from `managementUrl`'s relative
  form**, which resolves against the *module's own well-known origin*
  — see
  [`module-json-extensibility.md`](./module-json-extensibility.md#managementurl-string).
  The two collapse to the same URL for first-party modules colocated
  on hub's origin, but a third-party module hosted elsewhere would see
  the two diverge.
- **Absolute URL** — `uiUrl: "https://notes.example.com"`. Hub uses
  verbatim. Escape hatch for modules whose UI is hosted somewhere
  other than the hub origin.
- **Omitted** — no tile rendered. Use this for API-only services
  (vault today, scribe today) or services whose UI is only reachable
  via another module (vault content browsed via Notes).

The hub picks `displayName` and `tagline` for the tile from the same
`module.json` fields it already reads
([`module-json-extensibility.md` — Shape](./module-json-extensibility.md#shape))
— no separate per-discovery-tile copy.

## Why

- **Discovery is no longer hub-side knowledge.** Hub doesn't ship a
  hardcoded list of "which services have UIs and what they're called."
  Adding a new service ships a new tile when its `module.json`
  declares one.
- **The use-vs-admin distinction stops mattering at the hub layer.**
  The first cut at the discovery section split tiles into "Use" and
  "Admin"; that broke down because real service UIs mix use, config,
  and admin together (Notes is also where you administer Notes; Agent
  has run + admin in one SPA). Services declare what their UI *is* —
  combining concerns however they want — and hub renders one link.
  See the rationale comment at the top of
  [`parachute-hub/src/hub.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/hub.ts).
- **Author-controlled.** A third-party module that ships a `uiUrl` in
  its `module.json` lights up on the hub's discovery page on install
  with no hub-side change.
- **Backwards-compatible.** Absent field = no tile. Existing
  `module.json` files stay valid unchanged.

## Relationship to `managementUrl`

`managementUrl` (added 2026-05-02, see
[`module-json-extensibility.md` — Hub UI fields](./module-json-extensibility.md#managementurl-string))
already exists as an admin-specific link for hub-owned admin pages —
specifically, the hub's vault-management SPA renders a
"Manage `<displayName>`" link per vault instance pointing at
`<vault-url><managementUrl>`. That covers the case where hub admin
pages need to link out to per-instance module admin UIs.

`uiUrl` is its discovery-side peer:

| Field | Surface | Renders | Cardinality |
| --- | --- | --- | --- |
| `uiUrl` | Hub discovery page | One tile per service | Per service (or per-instance if a service runs multiple) |
| `managementUrl` | Hub admin pages (e.g., vault list) | "Manage `<name>`" link per instance | Per instance |

A service may declare both (e.g., a future combined notes admin SPA
under `/notes` declares both `uiUrl: "/notes"` and `managementUrl:
"/notes/admin"`), one, or neither. They serve different surfaces and
don't conflict.

## Examples

- **`parachute-notes`** — declares `uiUrl: "/notes"`. The Notes PWA is
  the module's UI. Hub discovery renders a Notes tile. No
  `managementUrl` (admin and use are the same surface).
- **`parachute-agent`** — declares `uiUrl: "/agent"`. The agent UI
  combines run, config, and admin. Hub discovery renders an Agent tile.
- **`parachute-scribe`** — omits `uiUrl` today (no UI; CLI- and
  API-only). When the combined transcribe + config UI ships, it adds
  `uiUrl: "/scribe"`.
- **`parachute-vault`** — omits `uiUrl`. Vault content is browsed via
  Notes; a "Vault" tile on discovery would dead-end at the hub-owned
  vault-management SPA, which is the friction Aaron flagged earlier
  ("clicked Vault, took me to hub management"). Vault keeps its
  per-instance `managementUrl: "/admin"` for the hub's vault-list
  page; that's the right surface for "manage this specific vault."

## Rules

- **Path-form `uiUrl` starts with `/`, no trailing slash.** Same
  normalization as `managementUrl`. Hub joins origin + `uiUrl`
  verbatim.
- **`uiUrl` is for the hub discovery page.** Don't hand-jam admin-only
  paths in here when the user-facing UI is what belongs on discovery —
  that's what `managementUrl` is for. If a service has only an admin
  UI and no public-facing surface, declaring it as `uiUrl` is fine
  (Agent's UI is admin-flavored and ships there); the rule is about
  framing, not gating.
- **Hub doesn't sniff or parse the link target.** `uiUrl` is opaque to
  hub. Auth, anonymous-access policy, and what's behind the link are
  the module's concern.
- **Display copy comes from `displayName` + `tagline`.** No separate
  `uiTitle` / `uiDesc` field. If the module wants different copy on
  discovery vs. elsewhere, that's a (rejected for now) signal of
  YAGNI splintering.

## Adoption sequencing

Standard parallel-cross-repo shape (see
[`parallel-cross-repo-PRs.md`](./parallel-cross-repo-PRs.md)):

1. **This PR (parachute-patterns)** — define the convention.
2. **Module `module.json` updates (one PR per module)** —
   `parachute-notes` declares `uiUrl: "/notes"`;
   `parachute-agent` declares `uiUrl: "/agent"`. Vault and scribe stay
   absent at this step. Each module ships its updated `module.json`
   inside its npm artifact.
3. **Hub consumer-side update** — well-known doc carries `uiUrl`
   through; discovery page (`hub.ts`) reads `uiUrl` from
   `/.well-known/parachute.json` and renders one tile per declaring
   service. The hardcoded `SERVICE_LABELS` + `SERVICE_ORDER` arrays
   and the `isVaultName` filter retire. Tile order: stable by service
   `name` alphabetical (or by an explicit `displayOrder` field if a
   need for explicit ordering surfaces — defer until two services
   actually conflict on natural order).

Steps 2 and 3 are backwards-compatible with each other: hub before
step 3 ignores the new field; modules before step 2 simply don't
appear (same behavior as today's hardcoded omission). They can land
in either order.

## Open questions

- **Per-instance `uiUrl` for multi-instance services.** Vault is
  multi-instance (`default`, `boulder`, `techne`); if a future vault
  grows a per-instance use-facing UI (not just admin), each instance
  would want its own UI URL. The `services.json` row shape today is
  per-instance, so the natural extension is "module declares `uiUrl`
  template; vault writes it into each instance's `services.json` row
  on init." Defer until a real use case lands.
- **Auth requirements metadata.** Should `uiUrl` carry whether the UI
  supports anonymous access vs. requires sign-in? Useful for hub to
  hint "Sign in to use Agent" vs. "Open Notes" on the tile. Defer
  until hub discovery actually wants to differentiate; today's "sign
  in to hub, then click anything" flow doesn't need it.
- **`displayOrder` for explicit ordering.** The current hardcoded
  order (`notes`, `scribe`, `agent`) reflects Aaron's preferred
  prominence; alphabetical by name happens to give the same result
  for these three. If a service named `aardvark` later wanted
  bottom-of-list placement, an explicit numeric `displayOrder` (lower
  = earlier) is the obvious knob. Defer.
- **Display kind beyond a single link.** `kind: "tool"` modules (no
  one ships one yet) might want a launch-button vs. a card. Today
  the tile is the only render shape; revisit if a tool-kind module
  actually arrives.

## Where this applies

- **Today (target):** `parachute-notes` (`uiUrl: "/notes"`),
  `parachute-agent` (`uiUrl: "/agent"`).
- **Later:** any first- or third-party module that ships a UI under
  the hub origin. Same field, same shape.
- **Not in scope:** services with no UI (vault today, scribe today)
  simply omit the field.
