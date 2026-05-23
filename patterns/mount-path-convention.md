# Mount-path convention

> **⚠️ Superseded for parachute-app hosted UIs (2026-05-23).**
> This doc describes the build-time-baked-mount pattern (Vite `base` +
> `import.meta.env.BASE_URL`) that the notes-daemon era used. For app
> bundles hosted under **parachute-app**, the canonical pattern is
> **runtime mount detection** via `@openparachute/app-client` reading
> host-injected metadata. See:
>
> - [`runtime-tenancy-contract.md`](./runtime-tenancy-contract.md) — what hosts inject
> - [`app-bundle-shape.md`](./app-bundle-shape.md#mount-agnosticism) — mount-agnosticism requirement
>
> This doc remains accurate for the deprecating notes-daemon path and
> as historical context. Don't follow its build-time-mount guidance for
> new apps under parachute-app — they need to work at any operator-
> chosen mount, which the old pattern can't support.

## Convention

Every Parachute frontend module is served at a **subpath** under the
ecosystem origin (today: `/notes/`). The mount path is set in **one
place** — Vite's `base` — and every consumer of it reads through
`import.meta.env.BASE_URL`. Internal routes are written as if the app
sat at the origin root; the framework strips the prefix on read and
prepends it on write.

This is what lets the hub at `1939` proxy multiple frontends side-by-side
under one origin, lets `parachute expose` produce one public URL, and
lets a frontend move to a different mount with a one-line change.

## Single source, three downstream consumers

The mount path is declared in `vite.config.ts` (`base: basePath`,
overrideable via `VITE_BASE_PATH`). Vite injects it into the bundle as
`import.meta.env.BASE_URL`. Three things read it:

1. **Vite `base`** — asset URLs, service-worker scope, anything Vite
   itself emits. Build-time concern.
2. **`BrowserRouter` basename** — strips the prefix from the URL before
   matching, prepends it on `<Link>` writes. Runtime concern.
3. **PWA manifest `id` / `scope` / `start_url`** — installed PWA must
   launch under the deployed mount, not at `/`.

```ts
// parachute-notes/vite.config.ts
const basePath = normalizeBase(process.env.VITE_BASE_PATH ?? "/notes");

export default defineConfig({
  base: basePath,                      // (1)
  plugins: [
    VitePWA({ manifest: buildPwaManifest(basePath), ... }),  // (3)
  ],
});

// parachute-notes/src/app/App.tsx
<BrowserRouter basename={import.meta.env.BASE_URL.replace(/\/$/, "") || undefined}>
  <Routes>
    <Route path="/" element={<NotesIndex />} />
    <Route path="/n/:id" element={<NoteView />} />
    {/* ...mount-relative paths only — no `/notes/` prefix */}
  </Routes>
</BrowserRouter>
```

## Internal routes are mount-relative

This is the load-bearing simplification, established in
[`parachute-notes#50`](https://github.com/ParachuteComputer/parachute-notes/pull/50).
Routes inside the app drop the mount prefix:

```ts
<Route path="/n/:id" element={<NoteView />} />          // not "/notes/n/:id"
<Route path="/oauth/callback" element={<OAuthCallback />} />
```

Reasoning: `BrowserRouter`'s `basename` already strips and prepends the
prefix at the URL boundary. Putting `/notes/` inside the `path` props
double-stacks the prefix and forces a route-by-route search-and-replace
every time the mount moves. With mount-relative routes, **moving from
`/notes/` to `/foo/` is a single env-var change.**

The base-path test in `parachute-notes/src/base-url.test.ts` pins the
production default to catch unintentional drift.

## OAuth callback paths use `BASE_URL`

OAuth redirect URIs are constructed against the deployed mount, not the
origin root. The auth server registers `${origin}/notes/oauth/callback`
and bounces the browser back to that exact URL.

```ts
// parachute-notes/src/lib/vault/oauth.ts
function basePathPrefix(): string {
  const b = import.meta.env.BASE_URL ?? "/";
  return b.replace(/\/$/, "");
}

export function redirectUriForOrigin(origin = window.location.origin): string {
  return `${origin.replace(/\/$/, "")}${basePathPrefix()}/oauth/callback`;
}
```

If the redirect URI hardcoded `/oauth/callback`, a moved-or-aliased
mount would 404 the OAuth bounce. Reading `BASE_URL` keeps the redirect
URI in lockstep with the mount.

## PWA manifest mirrors the mount

```ts
// parachute-notes/src/pwa-manifest.ts
export function buildPwaManifest(base = "/"): Partial<ManifestOptions> {
  const normalized = base.endsWith("/") ? base : `${base}/`;
  return {
    id: normalized,
    start_url: normalized,
    scope: normalized,
    icons: [{ src: "pwa-192x192.png", ... }],  // bare (no leading "/")
    ...
  };
}
```

Two non-obvious calls baked in:

- **`scope` and `start_url` must end in `/`.** A scope of `/notes`
  (no trailing slash) does not match `/notes/`, breaking installed-PWA
  launch.
- **Manifest icon `src` values are bare** (`pwa-192x192.png`, not
  `/pwa-192x192.png`). They resolve relative to the manifest URL, which
  itself sits under the mount. Adding a leading slash strands them at
  the origin root and 404s the icon.

## The override knob

`VITE_BASE_PATH` env var, defaulting to the canonical mount path. Two
real uses:

- **`VITE_BASE_PATH=/`** — legacy stand-alone shape (dev-server case
  where you want the app at the origin root, not under a hub mount).
- **Multi-instance deployments** — a fork serving Notes at `/foo/`
  alongside the canonical `/notes/`.

Defaulting in `vite.config.ts` means dev / build / `parachute start
notes` all agree without explicit env-var setting.

## Deep-link shim for pre-refactor bookmarks

When Notes moved from `/<id>` (origin-root era) to `/notes/n/<id>`
(mount-aware era), pre-refactor bookmarks would land at internal `/<id>`
after the prefix-strip and bounce to `/`. The fix: a shim route that
redirects internal `/:id` → canonical `/n/:id`. See
[`parachute-notes#54`](https://github.com/ParachuteComputer/parachute-notes/pull/54)
and the `NoteIdRedirect` component in `App.tsx`.

This is mount-specific scaffolding — only relevant when you change the
internal route shape after users already have bookmarks.

## Rules

- **Declare the mount once.** `vite.config.ts`'s `base` is the single
  source. Don't hardcode `/notes/` anywhere else; read
  `import.meta.env.BASE_URL`.
- **Internal routes are mount-relative.** `path="/foo"`, never
  `path="/notes/foo"`. The router's `basename` does the prefixing.
- **`scope` / `start_url` end in `/`.** Manifest icons stay bare. The
  test in `pwa-manifest.test.ts` covers this.
- **OAuth redirect URIs read `BASE_URL`.** Never hardcode the callback
  path.
- **The mount path is the route slug, not the package name.** `Notes`
  is `parachute-notes` the package, mounted at `/notes/`. Future
  modules: pick a short, stable slug; the package-name boundary is
  separate.
- **Pin the production default in a test.** `parachute-notes/src/base-url.test.ts`
  asserts `BASE_URL === "/notes/"` so accidental drift in
  `vite.config.ts` or `vitest.config.ts` fails CI.

## Where this applies

- **`parachute-notes`** — reference implementation. Mount: `/notes/`.
  Refactor that established the pattern: PR
  [#49](https://github.com/ParachuteComputer/parachute-notes/pull/49)
  (move base to `/notes`) → PR
  [#50](https://github.com/ParachuteComputer/parachute-notes/pull/50)
  (drop `/notes/` from internal routes) → PR
  [#54](https://github.com/ParachuteComputer/parachute-notes/pull/54)
  (deep-link shim for legacy bookmarks). The full architecture writeup
  lives in
  [`parachute-notes/CLAUDE.md`](https://github.com/ParachuteComputer/parachute-notes/blob/main/CLAUDE.md)
  ("Mount-path architecture").
- **Future Parachute frontends (PWAs and SPAs)** — same shape. Pick a
  slug, set `base`, write mount-relative routes, mirror the manifest.
  The hub catalog (`/.well-known/parachute.json`, see
  [`module-protocol.md`](./module-protocol.md)) auto-renders any
  module that publishes a `services.json` entry with `paths`,
  `health`, and (optionally) `uiUrl`. The legacy `kind: "frontend"`
  field has been retired (hub#330); rendering is driven by capability
  fields, not type labels.
- **Third-party frontends** — same contract. There's nothing
  Parachute-specific in the convention; it's standard SPA-under-subpath
  hygiene that Parachute's hub-as-front-door composition pins.

## What this isn't

- **A backend mount convention.** API services already get a mount via
  the multi-tenant path shape (`/vault/<name>/`); that's a different
  pattern (see [`module-protocol.md`](./module-protocol.md)). This file
  is specifically about frontend bundles and the three Vite + Router +
  PWA places that have to agree.
- **A routing-library opinion.** The convention is "internal routes are
  mount-relative"; whether you use React Router, TanStack Router, or
  vanilla `URL` math is up to the module. The Notes reference happens to
  use React Router v7.

## Open questions

- **Server-rendered frontends.** Today every Parachute frontend is a
  client-rendered SPA with a single Vite bundle. If a future module
  ships SSR (Next, Remix, Astro), the "Vite `base` is the single source"
  shape needs a parallel: SSR frameworks have their own `basePath` /
  `app.basePath` knob that has to read the same env var.
- **Cross-frontend deep links.** Today each frontend handles its own
  routes; there's no convention for `notes-app` linking to a path inside
  `lens-app` other than full-URL construction. If/when that becomes a
  pattern, this doc grows a section.
