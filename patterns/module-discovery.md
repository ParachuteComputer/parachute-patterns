# Module discovery — umbrella

> Signpost across the module-cluster pattern docs. **If you're trying
> to X, read Y.** This file links — it doesn't duplicate. The
> authoritative shape for each piece lives in the linked doc; if those
> diverge from this one, the linked doc wins.

## The lifecycle at a glance

```
                  Author publishes npm package with
                  .parachute/module.json shipped inside
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────┐
   │  `parachute install <pkg>`                                │
   │  • CLI reads module.json                                   │
   │  • Writes ~/.parachute/services.json entry                 │
   │  • Runs `init.command` (one-shot, safety-checked)          │
   └──────────────────────────────┬───────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────┐
   │  Hub serves /.well-known/parachute.json                   │
   │  • Aggregates services.json + each module's well-known   │
   │  • Renders discovery tiles per module's `uiUrl`           │
   │  • Renders "Manage" links per module's `managementUrl`    │
   └──────────────────────────────┬───────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────┐
   │  Clients discover module capability                       │
   │  • MCP clients hit <module-url>/mcp (Streamable HTTP)     │
   │  • Vault MCP returns the projection brief at initialize   │
   │  • OAuth-aware clients discover AS via well-known         │
   └──────────────────────────────────────────────────────────┘
```

## Self-registration is the single source of truth (2026-06-09)

The **[modular-UI architecture](../design/2026-06-09-modular-ui-architecture.md)**
shift settles a long-standing inconsistency: discovery is driven by
**self-registration**, not a curated whitelist.

Previously the hub's Modules screen was gated by a hardcoded
`CURATED_MODULES = ["vault","scribe"]` constant. A module could be running,
proxied, supervised, and self-registered in `services.json` — yet
administratively invisible and un-installable because it wasn't in that
constant (channel hit exactly this). Three registries disagreed
(`CURATED_MODULES` vs `services.json` vs `FIRST_PARTY_FALLBACKS` /
`KNOWN_MODULES`).

The model now:

- **Enumeration = self-registration.** The Modules screen and `/api/modules`
  enumerate the union of `services.json` ∪ each module's `module.json` ∪ the
  supervisor's live children. **No whitelist decides visibility.** The other
  registries (`KNOWN_MODULES`) survive only as an **install-time bootstrap**
  index (resolve a name → installable package), not as a visibility gate.
