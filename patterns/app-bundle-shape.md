# App bundle shape

> A Parachute "app" is a static UI bundle consumed by parachute-app,
> the host module. The minimum surface is `dist/` (build output) +
> `meta.json` (declaration). No daemon, no port, no MCP — apps consume
> backend modules via OAuth-scoped HTTP from the browser. Mirror of
> [`module-surfaces.md`](./module-surfaces.md) for the consumer side
> of the same ecosystem.

## The convention (TL;DR)

A Parachute app ships:

| File | Required? | Purpose |
|---|---|---|
| `dist/` | yes | Build output. Whatever the build tool produces. |
| `dist/index.html` | yes | SPA entry point. parachute-app refuses to mount a bundle missing this. |
| `meta.json` | yes | Declaration: name, displayName, path, scopes, optional fields. Lives as a sibling of `dist/`, not inside it. |
| `package.json` | recommended | If publishing to npm — the canonical install path under parachute-app. |
| `LICENSE`, `README.md`, `CHANGELOG.md` | recommended | Standard publish hygiene. |

The `meta.json` MUST validate against
[`parachute-app/packages/app-host/src/meta-schema.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/meta-schema.ts)'s
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
- **No MCP server, no backend** → apps DELEGATE data + agentic-LLM
  surfaces to vault (and other backend modules). An app that grew its
  own backend is a module-plus-app, not an app.
- **No path negotiation** → apps mount under `/app/<name>/`. The
  parachute-app daemon proxies via the single row it self-registers
  for `/app/`.

The simplification produced a clean two-axis split with backend
modules ([`module-surfaces.md`](./module-surfaces.md)): modules expose
the canonical surfaces (API / admin / MCP / health / self-reg); apps
consume them.

Aaron's framing (2026-05-22):

> I see app being like vault — we want to be able to spin up separate
> apps easy, so it should be easy for another person with a simple
> Claude skill or something to create a new app frontend.

Vault hosts named vaults; app hosts named apps. Same shape, different
content. The pattern doc canonicalizes the contract so future apps
(and a future scaffolder) point at one source.

## The `meta.json` fields

Quick reference. Canonical source:
[`meta-schema.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/meta-schema.ts).

**Required:**

- `name` (string, `^[a-z][a-z0-9-]*$`) — directory + URL key.
  Becomes `~/.parachute/app/uis/<name>/` on the host and the OAuth
  client name.
- `displayName` (non-empty string) — human-readable label rendered in
  the admin SPA + hub discovery.
- `path` (string, `^/app/[a-z0-9-]+$`) — mount path, single-segment
  under `/app/`.

**Recommended:**

- `tagline` (string) — one-liner under `displayName`.
- `scopes_required` (string[]) — defaults to `["vault:*:read"]`.
  Wildcard (`vault:*:read`) for vault-agnostic UIs; concrete
  (`vault:gitcoin:read`) for vault-bound UIs. See
  [`oauth-scopes.md`](./oauth-scopes.md).
- `version` (string) — free-form. Surfaced for diagnostics.
- `iconUrl` (string) — favicon/icon path relative to `dist/`.

**Optional:**

- `vault_default` (non-empty string) — pins the app to one named vault.
  Omit for vault-agnostic apps that surface a picker.
- `pwa` (boolean, default `false`) — declares PWA mode. When `true`,
  `pwa_service_worker` is required.
- `pwa_service_worker` (string, relative path within `dist/`) — SW
  file path. App serves it with no-cache headers.
- `public` (boolean, default `false`) — when `true`, hub does NOT
  enforce a session gate at `/app/<name>/*`. Use sparingly.
