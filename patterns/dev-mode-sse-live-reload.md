# Dev-mode SSE live-reload

> Hosted UIs in a supervisor module ship a dev mode that automatically
> reloads the browser when their source changes. The shape: a file
> watcher (or manual trigger) broadcasts a `reload` event over an SSE
> stream; an injected `<script>` in the served HTML listens via
> `EventSource` and calls `window.location.reload()`. Iteration cost
> for a UI under bun-link drops from "rebuild + manual reload + maybe
> service-worker dance" to "edit + tab refreshes itself."

## The principle

UIs hosted inside a supervisor module (apps host UIs; a hypothetical
runner could host job dashboards) don't get the dev affordances a
standalone Vite dev server gives them — they're served by the host as
static bundles. Without a deliberate dev mode the iteration loop is:

  edit → `bun run build` → switch to browser tab → reload → service
  worker cached the old bundle, hard-reload → still cached, devtools
  cache-disable + reload → finally see the new code.

Multiply by ten edits per minute during a polish session and the
friction dominates. The dev-mode pattern moves the loop to: edit →
tab refreshes itself.

## The architecture

Three thin layers, all per-UI (a UI can be in dev mode without others
being affected):

1. **Server side — SSE endpoint.** `GET /<mount>/<name>/_dev/reload`
   returns a `text/event-stream` response. Each connected browser is a
   subscriber held in an in-process `Map<name, Set<subscriber>>`.
   Disconnect handler reaps the entry. Unauthenticated (browser
   `EventSource` can't add `Authorization` headers; the affordance is
   meant for the dev path, not a production protected surface).

2. **Inject script — browser side.** When dev mode is on AND the
   response body is HTML for that UI, the host parses the HTML and
   injects a `<script id="parachute-app-dev-reload">` just before
   `</head>`. The script opens an `EventSource` against the relative
   endpoint, listens for `reload` events, and calls
   `window.location.reload()` (200ms grace to coalesce duplicate
   events). Idempotent: marker `id` is checked before injection so
   re-serves don't duplicate the tag.

