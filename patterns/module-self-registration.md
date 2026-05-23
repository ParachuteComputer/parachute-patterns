# Module self-registration

> Every Parachute module owns its own row in
> `~/.parachute/services.json`. On `serve` startup it reads its own
> `.parachute/module.json`, computes its `installDir`, and atomically
> upserts the row. Hub reads the file as the canonical source of truth.

## The principle

Hub-as-supervisor (v0.6) reads `~/.parachute/services.json` to know which
modules exist on the host. A module that doesn't self-register is
invisible to `parachute status`, `parachute restart`, the admin SPA
module catalog, and the live `/.well-known/parachute.json` builder.

**The module is the authority on its own row.** Hub's vendored
`FIRST_PARTY_FALLBACKS` table in
[`parachute-hub/src/service-spec.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/service-spec.ts)
is a transitional shim — one entry per module that hasn't yet shipped
its own `.parachute/module.json` or self-register path. The endgame is
every committed-core module self-registers reliably and the fallback
table retires (tracked at
[parachute-hub#301](https://github.com/ParachuteComputer/parachute-hub/issues/301)).

## The contract

A self-registering module:

1. **Ships `.parachute/module.json`** with the required fields (see
   [`module-json-extensibility.md`](./module-json-extensibility.md)):
   `name`, `manifestName`, `displayName`, `tagline`, `port`,
   `paths`, `health`, `startCmd`, `scopes`.
2. **Exposes a `selfRegister(opts) → result` function** that reads the
   manifest, atomically upserts the services.json row, and returns
   structured success/failure (never throws).
3. **Calls it from `serve` startup AFTER the HTTP server starts
   listening**, fire-and-forget. Best-effort: failures log + the daemon
   continues serving.

## The reference shape

Canonical types — runner's version is the cleanest reference:

```ts
// parachute-runner/src/self-register.ts
export type SelfRegisterOpts = {
  /** The port we just bound — first-run fallback only. */
  boundPort: number;
  /** Absolute path to the package root (where `.parachute/` + `package.json` live). */
  installDir: string;
  /** Override services.json location (tests). */
  manifestPath?: string;
  /** Logger override; default console. */
  logger?: Pick<Console, "log" | "warn" | "error">;
};

export type SelfRegisterResult = {
  ok: boolean;
  manifestPath: string;
  hadExistingEntry: boolean;
  portWritten: number;
  /** Set when ok=false — the error swallowed by the caller. */
  error?: Error;
};
```

And the services.json helpers (mirror these per module — same shape
across vault, scribe, runner, agent):

```ts
// parachute-runner/src/services-manifest.ts
export function resolveManifestPath(
  env: Record<string, string | undefined> = process.env,
): string {
  const base = env.PARACHUTE_HOME ?? join(env.HOME ?? os.homedir(), ".parachute");
  return join(base, "services.json");
}

export function readServiceEntry(name: string, path = resolveManifestPath()): ServiceEntry | undefined;

export function upsertService(entry: ServiceEntry, path = resolveManifestPath()): void {
  // Merge into existing row (preserves hub-stamped fields). Atomic write:
  // stage to `<path>.tmp-<pid>-<now>`, rename over target.
}
```

Three load-bearing details:

- **`upsertService` merges, doesn't replace** — `entry` spreads last so
  the module wins on its own fields; hub-stamped fields the module
  doesn't author (`installDir`, future `uiUrl` / `managementUrl`) ride
  through.
- **Atomic write** — stage to a per-pid tmp file, then rename. A crash
  mid-write leaves the prior file intact rather than corrupting it.
- **`PARACHUTE_HOME` is resolved per-call** — honored at runtime so
  Docker / sandbox / test setups can redirect without import-boundary
  flakiness.

## What gets preserved across re-registrations

| Field | Authority | Behavior |
| --- | --- | --- |
| `port` | Operator (or hub) at install time | If a row exists with a `port`, the module **preserves** it on subsequent boots. First-boot writes the bound port. |
| `installDir` | The module on boot | Module **re-stamps** `installDir` from its own package root so a `git pull` that moves the checkout is reflected. Hub-stamped value from `parachute install` is overwritten by the module's own resolution (they should agree). |
| `paths` / `health` / `displayName` / `tagline` / `stripPrefix` / `version` | Module's `.parachute/module.json` + `package.json` | Re-stamped every boot from the manifest. |
| Hub-stamped extras (`uiUrl`, `managementUrl`, future fields) | Hub at install/upgrade time | Preserved via the merge in `upsertService`. |
| Other modules' rows | Other modules | Never touched. The upsert keys on `name`. |

Port-preservation matters: an operator who set `scribe.port = 1947` in
services.json (or hub picked it during port-collision resolution) stays
at 1947 across restarts. Scribe pinned this in `scribe#40` /
`paraclaw#145` — earlier scribe versions silently overwrote the
operator's port with the env-derived default on every boot.

## Failure modes (graceful)

Every read or write boundary returns `{ok: false, error}` rather than
throwing. The caller logs a single `[<module>] skipped self-register:
<reason>` line and continues:

- **`PARACHUTE_HOME` unset and `$HOME` unresolvable** → skip, log.
- **`.parachute/module.json` absent** → skip, log ("legacy install or
  dev tree").
- **`services.json` malformed** → skip, log. (The next operator-driven
  fix-up surfaces the error.)
- **`services.json` unwritable** (permissions, disk full, concurrent
  writer) → skip, log.

The running module is more valuable than the discoverability
bookkeeping. The visible symptom of failure is "module doesn't appear
on hub discovery / admin SPA"; the fix is to restart the module or run
`parachute install <name>` to re-stamp via the hub-side path.

## Trust boundary

Filesystem-direct writes mean the module process has write access to
hub's `~/.parachute/` directory. That's appropriate for the v0.6
owner-operated single-container deployment (see
[`trust-gradient-isolation.md`](./trust-gradient-isolation.md)) — hub
and module share a filesystem, share an operator, share a trust
gradient.

For v0.7 multi-container cloud, the seam is swappable: the
`selfRegister` function is the single call site that would change from
"write to filesystem" to "POST to `hub/api/modules/self-register`". The
caller — `serve` startup — doesn't know or care which transport ran.
Vault's `self-register.ts` docstring captures the forward-compatibility
explicitly.

## What about frontend modules (notes)?

Notes is a static bundle served by hub's `notes-serve.ts` shim, not a
daemon with a `serve` startup. The self-registration pattern doesn't
directly apply — notes is registered by whatever installs it (hub's
install flow + the `NOTES_FALLBACK` vendored manifest in
`service-spec.ts`). When notes ships its own `.parachute/module.json`
and hub's install path reads it, `NOTES_FALLBACK` retires the same way
the others do — but the call site for the row stamp lives in hub's
install command rather than in notes itself.

## Why filesystem-direct, not HTTP

HTTP would be a cleaner trust boundary — the module wouldn't need write
access to hub's home directory — but it costs:

- **Hub-side endpoint.** `POST /api/modules/self-register` with auth
  (the module needs the operator's bearer to register).
- **Bootstrap ordering.** If hub is supervising every module and the
  module self-registers via HTTP-to-hub, hub has to be up first; today
  modules can boot independently and hub picks them up on next read.
- **Auth complexity.** Modules don't currently hold an operator-bearer
  on cold-boot.

Filesystem-direct works in v0.6 single-container, where hub and modules
share both filesystem and operator. Defer HTTP to v0.7 when the trust
gradient genuinely steepens (cross-container, multi-tenant) and the
isolation cost is load-bearing rather than ceremonial.

## History

The pattern shipped across three modules on 2026-05-21:

- **vault#356** — first implementer; POC for retiring hub's
  `FIRST_PARTY_FALLBACKS[vault]`.
- **runner#3** — Phase 1.3, modeled on the agent + scribe shape (which
  predate the vault POC by a few weeks but weren't formalized as a
  pattern yet). (Note: parachute-runner is currently exploration-tier;
  cited as a faithful implementation of the same pattern as vault/scribe,
  not as a canonical committed-core module.)
- **scribe#50** — converged on the runner shape; module.json is now the
  single source of truth for paths/health/displayName/tagline.

Agent's `services-manifest.ts` (now deprecated alongside the module
itself, see `parachute-agent/DEPRECATED.md`) was the original
implementation that runner + scribe mirrored. The pattern's
"manifest-sourced metadata, not hardcoded in the call site" property is
the load-bearing piece that makes the FALLBACK retirement possible —
once all four committed-core modules self-register from their own
manifest, hub no longer needs vendored copies.

## Related patterns

- [`module-protocol.md`](./module-protocol.md) — the three contracts
  every module implements (storage / runtime / discovery).
  Self-registration is how a module gets its row into the storage
  layer.
- [`module-json-extensibility.md`](./module-json-extensibility.md) —
  the manifest shape self-registration reads from.
- [`trust-gradient-isolation.md`](./trust-gradient-isolation.md) —
  why filesystem-direct writes are appropriate for v0.6 owner-operated
  and the seam where v0.7 multi-tenant would swap to HTTP.
- [`canonical-ports.md`](./canonical-ports.md) — what the `port` field
  the module re-stamps is bounded by.
