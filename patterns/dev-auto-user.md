# Dev-auto-user convenience

## [DRAFT] — convention is real, the naming isn't locked

## Convention

In local development, a Parachute service may auto-authenticate as a
synthetic "dev user" when (and only when):

1. The process detects it is running in a **local development** context, AND
2. An explicit environment variable opts in.

```
PARACHUTE_DEV_AUTO_USER=1
```

Without that env, the service refuses dev-auto-user even if other signals
(hostname, NODE_ENV) suggest dev. This is the gate.

## Why

- Removes friction when hacking on a vault / cloud / agent runner locally —
  no need to create a token on every fresh checkout.
- Gating on a *single explicit env var* (not `NODE_ENV=development`, not
  "localhost only") prevents the class of mistake where a misconfigured
  staging deploy silently disables auth.

## Rules

- **Env variable name: `PARACHUTE_DEV_AUTO_USER`.** Same name across every
  module. Never a per-module variant.
- **Off by default.** The default state of a fresh checkout must still
  require real auth. Opt in is a deliberate act.
- **Log loudly on boot.** When dev-auto-user is enabled, the server logs a
  visible banner: `⚠ PARACHUTE_DEV_AUTO_USER is enabled — do not use in
  production`.
- **Never bundle in production builds.** The code path should be reachable
  from the dev env only; prefer a guard + a unit test that asserts the
  banner appears in dev and does not appear in prod.
- **Synthetic user gets a fixed id.** `dev-user` or similar — so vault
  notes / logs produced during dev are easy to find and clear.

## Where this applies

- `parachute-vault` (single-tenant local dev)
- `parachute-cloud` (multi-tenant; dev-auto-user maps to a fixed dev tenant)
- Any future server that would otherwise require real auth to exercise
  locally.

## Open questions

- Do we want `PARACHUTE_DEV_AUTO_USER=<id>` (picks the synthetic user/tenant
  id) vs a boolean? Probably boolean + a separate `PARACHUTE_DEV_USER_ID`
  override. Not blocking.
