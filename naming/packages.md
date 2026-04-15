# Package names

## Convention

All publishable Parachute packages live under the `@openparachute` npm scope.

```
@openparachute/<module>
```

Examples:

- `@openparachute/vault` — parachute-vault
- `@openparachute/agent` — parachute-agents (singular on the package side)
- `@openparachute/cli` — the umbrella dispatcher
- `@openparachute/scribe`, `@openparachute/narrate` — when/if published

## Why

- One scope means one audit surface and one set of owners on npm.
- `openparachute` (not `parachute`) avoids collision with unrelated packages
  that were already squatting on bare `parachute-*` names, while keeping
  `parachute` available as a display word across the ecosystem.
- Singular package names (`agent`, not `agents`) match the import shape
  (`import { ... } from "@openparachute/agent"`). The repo can stay plural
  where that reads better — see `naming/repos.md`.

## Rules

- Package name: **singular**, lowercase, no hyphens inside the module slug.
- Scope: always `@openparachute`, never `@parachute`.
- Bin names exposed by a package follow `naming/bins.md`, not the package
  name. They are separate surfaces.
- A package that isn't yet published still picks its name up front and
  records it in `package.json` so cross-repo references don't churn.

## Open questions

- None currently.
