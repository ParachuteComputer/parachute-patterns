# Bin names

## Convention

Every executable shipped by a Parachute package is named
`parachute-<subcommand>` on PATH.

The umbrella `parachute` command (from `@openparachute/cli`) discovers those
bins by PATH scan and dispatches to them:

```
parachute <sub> [args...]   →  execs `parachute-<sub>` with the remaining args
parachute                    →  lists discovered subcommands + descriptions
```

First match on PATH wins (same as shell lookup). This means `parachute vault
...` works as soon as `@openparachute/vault` is installed anywhere on PATH,
without the umbrella having to know about it at build time.

See: [parachute-hub/src/cli.ts](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/cli.ts).

## Current bins (state of the world, 2026-04-25)

| Package | Bin name | Status |
|---|---|---|
| `@openparachute/cli` | `parachute` | umbrella dispatcher |
| `@openparachute/vault` | `parachute-vault` | conformant (renamed in [vault #134](https://github.com/ParachuteComputer/parachute-vault/pull/134)) |
| `@openparachute/scribe` | `parachute-scribe` | conformant (renamed in [scribe #9](https://github.com/ParachuteComputer/parachute-scribe/pull/9)) |
| `@openparachute/notes` | *(no bin)* | frontend; served by `parachute-hub`'s `notes-serve` shim, no own bin |
| `@openparachute/agent` | `parachute-agent`, `parachute-agent-bridge` | conformant (renamed from `@openparachute/channel` / `parachute-channel`, `parachute-channel-bridge` 2026-06-17; secondary bin follows `parachute-<module>-<role>`) |
| `@openparachute/narrate` | `parachute-narrate` | planned; not yet published |
| `tailshare` | `tailshare` | not a Parachute-branded tool; no rename planned |

## Why

- **PATH discovery is the composition point.** The umbrella never hard-codes
  its subcommand list — install a new `parachute-<x>` bin anywhere on PATH
  and it appears. That only works if everyone shares the prefix.
- **Avoids collisions.** Short names like `scribe` and `narrate` collide with
  common system or third-party binaries. The prefix is boring and safe.
- **Discoverability.** Tab-completion on `parachute-` in any shell lists
  every Parachute bin installed locally.

## Rules

- Primary bin: `parachute-<module>`.
- Secondary bins (if a package ships more than one, e.g. a server + a UI):
  `parachute-<module>-<role>`. Example: `parachute-agent-ui`.
- No bare-word bins. A package that currently ships one is on the migration
  list (see `adoption/migration-notes.md`).
- The umbrella `parachute` bin is reserved for `@openparachute/cli`. Nothing
  else may claim it. The vault rename unblocks this.

## Open questions

- Do we want a `parachute doctor` subcommand (shipped in the umbrella) that
  lints PATH for bare-name or duplicate bins? Tracked informally until
  someone hits a real collision.