3. **Trigger — file watcher OR manual.** Default trigger is a
   recursive `fs.watch` on the UI's source dir (debounced 250ms).
   Operators can also fire a manual broadcast via `POST
   /<mount>/<name>/dev/trigger` (the CLI's `--trigger` flag); useful
   when the source is on a remote filesystem the watcher can't see, or
   for testing the reload path itself.

## The flow

1. Operator runs `<module> dev <ui>` → POSTs to the host's
   `/dev/enable` route. In-memory state flips for that UI; file watcher
   starts on the UI's `dev_watch_dir`.
2. Source change → FSWatcher fires → debounced callback waits the
   quiet-window out (250ms default; floor 50ms).
3. (Optional) operator-declared `dev_build_cmd` runs via `Bun.spawn` —
   60s timeout, single-flight per UI (a fresh batch arriving during a
   build is coalesced into "re-run on completion").
4. Build success (exit 0) → `broadcastReload(name)` pushes an
   `event: reload\ndata: {"timestamp":...}\n\n` to every subscriber.
   Build failure → log stdout/stderr (truncated), no broadcast,
   watcher stays armed.
5. Each connected browser's `EventSource` dispatches; injected script
   calls `window.location.reload()`. The next request for the
   bundle is served fresh (dev mode also overrides cache headers, see
   below). New code visible.

Total wall-clock from "save" to "browser refreshed": debounce +
build-time + ~10ms broadcast + ~50ms reload + bundle reparse.
For a small UI with no build cmd, it's ~300ms end-to-end.

## Cache strategy interaction

A dev mode that fires reload events while service workers serve stale
bundles is worse than no dev mode at all. The host enforces a hard
override:

- **In dev mode:** every response from that UI's mount gets
  `Cache-Control: no-cache, no-store, must-revalidate`, overriding the
  production smart-cache headers (hashed assets get `immutable`,
  unhashed get `max-age=3600`). HTML especially: the browser must
  re-fetch the document for the inject script to find a fresh
  `EventSource` endpoint.
- **PWA service workers:** UIs that ship a service worker get the same
  no-cache treatment on the SW file itself, but ultimately the UI
  owns its SW lifecycle. Best-practice for UIs that want clean dev:
  detect dev mode (e.g. presence of the inject script) and call
  `registration.unregister()` to drop the SW entirely while iterating.
  (parachute-notes#151 tracks Notes adopting this pattern.)
- **On `dev disable`:** cache headers revert to the production shape;
  SSE subscribers are closed; the browser's next request fetches via
  the production cache plan. No daemon restart needed.

## Reference implementation

In [`parachute-app`](https://github.com/ParachuteComputer/parachute-app):

- [`dev-mode.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/dev-mode.ts)
  — per-UI state (`Map<name, DevModeState>` + `Map<name,
  Set<subscriber>>`). `enableDevMode` / `disableDevMode` /
  `broadcastReload` / `addSubscriber` / `removeSubscriber`.
- [`dev-watcher.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/dev-watcher.ts)
  — `fs.watch(..., { recursive: true })` per UI; debounce + ignore
  `dist/` + `node_modules/` + `.git/`; optional build via `Bun.spawn`
  with `AbortController` timeout; single-flight + rerun-pending guard.
- [`dev-injection.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/dev-injection.ts)
  — regex-based HTML insertion before `</head>` (fallbacks: before
  first `<script>`, after `<body>`, append). Idempotent via
  `id="parachute-app-dev-reload"` marker check. Deliberately NOT
  cheerio — a 500KB HTML-parser dep for one insertion is wrong-shaped.
- [`dev-routes.ts`](https://github.com/ParachuteComputer/parachute-app/blob/main/packages/app-host/src/dev-routes.ts)
  — `GET /_dev/reload` SSE; `POST /dev/enable`, `/dev/disable`,
  `/dev/trigger`; `GET /dev/list`, `GET /dev`.

## Configuration

Per-UI knobs live in the UI's manifest (apps reads them from
`meta.json`):

- **`dev_watch_dir: string`** — source dir to watch, relative to UI
  root. Validated as relative (no absolute-path escape). Defaults to
  the UI root itself (filter handles `dist/` + `node_modules/`).
- **`dev_build_cmd: string`** — optional shell command run before
  broadcast (e.g. `"bun run build"`). cwd is UI root. Spawned via `sh
  -c`. Skipped when undefined.
- **`dev_debounce_ms: number`** — debounce window. Default `250`,
  floor `50` (clamped).

Per-module knobs in the module config:

- **`dev_mode_allowed: boolean`** — operator kill-switch. Default
  `true`. Setting `false` makes `/dev/enable` return `409
  dev_mode_disabled` — useful for production deployments where dev
  mode shouldn't be reachable even with admin scope.

## Failure modes

| Condition | Behavior |
| --- | --- |
| `dev_build_cmd` exits non-zero | Log truncated stdout + stderr; no reload broadcast; watcher stays armed; next edit retries. |
| `dev_build_cmd` hangs > 60s | `AbortController.abort()` kills the process; watcher continues. |
| Build-output-loop (build writes to `dist/`) | Watcher filter drops `dist/` + `node_modules/` + `.git/` paths before debounce; loop never starts. |
| FSWatcher error (rare; platform quirks) | Logged; watcher slot may fall back to non-recursive on the same dir; pattern degrades to "watches root only". |
| Recursive watch unsupported on platform | Logged warning; falls back to `fs.watch` without `recursive: true`. |
| SSE client disconnect | `cancel` hook fires; subscriber removed from set; no leak. |
| Build in flight when next batch lands | Single-flight guard; `rerunPending = true`; runs once current build settles. |
| `dev_mode_allowed: false` | `enable` returns `409 dev_mode_disabled`. |

## Security

- **SSE endpoint is unauthenticated.** Browser `EventSource` doesn't
  support custom headers; an OAuth-bearer flow on the dev stream
  would require a token-in-query-string shim. The endpoint reveals
  reload events for one named UI; the surface is small and the impact
  is "a third-party tab gets told to reload, which it has no reason
  to listen for." For deployments where this is unacceptable, the
  `dev_mode_allowed: false` config disables the whole subsystem.
- **`dev_build_cmd` is shell-spawned.** That's operator-authored
  config under the operator's own UID — same trust level as the
  `startCmd` in the module's `.parachute/module.json`. Not user
  input, not callable from a third party.
- **`dev_watch_dir` is validated relative.** An absolute path in
  the manifest would let a malformed UI ask the host to watch
  `/Users/<op>/.ssh/`. Schema rejects absolute paths at meta-load.
- **CORS / cross-origin:** SSE stream uses standard CORS, not
  credentialed — a third-party origin can connect (and observe a
  noisy "the operator reloaded their dev tab" signal), but can't
  trigger a reload (no auth means no `/dev/trigger`).

## Cross-references

- Shipped in
  [parachute-app#3](https://github.com/ParachuteComputer/parachute-app/pull/3)
  (Phase 1.3 — dev mode + SSE + inject) and
  [parachute-app#8](https://github.com/ParachuteComputer/parachute-app/pull/8)
  (Phase 3.0 — file watcher + auto-rebuild) on 2026-05-22.
- Closes the iteration friction tracked in
  [parachute-notes#151](https://github.com/ParachuteComputer/parachute-notes/issues/151)
  ("dev mode: trigger SW unregister on rebuild so bun-link source
  edits propagate") — the SW-unregister piece still belongs to Notes,
  but the broadcast-on-rebuild affordance the issue was working
  around now ships at the platform level.
- See [`module-self-registration.md`](./module-self-registration.md) —
  dev-mode state is process-local + ephemeral by design; it doesn't
  ride along in services.json. A daemon restart returns every UI to
  production cache headers.
