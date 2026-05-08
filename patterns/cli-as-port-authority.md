# CLI as port authority

## Convention

`parachute-hub` is the **port authority** for the Parachute ecosystem. At
install time the CLI picks a port for each service, persists it as
`PORT=<port>` in `~/.parachute/<svc>/.env`, and reflects the chosen port in
`~/.parachute/services.json`. Services read `PORT` from env on boot with a
compiled-in fallback (e.g. vault → 1940), so a stand-alone `bun run` still
works — but the CLI's value wins on installs the CLI manages.

The authoritative implementation is
[`parachute-hub/src/port-assign.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/port-assign.ts).
The install hook lives in
[`parachute-hub/src/commands/install.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/commands/install.ts).
This pattern doc captures the why and the rules; if the two ever disagree,
the code wins and this doc is wrong.

Pairs with [`canonical-ports.md`](./canonical-ports.md): canonical-ports
defines *which* ports belong to Parachute; this doc defines *who decides*
who gets which one.

## Why up-front assignment

The previous shape was detect-on-collision-at-boot: each service tried its
canonical port, fell back if the bind failed. That broke in three ways:

- **Opaque "address in use" errors.** Two services racing the same port
  produce a bind error deep inside one of them, with no shared picture of
  who owns what.
- **Hub proxy 502s.** The hub's reverse-proxy targets are computed from
  `services.json`. If a service silently fell back to a different port at
  runtime, the hub kept proxying to a dead port and the user saw a 502 with
  no explanation.
- **Race-y first install.** Two services starting in parallel could both
  decide the canonical slot was free and both try to bind it.

Up-front assignment makes the CLI the single coherent picture: the .env
written at install time is the contract for the next boot, and
`services.json` is kept in sync as the side effect.

## Algorithm

`assignPort(canonical, occupied)` is the pure helper:

1. **Prefer canonical.** If the service has a canonical slot
   (vault → 1940, etc.) and it's free, use it.
2. **Walk the unassigned reservations.** On collision (or when the service
   has no canonical slot — third-party modules), iterate
   `PORT_RESERVATIONS` where `status === "reserved"` and pick the first
   free one. Today that's `1944..1949`.
3. **Fall outside the range.** If the entire reserved set is full, walk
   past `CANONICAL_PORT_MAX` (1949) until a free port is found, and
   surface a warning. The install still proceeds — the warning tells the
   operator the install landed outside the curated range.

`assignServicePort(opts)` wraps the helper with .env round-trip:

- Reads `~/.parachute/<svc>/.env`. If `PORT` is already set to a valid
  numeric value (regex: `^[1-9]\d{0,4}$`, range-checked < 65536),
  **preserves it** and returns `source: "preserved"` without writing.
- Otherwise calls `assignPort`, upserts `PORT=<n>` into the file
  (preserving surrounding lines via
  [`env-file.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/env-file.ts)),
  and returns the chosen port plus the assignment source.

The `occupied` set is built by `collectOccupiedPorts` in `install.ts`:
union of (a) every `port` already in `services.json` for *other* services,
and (b) any port in the [`1939–1949`](./canonical-ports.md) range that
responds to a 150ms TCP probe at
`127.0.0.1:<port>`. The probe is fail-open — timeouts and errors return
`false` so a flaky probe never blocks an install.

## Idempotency

The contract is: **re-installing a service must not change its port unless
you ask it to.**

- Existing `PORT=` in `.env` wins. A user who edited their port keeps it
  across upgrades.
- A service whose `.env` has no `PORT` gets one written; subsequent
  installs see it and preserve.
- The canonical-vs-collision path only runs on the first install (or after
  a manual `.env` edit that removed `PORT`).

To force a re-pick: delete the `PORT=` line from
`~/.parachute/<svc>/.env`, then re-run `parachute install <svc>`.

## Defensive manifest sync

`install.ts` keeps `services.json` consistent with the .env it just wrote:

- **No entry yet + spec has a `seedEntry`:** seed the entry, overriding
  the seed's port if the CLI assigned a different one.
- **Entry exists on a different port:** upsert with the assigned port.
  This catches the case where a service's own init wrote an entry at the
  canonical port before the CLI's collision logic redirected it elsewhere.
- **Read-back verify after every write.** A silent upsert failure (perms,
  external writer races) surfaces as a loud log line instead of a phantom
  "registered" claim. Surfaced by
  [parachute-hub#44](https://github.com/ParachuteComputer/parachute-hub/issues/44):
  notes silently missing from `services.json` on a fresh bun 1.2.x install.

## Service-side contract

Services don't have to change to participate. They keep doing what they
already do:

1. Read `PORT` from `process.env` on boot.
2. If absent, fall back to a compiled-in default (vault → 1940, notes →
   1942, scribe → 1943).
3. Bind and serve.

The CLI's `lifecycle.start` merges `~/.parachute/<svc>/.env` into the
spawn env before exec, so a CLI-managed boot sees the assigned `PORT`. A
direct `bun run` outside the CLI still works on the compiled-in fallback.

This means: **third-party modules need no integration with the port
authority to coexist.** Drop them in, point `parachute install` at them,
and they'll land on a free slot in the reserved range or a warned slot
outside it.

## Rules

- **The CLI is the authority on installed services.** A service that
  hard-codes a port without honoring `process.env.PORT` breaks the
  authority and will collide on contested machines. Always read env first,
  fall back compiled-in second.
- **Don't write `PORT` from inside a service's own init.** The CLI writes
  it during install. A service init that also writes `PORT` creates two
  sources of truth and an idempotency hole.
- **Surface the warning when assignment falls outside the range.** Tools
  that wrap `parachute install` (TUIs, future installers) must echo the
  warning to the operator — silently landing on `1950+` defeats the
  point of the curated range.
- **Probe fail-open.** A failed TCP probe must not block install. Worst
  case the CLI assigns a port that something else is on; the bind fails at
  boot with a clear error and the operator re-runs install.

## Examples

- Helper:
  [`parachute-hub/src/port-assign.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/port-assign.ts).
- Install hook (port assignment + manifest sync):
  [`parachute-hub/src/commands/install.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/commands/install.ts).
- Test matrix:
  [`parachute-hub/src/__tests__/port-assign.test.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/__tests__/port-assign.test.ts).
- Originating PR:
  [parachute-hub#54](https://github.com/ParachuteComputer/parachute-hub/pull/54)
  (closes #53).

## Open questions

- **Re-pick UX.** Today the only way to force a re-pick is to hand-edit
  `.env`. A `parachute install --reassign-port <svc>` flag is plausible
  but unbuilt; defer until someone needs it.
- **Cross-machine sync.** Multi-machine setups (e.g. one workstation, one
  always-on box) currently pick ports independently. Not a problem yet —
  the hub fronts each machine separately — but worth flagging if cross-
  machine consistency becomes a goal.
