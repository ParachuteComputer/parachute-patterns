# Module JSON extensibility

> **Status: target convention, partial implementation.** The shape is
> declared in
> [`parachute.computer/design/2026-04-20-module-architecture.md`](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-04-20-module-architecture.md#extensibility-path)
> and committed to as the third-party path. The CLI's
> `parachute install` does not yet read `.parachute/module.json` —
> today it falls back to a hardcoded `SERVICE_SPECS` table in
> [`parachute-cli/src/service-spec.ts`](https://github.com/ParachuteComputer/parachute-cli/blob/main/src/service-spec.ts).
> That hardcoding is a **first-party shortcut, not an architectural
> limit**. This pattern doc nails the contract so third-party authors
> and the eventual CLI implementation agree on the shape.

## Convention

A Parachute module is identified by its **contracts**, not by its
package name. A third-party module declares itself by shipping a
`.parachute/module.json` file in the published npm package; the CLI
reads it on `parachute install <package>` and treats the package as
first-class. **No `@openparachute/` scope, no `parachute-*` prefix
required.**

The `module.json` is the canonical, machine-readable self-description.
Everything the CLI needs to install and run the module — and
everything the hub needs to render and route to it — lives in this
one file the author controls.

## Shape

```json
{
  "name": "my-service",
  "manifestName": "my-service",
  "displayName": "My Service",
  "tagline": "What the service does",
  "kind": "api",
  "port": 7001,
  "paths": ["/my-service"],
  "health": "/health",
  "startCmd": ["bin/my-service", "serve"],
  "scopes": { "defines": ["my-service:read", "my-service:write"] },
  "dependencies": {
    "vault": { "optional": true, "scopes": ["vault:read"] }
  }
}
```

| Field | Meaning |
| --- | --- |
| `name` | Stable, unique identifier across the ecosystem. Becomes the `services.json` key, the scope namespace, the `parachute start <name>` token. Must match `[a-z][a-z0-9-]*`. |
| `manifestName` | The name used in user-facing manifests (PWA / OAuth client name). Often equals `name`. |
| `displayName` | Human label rendered on the hub card. |
| `tagline` | One-line description rendered under `displayName`. |
| `kind` | One of `"api" \| "frontend" \| "tool"`. Hub picks card vs. iframe vs. launcher. |
| `port` | Default loopback port. Pick outside the reserved Parachute range (`1939–1949`) — see [`canonical-ports.md`](./canonical-ports.md). The CLI warns on collision but does not block. |
| `paths` | URL paths the module serves under the hub origin. |
| `health` | Path for liveness probes. |
| `startCmd` | Argv the CLI invokes for `parachute start <name>`. Resolved relative to the installed package. |
| `scopes.defines` | OAuth scopes the module owns. Namespaced by `name` so collisions don't happen — see [`oauth-scopes.md`](./oauth-scopes.md). |
| `dependencies` | Other modules this one wants to talk to. Each entry has `optional` and `scopes` fields; CLI uses these to auto-wire on install (env-var injection) — see [`service-to-service-auth.md`](./service-to-service-auth.md). |

## Why this shape

- **Author-controlled.** The package author declares everything in one
  file in their published artifact. No central registry, no PR against
  Parachute repos, no naming approval.
- **Caller-agnostic to the CLI.** First-party and third-party modules
  go through the same `module.json` path. The first-party
  `SERVICE_SPECS` table is a transitional shortcut.
- **Hub doesn't inspect names.** A `services.json` entry written from
  any `module.json` renders identically to first-party entries. The
  hub already treats any conformant entry as first-class — see
  [`module-protocol.md`](./module-protocol.md).
- **Scope namespace = module name.** No central registry of scope
  names. A `my-service` module owns `my-service:*`. Names are unique
  across the ecosystem because `services.json` keys are unique.
- **Composable with auto-wiring.** The `dependencies` block is what
  makes `parachute install <module>` able to mint a token (today: a
  shared secret; Phase B2: a JWT) and inject it into both ends —
  callee gets the validator material, caller gets the credential —
  without the user manually copying anything.

## How the CLI consumes it (target)

`parachute install <package>` will run:

1. `bun add -g <package>` — standard npm install. No naming constraint.
2. Read `<package>/.parachute/module.json` from the installed artifact.
3. Validate against the module-manifest schema. Reject malformed
   modules early.
4. Write a `services.json` entry using the declared `name`, `port`,
   `paths`, `health`, `displayName`, `tagline`, `kind`.
5. Register `startCmd` so `parachute start <name>` knows what to spawn.
6. For each `dependencies` entry, run `auto-wire` (mints credential,
   writes both ends, idempotent) — same machinery the vault↔scribe
   pair already uses. See
   [`service-to-service-auth.md`](./service-to-service-auth.md).

The first-party `SERVICE_SPECS` record stays as a fallback for
packages that pre-date the convention, then retires.

## Rules

- **`name` is the unique identifier.** Reuse of `name` across packages
  is a conflict — `services.json` keys must be unique. CLI fails the
  install if `name` collides with an existing entry.
- **`name` is the scope namespace.** A module declaring
  `defines: ["foo:read"]` must have `name: "foo"`. Otherwise a third
  party could squat scopes the user already trusts for a different
  module.
- **Port outside the reserved range when you can.** The Parachute
  range `1939–1949` is for first-party modules. Third-parties pick
  outside; the CLI warns but does not block.
- **`startCmd` must be argv, not a shell string.** Avoids
  shell-injection weirdness when users have spaces in package paths.
- **`module.json` is shipped in the npm artifact.** Not in
  `.gitignore`, not generated at install time. The CLI reads it
  post-install from the installed package directory.
- **Don't mutate the caller's `module.json` at install time.** If the
  CLI needs install-time state (assigned port, generated secret), it
  goes in `~/.parachute/<name>/.env` (see
  [`cli-as-port-authority.md`](./cli-as-port-authority.md)), not in
  the package's source.

## What this isn't

- **A package-naming convention.** First-party packages happen to use
  `parachute-*` (see [`naming/bins.md`](../naming/bins.md)) but the
  ecosystem doesn't require it. `module.json` is what makes a package
  a Parachute module.
- **A registry.** There is no central index of installed third-party
  modules. Discovery is per-machine via `~/.parachute/services.json`,
  exactly like first-party modules.
- **A trust mechanism.** `module.json` makes a package
  *Parachute-compatible*; it doesn't make it trusted. Users still
  decide what to install. The hub-as-OAuth-issuer architecture is
  what gates capability grants; see
  [`hub-as-issuer.md`](./hub-as-issuer.md).

## Where this applies

- **Today:** first-party modules (vault, notes, scribe, channel) are
  hardcoded in `parachute-cli/src/service-spec.ts`. The shape lives in
  `PORT_RESERVATIONS` + `SERVICE_SPECS` and is functionally a
  pre-`module.json` ancestor.
- **Tomorrow (target):** every module — first-party and third-party —
  ships its own `module.json`. The CLI reads it; the hardcoded
  `SERVICE_SPECS` table goes away or shrinks to a transitional
  fallback.
- **Reference for authors:** the design doc at
  [`parachute.computer/design/2026-04-20-module-architecture.md`](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-04-20-module-architecture.md)
  is the live shape until this pattern doc and the CLI implementation
  catch up.

## Open questions

- **Schema location.** Do we publish a JSON Schema for `module.json`
  (e.g. `https://parachute.computer/schemas/module.json/v1`)?
  Defer until the validator is being written — premature otherwise.
- **Versioning.** Today there's no `version` field on `module.json`
  itself (separate from the package's `version`). If/when the shape
  evolves breakingly, we'll need a `manifestVersion: 1` discriminator.
  Defer until a v2 shape is real.
- **Capabilities.** The richer `manifest` shape in the design doc has
  `capabilities`, `iconUrl`, `endpoints` etc. Today most of those
  duplicate what `/.parachute/info` already exposes at runtime.
  `module.json` is install-time; runtime metadata stays at
  `/.parachute/info` (see [`module-protocol.md`](./module-protocol.md)).
  The boundary is "what the CLI needs to install and route" lives in
  `module.json`; "what the hub fetches every render" stays at
  `/.parachute/info`.