- `required_schema` ({ tags: [...] }) — tag-role declarations the
  app needs vault to have. Phase 2.0 validates the shape; Phase 2.1+
  will auto-provision missing tag definitions in vault. Per
  [patterns#57](https://github.com/ParachuteComputer/parachute-patterns/issues/57).
- `dev_watch_dir`, `dev_build_cmd`, `dev_debounce_ms` — Phase 3.0
  dev-mode file watcher knobs. Operators iterating from a source
  checkout point these at the source directory and a build command.
  See [`dev-mode-sse-live-reload.md`](./dev-mode-sse-live-reload.md).

Defaults are filled at parse time so consumers can read every field
unconditionally.

## Reference implementation

**[`@openparachute/notes-ui`](https://github.com/ParachuteComputer/parachute-notes/tree/main/packages/notes-ui)**
— first canonical app. Vault read+write, PWA mode, declares
`required_schema` for `capture` / `capture/text` / `capture/voice` tag
types. See
[`parachute-notes/packages/notes-ui/meta.json`](https://github.com/ParachuteComputer/parachute-notes/blob/main/packages/notes-ui/meta.json)
(PR #158).

```json
{
  "$schema": "https://parachute.computer/schemas/app-ui-meta.json",
  "name": "notes",
  "displayName": "Notes",
  "tagline": "Notes PWA backed by your vault.",
  "path": "/app/notes",
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
Brain, Unforced Brain, and any third-party apps).

## How an app is installed under parachute-app

Three paths, all converging on the same disk layout:

1. **npm-published** — `parachute-app add @openparachute/notes-ui`.
   parachute-app spawns `bun add` into a staging dir, locates the
   package's sibling `dist/` + `meta.json`, copies them to
   `~/.parachute/app/uis/<name>/`. This is the path most apps will
   reach for; see
   [`npm-fetch.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/npm-fetch.ts).

2. **Local directory** — `parachute-app add ./path/to/my-app/`.
   Same destination, no npm round-trip. Used during local development
   and for unpublished forks.

3. **Bootstrap default** — configured in `~/.parachute/app/config.json`
   under `bootstrap_default_apps.apps`. Runs on first daemon boot when
   `~/.parachute/app/uis/` is empty. Notes ships as the canonical
   first bootstrap default. See
   [`bootstrap-on-first-boot.md`](./bootstrap-on-first-boot.md).

In all three cases, parachute-app:

1. Copies (or fetches) the bundle to `~/.parachute/app/uis/<name>/dist/`.
2. Reads + validates the sibling `meta.json` via `parseMeta()`.
3. Registers the path with hub (via the parachute-app `services.json`
   row's hierarchical `uis` map; see design doc section 12).
4. Serves `/app/<name>/*` from the bundle's `dist/`.

The discovery loop in
[`ui-registry.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/ui-registry.ts)
treats malformed bundles as best-effort: an invalid `meta.json` or
missing `dist/index.html` is skipped + surfaced in the admin SPA, not
fatal to the daemon.

## What apps DON'T have (architectural distinctions)

Apps are not modules:

- No `paths` field in `services.json` — they don't claim hub paths
  directly. parachute-app mounts them under its own `/app/` claim.
- No `health` endpoint — the parent app daemon's health covers them.
- No MCP server — they consume vault's MCP via OAuth; if you need an
  app-specific MCP surface, you're building a backend module.
- No `/.parachute/info` endpoint — no module-protocol surface.
- No self-registration — parachute-app's `services.json` row absorbs
  the per-UI declarations.
- No port — apps don't bind anything; they're files on disk.

If you find yourself needing one of these, you're building a backend
module, not an app. Use [`module-surfaces.md`](./module-surfaces.md).

## The "easy to create" arc (forthcoming work)

These build on this pattern doc as the contract:

- **`parachute-app scaffold <name>`** — TBD; generates a starter app
  directory with `meta.json`, a build config, and vault-client wiring.
  Different framework templates (Vite+React default; vanilla HTML for
  the simplest case). Tracked at
  [parachute-app#scaffold-issue](https://github.com/ParachuteComputer/parachute-app/issues)
  (TBD).
- **`/create-parachute-app` Claude skill** — TBD; natural-language
  scaffolding. The operator describes a use case, the skill generates
  a working starter. Tracked at
  [parachute-app#claude-skill-issue](https://github.com/ParachuteComputer/parachute-app/issues)
  (TBD).
- **`parachute-app validate-bundle <path-or-tarball>`** — TBD; CLI
  that runs `parseMeta()` against a built bundle so CI can catch shape
  drift before publish.

## Related patterns

- [`module-surfaces.md`](./module-surfaces.md) — mirror pattern for
  backend modules. Apps consume what modules expose.
- [`mount-path-convention.md`](./mount-path-convention.md) — how an
  SPA at `/app/<name>/` configures its routing (`base` / `basename` /
  internal routes).
- [`canonical-ports.md`](./canonical-ports.md) — apps don't have
  ports; backend modules do. Reference for the other side.
- [`oauth-scopes.md`](./oauth-scopes.md) — scope-string shape that
  populates `scopes_required`.
- [`oauth-dcr-approval.md`](./oauth-dcr-approval.md) — how an app
  registers as an OAuth client at install time.
- [`bootstrap-on-first-boot.md`](./bootstrap-on-first-boot.md) — how
  parachute-app bootstraps default apps on a fresh install.
- [`dev-mode-sse-live-reload.md`](./dev-mode-sse-live-reload.md) —
  what `dev_watch_dir` / `dev_build_cmd` / `dev_debounce_ms` plug
  into.

## History

- **2026-05-21** —
  [parachute-app design doc §5](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-05-21-parachute-apps-design.md#5-per-ui-metadata-schema--metajson-draft-07)
  articulated the `meta.json` schema. App design landed with notes-ui
  earmarked as the first canonical app.
- **2026-05-22** — Notes-as-app migration completed. `notes-ui`
  became the first published app (`@openparachute/notes-ui`).
- **2026-05-23** — Aaron's bootstrap loop revealed missing `meta.json`
  in `notes-ui`'s npm tarball; PR #158 fixed it. This pattern doc
  landed to canonicalize the contract so future apps (and a future
  scaffolder) have a single source to point at. The Phase 2.0
  `required_schema`, Phase 3.0 `dev_*` knobs, PWA fields, and
  `public` are all live in `meta-schema.ts` as of this doc.