- **`focus` de-emphasizes, never hides.** A module's `module.json` declares
  `focus: "core" | "experimental"` (see
  [`module-json-extensibility.md` — Modular-UI fields](./module-json-extensibility.md#modular-ui-fields)).
  The hub uses it to **sort and label** — `"core"` first, `"experimental"`
  de-emphasized — but every self-registered module appears. Unlisted →
  `"experimental"`.

This retires the curated-whitelist model. The propagation checklist is
[`../migrations/2026-06-09-modular-ui.md`](../migrations/2026-06-09-modular-ui.md).

## If you're trying to…

### Understand the three-layer module contract (services.json, well-known, module.json)

Read [`module-protocol.md`](./module-protocol.md). The primary
reference: storage layer (`~/.parachute/services.json`), discovery
layer (`/.well-known/parachute.json`), declaration layer
(`.parachute/module.json` shipped in the npm package). Every other
file in this cluster is a refinement of one slot in that protocol.

### Declare a new module (third-party or first-party)

Read [`module-json-extensibility.md`](./module-json-extensibility.md).
The full `module.json` field catalog — `name`, `manifestName`,
`displayName`, `tagline`, `port`, `paths`, `health`,
`startCmd`, `scopes`, `dependencies`, plus the extensibility fields
(`hasAuth`, `init`, `urlForEntry`, `managementUrl`, `uiUrl`) and the
2026-06-09 modular-UI fields (`focus`, `configUiUrl`, `configSchema`,
`adminCapabilities`, `events`, `actions`). No `@openparachute/` scope or
`parachute-*` prefix required; the contract is what makes a module a module.

### Render your module in the hub's discovery section

Read [`module-ui-declaration.md`](./module-ui-declaration.md).
Declare `uiUrl` in `module.json` and hub renders one tile per
service that declares it. Path form resolves against hub's origin
(distinct from `managementUrl`'s relative form, which resolves
against the module's own well-known origin). Absent = no tile.

### Expose MCP tools from your module

Read [`mcp-transport.md`](./mcp-transport.md). Streamable HTTP at
`<base>/mcp` + `Authorization: Bearer <token>`. Both OAuth bearers
and `pvt_*` PATs validate the same way. Discovery via RFC 8414
metadata — links into the auth cluster
([`well-known-discovery-rfc.md`](./well-known-discovery-rfc.md),
[`hub-as-issuer.md`](./hub-as-issuer.md)).

### Surface a rich projection of your module's shape at MCP `initialize`

Read [`vault-mcp-discovery.md`](./vault-mcp-discovery.md). Vault's
reference implementation: one source (`buildVaultProjection`), two
surfaces (markdown brief in `initialize` response + JSON via the
`vault-info` tool), scope-filtered symmetrically. Tags +
inheritance + effective_fields + indexed_fields + query_hints +
optional stats. Other modules with non-trivial shape can adopt the
same one-source-two-surfaces pattern.

## Worked example: vault declares itself

> **Note.** This example shows the full-complement *target* shape — the
> fields a future vault would emit once `hasAuth`, `init`, and
> `urlForEntry.perConsumer` flow through `module.json` end-to-end
> (today some of those declarations still live in hub's transitional
> `FIRST_PARTY_FALLBACKS` per
> [`module-json-extensibility.md`](./module-json-extensibility.md)).
> Vault's currently-shipped
> [`.parachute/module.json`](https://github.com/ParachuteComputer/parachute-vault/blob/main/.parachute/module.json)
> is simpler: `name`, `manifestName`, `displayName`, `tagline`,
> `port`, `paths`, `health`, `managementUrl`, `startCmd`, and
> a `scopes` object with a `defines` array. For the canonical field
> catalog see
> [`module-json-extensibility.md`](./module-json-extensibility.md).

The canonical end-to-end (target shape):

**1. `parachute-vault/.parachute/module.json`** declares the module:

```json
{
  "name": "parachute-vault",
  "manifestName": "@openparachute/vault",
  "displayName": "Vault",
  "tagline": "Personal knowledge graph",
  "port": 1940,
  "paths": ["/vault/:name"],
  "health": "/vault/:name/health",
  "startCmd": ["parachute-vault", "serve"],
  "hasAuth": true,
  "init": { "command": ["parachute-vault", "init"] },
  "urlForEntry": {
    "perConsumer": {
      "claude.ai": { "appendPath": "/mcp" }
    }
  },
  "managementUrl": "/admin/",
  "scopes": { "defines": ["vault:<name>:read", "vault:<name>:write", "vault:<name>:admin"] }
}
```

The field catalog is in
[`module-json-extensibility.md`](./module-json-extensibility.md);
`managementUrl` is the relative-resolves-against-module shape per
the same doc (trailing slash deliberate per its fragment-token-SPA
section); `init` carries a safety constraint that `command[0]` must
equal a bin from the installed npm package.

**2. `parachute install @openparachute/vault`** populates
`~/.parachute/services.json` with the entry, runs `init.command`,
and starts the service.
[`module-protocol.md`](./module-protocol.md) §1-2.

**3. Hub serves the well-known aggregate** at
`/.well-known/parachute.json`. Each vault entry includes its
`uiUrl` (intentionally omitted in vault's case — vault content is
browsed via Notes, see
[`module-ui-declaration.md`](./module-ui-declaration.md)'s adoption
note) and `managementUrl` so hub's admin page renders a "Manage
Vault `<name>`" link.
[`module-protocol.md`](./module-protocol.md) §2.

**4. An MCP client connects** to `<vault-url>/mcp` over Streamable
HTTP. The `initialize` response includes a markdown
`serverInstructions` payload — the vault projection brief — built
from `buildVaultProjection`. The client gets the vault's shape
(tags, schemas, indexed fields, query hints) before issuing its
first real tool call.
[`mcp-transport.md`](./mcp-transport.md) +
[`vault-mcp-discovery.md`](./vault-mcp-discovery.md).

**5. An OAuth-capable client** discovers the AS via
`/.well-known/oauth-authorization-server/vault/<name>` per
[`well-known-discovery-rfc.md`](./well-known-discovery-rfc.md),
sees the hub origin in `issuer` per
[`hub-as-issuer.md`](./hub-as-issuer.md), and runs the full DCR +
consent dance with the auth cluster's
[`auth-stack.md`](./auth-stack.md) shapes.

## How the cluster composes with the auth cluster

The module-discovery cluster and the auth cluster overlap at two
seams:

- **`hasAuth: true`** in `module.json` signals the module is an
  OAuth resource server. Hub keys its publicExposure derivation off
  this; the resource server itself adopts
  [`auth-stack.md`](./auth-stack.md) wholesale.
- **`urlForEntry.perConsumer`** declarations describe per-consumer
  URL adjustments for clients that read the well-known aggregate.
  Today's only case: claude.ai appends `/mcp` to vault entries.

For everything else, the two clusters are orthogonal: module
discovery answers "where does this thing live and what does it
expose"; auth answers "who's allowed to talk to it."

## Cross-links

- [`module-protocol.md`](./module-protocol.md) — three-layer
  protocol (storage / discovery / declaration)
- [`module-json-extensibility.md`](./module-json-extensibility.md)
  — full `module.json` field catalog
- [`module-ui-declaration.md`](./module-ui-declaration.md) — `uiUrl`
  + hub discovery tiles
- [`mcp-transport.md`](./mcp-transport.md) — Streamable HTTP at
  `<base>/mcp`
- [`vault-mcp-discovery.md`](./vault-mcp-discovery.md) — vault's
  one-source-two-surfaces projection pattern
- [`auth-stack.md`](./auth-stack.md) — the auth cluster, hooked in
  at `hasAuth: true`
- [`governance.md`](./governance.md) Rule 3 — patterns-check
  discipline
