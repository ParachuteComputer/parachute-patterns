# Surface bundle shape

> A Parachute surface is a static UI bundle consumed by parachute-surface,
> the host module. The minimum surface is `dist/` (build output) +
> `meta.json` (declaration). No daemon, no port, no MCP — surfaces consume
> backend modules via OAuth-scoped HTTP from the browser. Mirror of
> [`module-surfaces.md`](./module-surfaces.md) for the consumer side
> of the same ecosystem.

## The convention (TL;DR)

A Parachute surface ships:

| File | Required? | Purpose |
|---|---|---|
| `dist/` | yes | Build output. Whatever the build tool produces. |
| `dist/index.html` | yes | SPA entry point. parachute-surface refuses to mount a bundle missing this. |
| `meta.json` | yes | Declaration: name, displayName, path, scopes, optional fields. Lives as a sibling of `dist/`, not inside it. |
| `package.json` | recommended | If publishing to npm — the canonical install path under parachute-surface. |
| `LICENSE`, `README.md`, `CHANGELOG.md` | recommended | Standard publish hygiene. |

The `meta.json` MUST validate against
[`parachute-surface/packages/app-host/src/meta-schema.ts`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/app-host/src/meta-schema.ts)'s
`parseMeta()` — that's the live source of truth. The Draft-07 shape
returned by `metaSchemaJson()` is published at
`https://parachute.computer/schemas/app-ui-meta.json` for editors.

