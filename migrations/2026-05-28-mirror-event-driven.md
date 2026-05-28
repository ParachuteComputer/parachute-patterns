---
title: Mirror event-driven + sync_mode schema rename
date: 2026-05-28
status: active
originating-pr: parachute-vault#382 (`feat(vault): event-driven mirror exports + deletion handling + sync_mode UX`)
---

# Mirror event-driven + sync_mode schema rename

Vault's git-mirror feature flipped from polling-based to event-driven (vault#382), and the config schema was reframed at the same time:

| Old field | New field | Migration |
|---|---|---|
| `watch: true` | `sync_mode: "events"` | back-compat parse: `watch: true` reads as events mode |
| `watch: false` | `sync_mode: "manual"` | back-compat parse: false reads as manual |
| `interval_seconds: N` | `safety_net_seconds: N` | renamed; default flipped from 5s to 3600s (1h) |

The architectural shift in one line: **mirror manager now subscribes to `HookRegistry` events** ("created" / "updated" / "deleted" on notes/tags/attachments) and runs an export within ~500ms of each mutation. Polling demotes to a safety-net cadence (default 1 hour) that catches anything missed by the event path (direct SQL writes, server restart races, etc.).

Reference: design doc [`parachute.computer/design/2026-05-20-vault-as-git-projection.md`](../../parachute.computer/design/2026-05-20-vault-as-git-projection.md) — this is the v0.8 evolution from the v0.7-bootstrap polling primitive shipped in vault#346.

## Why this propagation file exists

The reviewer on vault#382 flagged that the schema rename qualifies as a workspace-policy "architectural shift" — operators have a stored mental model ("the watch loop polls every interval_seconds") that no longer matches reality. The fields silently migrate on read, so no operator action is required, but downstream surfaces that quote the old schema (UPGRADING.md, design docs, future operator guides) need updating.

## Code references

Per-repo checklist for surfaces that mention or quote the mirror config schema.

### parachute-vault (the originating repo)

- [x] `src/mirror-config.ts` — schema renamed; back-compat parse + serialize. ([vault#382](https://github.com/ParachuteComputer/parachute-vault/pull/382))
- [x] `src/mirror-manager.ts` — event subscriptions + debounce + safety-net poll. ([vault#382](https://github.com/ParachuteComputer/parachute-vault/pull/382))
- [x] `core/src/hooks.ts` — `"deleted"` events added for notes/tags/attachments. ([vault#382](https://github.com/ParachuteComputer/parachute-vault/pull/382))
- [x] `core/src/portable-md.ts` — `pruneOrphans` for deletion propagation; `realpathSync` path-traversal guard. ([vault#382](https://github.com/ParachuteComputer/parachute-vault/pull/382))
- [x] `web/ui/src/routes/VaultMirror.tsx` — SPA picker collapsed to "On change" / "Manual only". ([vault#382](https://github.com/ParachuteComputer/parachute-vault/pull/382))
- [ ] `UPGRADING.md` — operator-facing note about the silent schema migration + the safety-net cadence change.

### parachute.computer (operator-facing site)

- [ ] `design/2026-05-20-vault-as-git-projection.md` — annotate the doc with a "Status: shipped as of 2026-05-28 via vault#382" header. The doc anticipated this shift; update to confirm.
- [ ] Future operator guide / FAQ — when written (task #163), use the new vocabulary throughout. Don't reference `interval_seconds` or `watch` except in a "Legacy fields" section.

### parachute-patterns (this repo)

- [x] `migrations/README.md` — entry for this file. (File presence in `migrations/` is the index; no manual README edit needed.)
- [ ] `patterns/design-system.md` — no change expected; mirror UI uses canonical tokens already (Workstream J).

## Operator-facing references

- [ ] **UPGRADING.md** in vault: short paragraph naming the schema rename + the back-compat. Most operators won't notice; those who hand-edited `config.yaml` for the watch interval will see their value preserved but the picker will round to "On change" mode regardless.
- [ ] Beta announcement: if a beta email goes out for the 0.4.9 stable release, mention the schema rename + the friendly default ("auto-syncs on every change now, no need to configure a cadence").

## External references

None outside the workspace today. The mirror feature is pre-1.0 and no third-party docs reference its config schema yet.

## What "complete" looks like

When the UPGRADING.md paragraph lands + the design-doc status header is updated, mark this migration `status: complete`. Status `active` while the operator-facing docs are still pending.

## Cross-references

- [`parachute-patterns/patterns/runtime-tenancy-contract.md`](../patterns/runtime-tenancy-contract.md) — not affected; mirror config is server-side, not a tenant→host contract.
- [`parachute-patterns/scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — no new grep added (no cross-repo string drift in operator-facing docs today).
