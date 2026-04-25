# Canonical ports

## Convention

Every Parachute ecosystem service reserves a slot in the **`1939–1949`**
loopback range. Third-party integrators are expected to stay out of it.

The single source of truth is the `PORT_RESERVATIONS` table in
[`parachute-cli/src/service-spec.ts`](https://github.com/ParachuteComputer/parachute-cli/blob/main/src/service-spec.ts).
This pattern doc tracks the same shape for cross-reference; if the two
ever disagree, the code wins and this doc is wrong.

## Reservations (state of the world, 2026-04-25)

| Port | Service | Status | Notes |
|---|---|---|---|
| 1939 | `parachute-hub` | assigned | CLI-managed; static + reverse-proxy front door, fronts every service for `parachute expose`. |
| 1940 | `parachute-vault` | assigned | REST + MCP at `/vault/<name>/`. |
| 1941 | `parachute-channel` | assigned | Daemon. |
| 1942 | `parachute-notes` | assigned | Static server over the PWA bundle. |
| 1943 | `parachute-scribe` | assigned | Whisper-compatible transcription API at root. |
| 1944 | `pendant` | reserved | Wearable companion (future). |
| 1945 | `daily-v2` | reserved | Reflective journal app (future). |
| 1946 | unassigned | reserved | |
| 1947 | unassigned | reserved | |
| 1948 | unassigned | reserved | |
| 1949 | unassigned | reserved | |

## Why a fixed range

- **Hub composition.** `parachute expose` (Tailscale serve / funnel) plans
  proxy routes against fixed loopback ports. The hub fronts the whole
  range from `127.0.0.1:1939`; clients only ever see the hub's address.
  If service ports drifted, the proxy plan would have to be regenerated
  on every install.
- **Predictable curl.** Operators muscle-memory `curl
  http://127.0.0.1:1940/...` for vault, `1942/notes` for the PWA, etc.
  A fixed range makes troubleshooting durable across machines.
- **Collision warnings.** `parachute install` warns (but does not block)
  when a service tries to claim a port outside the range — forks and
  non-standard deployments sometimes land elsewhere intentionally.
- **Leaving headroom.** Slots `1944–1949` are reserved so the next four
  modules don't have to negotiate. New first-party module → claim the
  next free slot via PR to `parachute-cli/src/service-spec.ts` and add a
  row here.

## Hub pin (1939)

Hub specifically pins `1939`. `parachute expose` composes hub targets as
`http://127.0.0.1:1939/` and that URL has to be stable across machines for
`tailscale serve` to proxy it correctly. The hub-port fallback range is 1
slot wide — if something else is on `1939`, the CLI fails loudly rather
than walking up into a service's slot.

## Rules

- **Pick the next free slot in the range.** Open a PR against
  `parachute-cli/src/service-spec.ts` adding a `PortReservation` entry,
  and a row in this doc.
- **Don't reuse a port across instances.** Multi-tenant modules (e.g.
  multiple vaults) take *one* port and disambiguate via path — see
  [module-protocol.md](./module-protocol.md) on the `/vault/<name>`
  shape.
- **Don't pin to a port outside the range without a reason.** A service
  that *can* live in `1939–1949` *should*. The warning from `parachute
  install` exists to catch drift, not to encourage it.
- **Reserved slots are not free for first-come grabs.** `pendant` and
  `daily-v2` have soft reservations; pick `1946+` if you ship before
  they do.

## What this isn't

- **Public ports.** This range is loopback; nothing here speaks publicly.
  Public reachability is layered on by `parachute expose` (Tailscale
  serve / funnel / Cloudflare), which presents one public URL fronted by
  the hub.
- **A registry of running services.** That's `~/.parachute/services.json`
  — see [module-protocol.md](./module-protocol.md). The reservation
  table says what *should* be at a port; services.json says what *is*.

## Open questions

- **Ports `1944` (pendant) and `1945` (daily-v2)** are soft-reserved
  against modules that aren't shipped yet. Reclaim if neither lands by
  end of 2026.
- **Range exhaustion.** Eleven slots is cozy; we'll start to feel it
  around the seventh or eighth published service. The follow-up plan is
  `1950–1969` as a second range, but we don't need to commit until the
  pressure is real.
