# Canonical ports

## Convention

Every Parachute ecosystem service that runs locally claims a slot in the
**`1939–1949`** loopback range. Third-party integrators are expected to
stay out of it.

The single source of truth is the `PORT_RESERVATIONS` table in
[`parachute-hub/src/service-spec.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/service-spec.ts).
This pattern doc tracks the same shape for cross-reference; if the two
ever disagree, the code wins and this doc is wrong.

The CLI is the **active authority** on which port a given install lands
on — it consults this table at install time, picks the canonical slot
(or walks the unassigned reservations on collision), and writes the
chosen port into the service's `.env`. See
[`cli-as-port-authority.md`](./cli-as-port-authority.md) for the
assignment algorithm, idempotency rules, and the service-side contract
this doc's reservations get enforced through.

## Reservations (state of the world, 2026-04-25)

| Port | Service | Tier | Status | Notes |
|---|---|---|---|---|
| 1939 | `parachute-hub` | committed core | assigned | CLI-managed; static + reverse-proxy front door, fronts every service for `parachute expose`. |
| 1940 | `parachute-vault` | committed core | assigned | REST + MCP at `/vault/<name>/`. |
| 1942 | `parachute-notes` | committed core | assigned | Static server over the PWA bundle. |
| 1943 | `parachute-scribe` | committed core | assigned | Whisper-compatible transcription API at root. |
| 1941 | `parachute-channel` | working module | assigned | Daemon. Exploratory; may retire — not part of the committed ecosystem. |
| 1944 | unassigned | — | reserved | |
| 1945 | unassigned | — | reserved | |
| 1946 | unassigned | — | reserved | |
| 1947 | unassigned | — | reserved | |
| 1948 | unassigned | — | reserved | |
| 1949 | unassigned | — | reserved | |

The **committed core** is the set of modules the Parachute ecosystem
commits to maintaining: hub, vault, notes, scribe, agent. Agent is
also committed-core but doesn't reserve a port in this range — it
ships its own `services.json` entry via `module.json`. **Working
modules** like channel exist and run, but the ecosystem does not
commit to them as long-term first-party citizens.

## Why a fixed range

- **Hub composition.** `parachute expose` (Tailscale serve / funnel)
  plans proxy routes against fixed loopback ports. The hub fronts the
  whole range from `127.0.0.1:1939`; clients only ever see the hub's
  address. If service ports drifted, the proxy plan would have to be
  regenerated on every install.
- **Predictable curl.** Operators muscle-memory `curl
  http://127.0.0.1:1940/...` for vault, `1942/notes` for the PWA, etc.
  A fixed range makes troubleshooting durable across machines.
- **Collision warnings.** `parachute install` warns (but does not block)
  when a service tries to claim a port outside the range — forks and
  non-standard deployments sometimes land elsewhere intentionally.

## Hub pin (1939)

Hub specifically pins `1939`. `parachute expose` composes hub targets as
`http://127.0.0.1:1939/` and that URL has to be stable across machines for
`tailscale serve` to proxy it correctly. The hub-port fallback range is 1
slot wide — if something else is on `1939`, the CLI fails loudly rather
than walking up into a service's slot.

## Rules

- **New first-party modules claim a slot at the time they ship, not
  before.** No speculative reservations for roadmap modules — the table
  reflects what runs today, not what might run later. Open a PR against
  `parachute-hub/src/service-spec.ts` adding a `PortReservation` entry
  when the module actually ships, and add a row here in the same PR.
- **Don't reuse a port across instances.** Multi-tenant modules (e.g.
  multiple vaults) take *one* port and disambiguate via path — see
  [module-protocol.md](./module-protocol.md) on the `/vault/<name>`
  shape.
- **Don't pin to a port outside the range without a reason.** A service
  that *can* live in `1939–1949` *should*. The warning from `parachute
  install` exists to catch drift, not to encourage it.
- **The committed-core tier is a maintenance commitment, not a port
  commitment.** A service can be in the table without being committed
  core; the table is the port registry, the tier column is editorial.

## What this isn't

- **Public ports.** This range is loopback; nothing here speaks publicly.
  Public reachability is layered on by `parachute expose` (Tailscale
  serve / funnel / Cloudflare), which presents one public URL fronted by
  the hub.
- **A registry of running services.** That's `~/.parachute/services.json`
  — see [module-protocol.md](./module-protocol.md). The reservation
  table says what *should* be at a port; services.json says what *is*.
- **A roadmap.** Slots `1944–1949` are unassigned, not earmarked.
  Whichever module ships first into the range claims the next free slot.

## Open questions

- **Channel's status.** Currently allocated `1941` and runs in the
  ecosystem, but flagged for possible retirement. If channel retires,
  free `1941` and update this table.
- **Range exhaustion.** Eleven slots is cozy; we'll start to feel it
  around the seventh or eighth shipped service. The follow-up plan is
  `1950–1969` as a second range, but we don't need to commit until the
  pressure is real.