For an npm-published app, the `package.json` `files` array should
include `dist`, `meta.json`, and standard hygiene files. See
[`@openparachute/notes-ui`'s package.json](https://github.com/ParachuteComputer/parachute-notes/blob/main/packages/notes-ui/package.json)
for the canonical shape.

## Why — the constraint that produced it

Apps are intentionally minimal. The full list of "Parachute-ness" an
app needs is: a sibling `meta.json` declaring the mount path + display
name + scopes. Everything else is "a static SPA that hits OAuth-scoped
HTTP endpoints." Build with anything; the contract is metadata +
assets.

What's deliberately absent:

- **No daemon** → no port allocation, no lifecycle to supervise, no
  auth surface to build, no per-app `services.json` row.
- **No MCP server, no backend** → surfaces DELEGATE data + agentic-LLM
  surfaces to vault (and other backend modules). An app that grew its
  own backend is a module-plus-app, not a surface.
- **No path negotiation** → surfaces mount under `/surface/<name>/`. The
  parachute-surface daemon proxies via the single row it self-registers
  for `/surface/`.

The simplification produced a clean two-axis split with backend
modules ([`module-surfaces.md`](./module-surfaces.md)): modules expose
the canonical surfaces (API / admin / MCP / health / self-reg); surfaces
consume them.

Aaron's framing (2026-05-22):

> I see app being like vault — we want to be able to spin up separate
> surfaces easy, so it should be easy for another person with a simple
> Claude skill or something to create a new app frontend.

Vault hosts named vaults; app hosts named surfaces. Same shape, different
content. The pattern doc canonicalizes the contract so future surfaces
(and a future scaffolder) point at one source.

## Mount-agnosticism

An app bundle MUST work at any `/surface/<name>/` mount where `<name>` is
set by the operator at install time. Don't bake in a specific path.

Specifically:

- **Vite build with `base: ""`** — emits relative asset URLs that
  work at any mount when paired with the host's `<base href>`
  injection (see
  [`runtime-tenancy-contract.md`](./runtime-tenancy-contract.md)).
- **React Router `basename`** derived at runtime via
  `@openparachute/surface-client#getMountBase()`. Don't read
  `import.meta.env.BASE_URL` for the basename.
- **OAuth callback URLs** derived from the runtime mount. The DCR
  (Dynamic Client Registration) flow registers redirect URIs that
  match the actual mount.
- **PWA manifest `start_url` / `scope`** are an acknowledged
  limitation — PWA install requires a build-time-pinned base because
  `manifest.webmanifest`'s URLs are static. Operators who want PWA at
  non-default mounts must build with `VITE_BASE_PATH=/surface/<name>/`.
  The bundle should DETECT the mismatch and skip SW registration
  gracefully (see
  [notes-ui#160](https://github.com/ParachuteComputer/parachute-notes/issues/160)
  for the reference implementation).

The runtime mount is provided by the host via injected meta tags. The
canonical set is `parachute-mount` (the mount path), `parachute-hub`
(hub origin), `parachute-vault` (bound vault path, when applicable),
`parachute-tenant-id` (tenant's logical name). Read them through
`@openparachute/surface-client`; don't regex-detect from
`window.location.pathname` (that pattern was the interim during
notes-ui's 0.1.1 rollout — phasing out as app-client lands).

For the full host↔tenant runtime metadata contract — including
`<base href>` injection, hub origin, and bound vault discovery — see
[`runtime-tenancy-contract.md`](./runtime-tenancy-contract.md).

## The `meta.json` fields

Quick reference. Canonical source:
[`meta-schema.ts`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/app-host/src/meta-schema.ts).

**Required:**

- `name` (string, `^[a-z][a-z0-9-]*$`) — directory + URL key.
  Becomes `~/.parachute/surface/uis/<name>/` on the host and the OAuth
  client name.
- `displayName` (non-empty string) — human-readable label rendered in
  the admin SPA + hub discovery.
- `path` (string, `^/surface/[a-z0-9-]+$`) — mount path, single-segment
  under `/surface/`.

**Recommended:**

- `tagline` (string) — one-liner under `displayName`.
- `scopes_required` (string[]) — defaults to `["vault:*:read"]`.
  Wildcard (`vault:*:read`) for vault-agnostic UIs; concrete
  (`vault:gitcoin:read`) for vault-bound UIs. See
  [`oauth-scopes.md`](./oauth-scopes.md).
- `version` (string) — free-form. Surfaced for diagnostics.
- `iconUrl` (string) — favicon/icon path relative to `dist/`.

**Optional:**

- `vault_default` (non-empty string) — pins the surface to one named vault.
  Omit for vault-agnostic surfaces that surface a picker.
- `pwa` (boolean, default `false`) — declares PWA mode. When `true`,
  `pwa_service_worker` is required.
- `pwa_service_worker` (string, relative path within `dist/`) — SW
  file path. App serves it with no-cache headers. Leading-slash form
  rejected at parse time — use `sw.js`, not `/sw.js`.
- `public` (boolean, default `false`) — when `true`, hub does NOT
  enforce a session gate at `/surface/<name>/*`. Use sparingly.
- `required_schema` ({ tags: [...] }) — tag-role declarations the
  app needs vault to have. Phase 2.0 validates the shape; Phase 2.1+
  will auto-provision missing tag definitions in vault. Per
  [patterns#57](https://github.com/ParachuteComputer/parachute-patterns/issues/57).
- `dev_watch_dir`, `dev_build_cmd`, `dev_debounce_ms` — Phase 3.0
  dev-mode file watcher knobs. Operators iterating from a source
  checkout point these at the source directory and a build command.
  `dev_watch_dir` also rejects leading-slash absolute paths at parse
  time (use a path relative to your checkout). See
  [`dev-mode-sse-live-reload.md`](./dev-mode-sse-live-reload.md).

`$schema` (optional, top-level) — point at
`https://parachute.computer/schemas/app-ui-meta.json` to get
schema-aware autocomplete + validation in editors. Not required by
`parseMeta()`; purely operator ergonomics.

Three fields are default-filled at parse time so consumers can read
them unconditionally: `scopes_required` (→ `["vault:*:read"]`), `pwa`
(→ `false`), `public` (→ `false`). Other optional fields stay
`undefined` when absent — code reading them needs to handle that.

## Reference implementation

**[`@openparachute/notes-ui`](https://github.com/ParachuteComputer/parachute-surface/tree/main/packages/notes-ui)**
— the bundled reference surface, shipped inside `parachute-surface`
(moved from the archived `parachute-notes` repo 2026-05-24). Vault
read+write, PWA mode, declares `required_schema` for `capture` /
`capture/text` / `capture/voice` tag types. See
[`parachute-surface/packages/notes-ui/meta.json`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/notes-ui/meta.json)
(originally parachute-notes PR #158).

```json
{
  "$schema": "https://parachute.computer/schemas/app-ui-meta.json",
  "name": "notes",
  "displayName": "Notes",
  "tagline": "Capture and browse notes in your vault.",
  "path": "/surface/notes",
  "iconUrl": "icon.svg",
  "scopes_required": ["vault:*:read", "vault:*:write"],
  "pwa": true,
  "pwa_service_worker": "sw.js",
  "required_schema": {
    "tags": [
      { "name": "capture", "description": "Notes captured directly by the user (text or voice)." },
      { "name": "capture/text", "description": "Text capture." },
      { "name": "capture/voice", "description": "Voice capture." }
    ]
  }
}
```

More canonical examples will be added as the ecosystem grows (Gitcoin
Brain, Unforced Brain, and any third-party surfaces).

## How a surface is installed under parachute-surface

Three paths, all converging on the same disk layout:

1. **npm-published** — `parachute-surface add @openparachute/notes-ui`.
   parachute-surface spawns `bun add` into a staging dir, locates the
   package's sibling `dist/` + `meta.json`, copies them to
   `~/.parachute/surface/uis/<name>/`. This is the path most surfaces will
   reach for; see
   [`npm-fetch.ts`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/app-host/src/npm-fetch.ts).

2. **Local directory** — `parachute-surface add ./path/to/my-app/`.
   Same destination, no npm round-trip. Used during local development
   and for unpublished forks.

3. **Bootstrap default** — configured in `~/.parachute/surface/config.json`
   under `bootstrap_default_apps.surfaces`. Runs on first daemon boot when
   `~/.parachute/surface/uis/` is empty. Notes ships as the canonical
   first bootstrap default. See
   [`bootstrap-on-first-boot.md`](./bootstrap-on-first-boot.md).

In all three cases, parachute-surface:

1. Copies (or fetches) the bundle to `~/.parachute/surface/uis/<name>/dist/`.
2. Reads + validates the sibling `meta.json` via `parseMeta()`.
3. Registers the path with hub (via the parachute-surface `services.json`
   row's hierarchical `uis` map; see design doc section 12).
4. Serves `/surface/<name>/*` from the bundle's `dist/`.

The discovery loop in
[`ui-registry.ts`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/app-host/src/ui-registry.ts)
treats malformed bundles as best-effort: an invalid `meta.json` or
missing `dist/index.html` is skipped + surfaced in the admin SPA, not
fatal to the daemon.

## What surfaces DON'T have (architectural distinctions)

Apps are not modules:

- No `paths` field in `services.json` — they don't claim hub paths
  directly. parachute-surface mounts them under its own `/surface/` claim.
- No `health` endpoint — the parent app daemon's health covers them.
- No MCP server — they consume vault's MCP via OAuth; if you need an
  app-specific MCP surface, you're building a backend module.
- No `/.parachute/info` endpoint — no module-protocol surface.
- No self-registration — parachute-surface's `services.json` row absorbs
  the per-UI declarations.
- No port — surfaces don't bind anything; they're files on disk.

If you find yourself needing one of these, you're building a backend
module, not a surface. Use [`module-surfaces.md`](./module-surfaces.md).

## The "easy to create" arc (forthcoming work)

These build on this pattern doc as the contract:

- **`parachute-surface scaffold <name>`** — TBD; generates a starter app
  directory with `meta.json`, a build config, and vault-client wiring.
  Different framework templates (Vite+React default; vanilla HTML for
  the simplest case). Tracked at
  [parachute-surface#17](https://github.com/ParachuteComputer/parachute-surface/issues/17)
  (TBD).
- **`/create-parachute-surface` Claude skill** — TBD; natural-language
  scaffolding. The operator describes a use case, the skill generates
  a working starter. Tracked at
  [parachute-surface#18](https://github.com/ParachuteComputer/parachute-surface/issues/18)
  (TBD).
- **`parachute-surface validate-bundle <path-or-tarball>`** — TBD; CLI
  that runs `parseMeta()` against a built bundle so CI can catch shape
  drift before publish.

## Related patterns

- [`module-surfaces.md`](./module-surfaces.md) — mirror pattern for
  backend modules. Apps consume what modules expose.
- [`mount-path-convention.md`](./mount-path-convention.md) — how an
  SPA at `/surface/<name>/` configures its routing (`base` / `basename` /
  internal routes).
- [`runtime-tenancy-contract.md`](./runtime-tenancy-contract.md) — the
  host↔tenant runtime metadata handshake that makes mount-agnostic
  bundles possible.
- [`canonical-ports.md`](./canonical-ports.md) — surfaces don't have
  ports; backend modules do. Reference for the other side.
- [`oauth-scopes.md`](./oauth-scopes.md) — scope-string shape that
  populates `scopes_required`.
- [`oauth-dcr-approval.md`](./oauth-dcr-approval.md) — how a surface
  registers as an OAuth client at install time.
- [`bootstrap-on-first-boot.md`](./bootstrap-on-first-boot.md) — how
  parachute-surface bootstraps default surfaces on a fresh install.
- [`dev-mode-sse-live-reload.md`](./dev-mode-sse-live-reload.md) —
  what `dev_watch_dir` / `dev_build_cmd` / `dev_debounce_ms` plug
  into.

## History

- **2026-05-21** —
  [parachute-surface design doc §5](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-05-21-parachute-surfaces-design.md#5-per-ui-metadata-schema--metajson-draft-07)
  articulated the `meta.json` schema. App design landed with notes-ui
  earmarked as the first canonical app.
- **2026-05-22** — Notes-as-app migration completed. `notes-ui`
  became the first published app (`@openparachute/notes-ui`).
- **2026-05-23** — Aaron's bootstrap loop revealed missing `meta.json`
  in `notes-ui`'s npm tarball; PR #158 fixed it. This pattern doc
  landed to canonicalize the contract so future surfaces (and a future
  scaffolder) have a single source to point at. The Phase 2.0
  `required_schema`, Phase 3.0 `dev_*` knobs, PWA fields, and
  `public` are all live in `meta-schema.ts` as of this doc.
- **2026-05-23 (v2)** — Mount-agnosticism section added. Aaron's
  install loop revealed that bundles with `VITE_BASE_PATH` baked in
  broke at operator-chosen mounts; notes-ui#159 shipped interim regex
  detection, and the canonical answer became explicit host-injected
  metadata — see
  [`runtime-tenancy-contract.md`](./runtime-tenancy-contract.md).
  Closes
  [parachute-patterns#80](https://github.com/ParachuteComputer/parachute-patterns/issues/80).
