# Module UI declaration

Services declare their UI URL in `module.json`; hub renders one
discovery tile per declaring service. For multi-instance services
(vault today), `uiUrl` is a per-instance path that hub prefixes with
the mount path during well-known fan-out.

> **Status: adopted.** Data-driven discovery shipped in hub#288 and
> the consumer-side `uiUrl` reader (`loadServiceUiMetadata`) landed
> with it. The earlier hardcoded `SERVICE_LABELS` map retired; the
> remaining hardcoded surface is the "Browse Vault" tile in the
> Get-started section of [`parachute-hub/src/hub.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/hub.ts),
> which workstream C (UX audit §5 row C, 2026-05-25) retires once
> vault and scribe declare `uiUrl` in their `module.json` files.

## Use vs admin — both can be true

The earlier framing of this doc said "vault has no `uiUrl` because
vault content is browsed via Notes." That framing collapsed two
different audiences into one decision. They split cleanly:

- **End users** browse vault data via Notes. Notes is the user-facing
  surface; vault is the storage backend Notes reads from.
- **Operators** administer the vault — provision, configure, manage
  per-vault tokens, inspect — via vault's own admin SPA at
  `/vault/<name>/admin/`.

`uiUrl` points operators at the admin SPA. It is not content
browsing. The Notes tile (Notes' own `uiUrl`) covers the end-user
surface; the vault tile covers the operator surface. Both belong on
discovery; they're complementary, not duplicative.

The Circle 1 conformance band ([design-system.md §8](./design-system.md#8-where-this-applies))
explicitly names `/vault/<name>/admin/*` and `/scribe/admin` as
admin-chrome surfaces — they exist, they're maintained, they're part
of the Parachute brand surface, and they deserve a discovery tile of
their own.

## Convention

Every committed-core module that has an admin or user-facing UI
**declares its UI URL in `module.json`** as a top-level optional
field:

```json
{
  "name": "parachute-notes",
  "uiUrl": "/notes",
  "displayName": "Notes",
  "tagline": "Browse your vault content."
}
```

The hub's discovery page reads `uiUrl` (via the well-known doc) and
renders one tile per declaring service — `displayName` as the title,
`tagline` as the description, `uiUrl` as the link target. Modules that
omit `uiUrl` are still registered (still appear in
`/.well-known/parachute.json`, still routable for API consumers); they
just don't render a clickable card on discovery.

### Multi-instance services (vault)

Vault runs N instances behind one backend (`/vault/default`,
`/vault/techne`, …). The declared `uiUrl` is the **per-instance path
relative to the vault mount**, not relative to the hub origin. Hub
prefixes it with the per-vault path when building well-known rows.

```json
{
  "name": "parachute-vault",
  "uiUrl": "/admin/",
  "managementUrl": "/admin/",
  "paths": ["/vault/default"]
}
```

For a vault mounted at `/vault/default`, hub emits one services row
per instance with `uiUrl: "/vault/default/admin/"` (the configured
hub origin joined onto the prefixed path). For a vault with paths
`["/vault/default", "/vault/techne"]`, hub emits two rows, each with
its own `uiUrl`. Discovery renders one tile per instance; operators
running multiple vaults see them all.

Single-instance services (scribe, notes, app) declare `uiUrl` as the
hub-origin path directly; the prefix rule degenerates to a no-op
(scribe's `paths: ["/scribe"]` + `uiUrl: "/scribe/admin"` resolves
verbatim).

## Shape

```ts
uiUrl?: string;  // path under the hub origin, leading "/"
```

Resolution rules:

- **Path form (single-instance)** — `uiUrl: "/notes"`. `uiUrl` is a
  path on **hub's origin** (not the module's). Hub renders the link
  as `<hub-origin>${uiUrl}` regardless of where the module itself is
  hosted. Leading `/` required; no trailing slash. Hub is the
  renderer of the discovery page; clicks happen from hub, so the
  relative path resolves there. This is **distinct from
  `managementUrl`'s relative form**, which resolves against the
  *module's own well-known origin* — see
  [`module-json-extensibility.md`](./module-json-extensibility.md#managementurl-string).
  The two collapse to the same URL for first-party modules colocated
  on hub's origin, but a third-party module hosted elsewhere would
  see the two diverge.
- **Path form (multi-instance)** — `uiUrl: "/admin/"`. Hub prefixes
  with the per-instance mount path during well-known fan-out: a
  vault mounted at `/vault/default` resolves the declared `"/admin/"`
  to `<hub-origin>/vault/default/admin/`. Trailing slash permitted on
  multi-instance forms (vault's admin SPA expects one); leading `/`
  required. Today vault is the only multi-instance service.
- **Absolute URL** — `uiUrl: "https://notes.example.com"`. Hub uses
  verbatim, no prefix. Escape hatch for modules whose UI is hosted
  somewhere other than the hub origin.
- **Omitted** — no tile rendered. Use this for API-only services
  (no admin UI shipped yet) or services whose UI is only reachable
  via another module.

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

## `configUiUrl` — the module's own config surface (2026-06-09)

The **[modular-UI architecture](../design/2026-06-09-modular-ui-architecture.md)**
shift adds a third UI-declaration field: `configUiUrl`. It completes the
trio by naming **where the module's own config surface lives** — the surface
the hub frames / links from a uniform config shell, instead of hard-coding a
per-module config view in the hub SPA (the deprecated generic `ModuleConfig`
form, and the bespoke per-module Channels view, were the anti-pattern this
retires).

The three fields divide cleanly by audience and surface:

| Field | Surface | Renders | Resolution base |
| --- | --- | --- | --- |
| `uiUrl` | Hub **discovery** page | One **tile** per service (the user-facing UI) | hub origin |
| `managementUrl` | Hub **admin** pages | "Manage `<name>`" **deep-link** per instance | module's own well-known origin |
| `configUiUrl` | Hub **config shell** | The module's **own config surface** (hub frames / links it) | module's own well-known origin |

```ts
configUiUrl?: string;  // path or full URL — the module's own config surface
```

- **uiUrl = the discovery tile.** "Here's the thing; go use it."
- **managementUrl = an admin deep-link.** "Manage this instance" from a
  hub admin list (today: the per-vault list).
- **configUiUrl = the module's own config surface.** The hub renders one
  consistent config shell and frames / links each module's `configUiUrl`;
  the module owns the config UI end-to-end. This is the machine-readable
  form of the "modules own their config UIs" principle. Resolution follows
  `managementUrl`'s rules (relative → module's well-known origin; absolute →
  verbatim).

A module may declare any subset. Examples from the modular-UI arc:

- **scribe** — `uiUrl: "/scribe/admin"` (discovery tile) and
  `configUiUrl: "/scribe/admin"` may point at the same self-served surface;
  scribe's admin HTML *is* its config UI. Note the two strings resolve
  against **different bases** — `uiUrl` against the hub origin, `configUiUrl`
  against the module's own origin — and only collapse to the same URL because
  scribe is co-located on the hub origin. A third-party module hosted
  elsewhere would see them diverge.
- **channel** — builds + serves a config/admin UI (manage channels /
  transports) and declares `configUiUrl` for it (`focus: "experimental"`).
- **runner** — builds + serves a job-listing / config UI and declares
  `configUiUrl`.

Full field catalog + the `focus` / `events` / `actions` peers:
[`module-json-extensibility.md` — Modular-UI fields](./module-json-extensibility.md#modular-ui-fields).
The discovery-side `focus` tier (self-registration, no whitelist) is in
[`module-discovery.md`](./module-discovery.md).

## Examples

- **`parachute-notes`** — declares `uiUrl: "/notes"`. The Notes PWA is
  the module's UI. Hub discovery renders a Notes tile. No
  `managementUrl` (admin and use are the same surface).
- **`parachute-surface`** — declares `uiUrl: "/surface/admin/"` for the
  app-admin SPA (managing bundled UIs); the PWA apps like Notes are
  separately surfaced via their own modules' `uiUrl`.
- **`parachute-scribe`** — declares `uiUrl: "/scribe/admin"`. The
  server-rendered admin page (`src/admin-ui.ts`) is the operator
  surface — config form, provider status, credential clearing. No
  `managementUrl` (single-instance, no hub-side vault-list surface).
- **`parachute-vault`** — declares `uiUrl: "/admin/"` (multi-instance
  form). Hub prefixes with the per-vault mount path on emission,
  producing one tile per vault instance pointing at
  `/vault/<name>/admin/`. The earlier "vault content is browsed via
  Notes — no tile" rule is retired: Notes covers the end-user surface,
  vault's admin SPA covers the operator surface (per-vault tokens,
  config, MCP). Both deserve discovery presence. Vault keeps its
  per-instance `managementUrl: "/admin/"` for the hub admin SPA's
  vault-list "Manage" link — a different surface, same target path.

## Rules

- **Path-form `uiUrl` starts with `/`.** Single-instance forms omit
  the trailing slash (`/notes`, `/scribe/admin`); multi-instance
  forms may include it (`/admin/`) when the target SPA expects it.
  Hub joins origin + (mount path if multi-instance) + `uiUrl`
  verbatim — no extra normalization.
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

1. **Patterns** — define the convention (this doc).
2. **Module `module.json` updates (one PR per module)** —
   `parachute-notes` declares `uiUrl: "/notes"`,
   `parachute-surface` declares `uiUrl: "/surface/admin/"`,
   `parachute-scribe` declares `uiUrl: "/scribe/admin"`,
   `parachute-vault` declares `uiUrl: "/admin/"` (multi-instance form).
   Each module ships its updated `module.json` inside its npm artifact.
3. **Hub consumer-side update** — well-known doc carries `uiUrl`
   through; discovery page (`hub.ts`) reads `uiUrl` from
   `/.well-known/parachute.json` and renders one tile per declaring
   service. The hardcoded `SERVICE_LABELS` / `SERVICE_ORDER` arrays
   and the `isVaultName` filter retired in hub#288. The hardcoded
   "Browse Vault" Get-started tile (added in hub#342 as a stopgap)
   retires under workstream C once vault declares `uiUrl` and hub
   reads it for vault entries (the current `loadServiceUiMetadata`
   skips vault rows; lift that skip and have `buildWellKnown`
   prefix the declared `uiUrl` with the per-instance mount path).
   Tile order: stable by service `displayName` alphabetical (or by
   an explicit `displayOrder` field if a need for explicit ordering
   surfaces — defer until two services actually conflict on natural
   order).

Steps 2 and 3 are backwards-compatible with each other: hub before
step 3 ignores the new field; modules before step 2 simply don't
appear (same behavior as today's omission). They can land in either
order.

## Open questions

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
- **Tile shape beyond a single link.** Today the tile is the only
  render shape; if a module ever wants a launch-button or a richer
  card, the decision is driven by whether the module declares
  `uiUrl` (discovery tile), `managementUrl` (admin link), or both.
  Defer until a real use case lands.

## Where this applies

- **Today (committed-core):**
  - `parachute-notes` — `uiUrl: "/notes"`.
  - `parachute-surface` — `uiUrl: "/surface/admin/"`.
  - `parachute-scribe` — `uiUrl: "/scribe/admin"` (workstream C).
  - `parachute-vault` — `uiUrl: "/admin/"` (workstream C, multi-instance form).
- **Later:** any first- or third-party module that ships a UI under
  the hub origin. Same field, same shape.
- **Not in scope:** services with truly no operator-facing UI simply
  omit the field. No committed-core module is in this bucket today —
  every module has at least an admin surface to declare.
