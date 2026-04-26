# Optimistic concurrency

## Convention

Every Parachute write API requires the caller to present the
**last-seen `updated_at` timestamp** of the resource it's modifying.
The server compares it against the live row and refuses the write if
they differ. The caller can opt out explicitly with `force: true` —
the only way to clobber, never the default.

This protects against the lost-update race that's the default failure
mode when N agents (or N tabs, or one agent + a sync worker) write to
the same note concurrently.

## Shape

### Request

```jsonc
{
  "content": "...",
  "if_updated_at": "2026-04-21T17:33:08.412Z",  // required by default
  "force": true                                   // explicit opt-out (overrides if_updated_at)
}
```

### Responses

**409 Conflict** — caller's `if_updated_at` doesn't match the live row.

```jsonc
{
  "error_type": "conflict",
  "current_updated_at": "2026-04-21T17:35:11.207Z",
  "your_updated_at":    "2026-04-21T17:33:08.412Z",
  "path":   "projects/launch.md",
  "note_id": "01J9Z2K3...",
  "message": "..."
}
```

**428 Precondition Required** (RFC 6585) — caller sent neither
`if_updated_at` nor `force: true`.

```jsonc
{
  "error_type": "precondition_required",
  "note_id": "01J9Z2K3...",
  "path":   "projects/launch.md",
  "message": "update requires `if_updated_at` (the note's last-seen updated_at) or `force: true`."
}
```

The two status codes are deliberately differentiated — `428` is
"you didn't try", `409` is "you tried and lost the race". An agent
should react differently to each.

### Reads always return `updated_at`

Every single-resource response includes `updated_at`, falling back to
`created_at` if the resource has never been updated. `create-note`
returns `updated_at` on the freshly-created note so the next write
already has a token. There is no path through the API where a caller
could end up holding a resource without a precondition value.

Canonical implementation:
[`parachute-vault/src/routes.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/routes.ts)
(write handlers, lines ~418–525) +
[`parachute-vault/src/mcp-http.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/mcp-http.ts)
(MCP tool surface — identical structured-error shape). Landed in
[`parachute-vault#153`](https://github.com/ParachuteComputer/parachute-vault/pull/153).

## Why

- **Agents are concurrent by default.** Two agents reading the same
  note, both updating, both succeeding silently is the most common
  silent-data-loss bug in agent stacks. Optimistic concurrency makes
  the conflict visible at the API boundary.
- **428 ≠ 409.** Distinguishing "no precondition supplied" from
  "precondition supplied but stale" lets clients/agents differentiate
  *bug-in-my-code* from *raced-with-someone-else*. A blanket 400
  collapses signal that the caller needs to recover.
- **Same shape on HTTP and MCP.** Whether an agent calls
  `update-note` over MCP or `PUT /api/notes/:id` over HTTP, the error
  body keys are identical (`error_type`, `current_updated_at`,
  `your_updated_at`, `path`, `note_id`). One recovery path.
- **`force: true` is loud.** Making the override an explicit boolean
  rather than absence of a header means clobbers show up in audit
  logs as deliberate decisions, not accidents.

## Rules

- **Default is required, not optional.** Writes without
  `if_updated_at` AND without `force: true` get a 428. Don't soft-fail
  to a write.
- **`force: true` overrides any `if_updated_at`.** Don't try to honour
  both — the explicit clobber wins. Documenting one rule keeps client
  logic simple.
- **Atomic check + write.** The precondition check must run inside the
  same transaction as the update, not as a separate `SELECT` →
  application-layer compare → `UPDATE`. Otherwise the race window
  reopens.
- **Never auto-resolve.** The server doesn't merge, doesn't pick a
  side, doesn't retry. The 409 is a signal back to the caller; the
  caller decides whether to re-fetch + re-apply or `force: true`.
- **Conflict body uses the structured field names.** `current_updated_at`,
  `your_updated_at`, `path`, `note_id`, `error_type: "conflict"`.
  Don't invent module-specific aliases. Legacy fields
  (`expected_updated_at`) may exist for back-compat shims; keep them
  alongside the new shape, drop on the next major.
- **Single-resource reads always include `updated_at`.** If the
  resource has never been updated, fall back to `created_at`. A read
  that doesn't return a precondition token is a bug.
- **Apply to *every* write.** Update, partial-update, link mutations,
  tag mutations on a note — anything that changes a resource's
  `updated_at`. Bulk operations either all-or-nothing the precondition
  per-resource, or document a different (`force: true`-equivalent)
  contract on the bulk endpoint.

## Where this applies

- **`parachute-vault`** — reference implementation. HTTP write handlers
  (`routes.ts`) and MCP `update-note` tool (`mcp-http.ts`) both
  enforce. PR #153.
- **`parachute-notes`** — relies on this contract for collaborative
  edits (browser tab + agent edits to the same note). Must not strip
  the precondition before forwarding writes from the PWA.
- **Future API-surface modules** — when a module exposes mutating
  HTTP/MCP endpoints over a database-backed resource, follow the same
  shape. Cheap to implement, prevents an entire class of silent
  corruption.

## Non-applicability

- **Append-only / event-log surfaces.** Anything where the operation
  is "add a row" rather than "modify a row" doesn't need the
  precondition — there's no row to clobber. Conflict semantics may
  still apply at the *uniqueness* level (e.g. a duplicate-path
  rejection on create), but that's a different shape (typically 409
  with `error_type: "duplicate"`).
- **Idempotent overwrites under a caller-supplied key.** Patterns like
  `PUT /by-key/:idempotency-key { value }` where the caller's key
  *is* the precondition.

## Open questions

- **Bulk operation semantics.** A bulk update across N notes today
  would require N preconditions. Reasonable, but verbose. A future
  bulk endpoint may want a single `if_unchanged_since: <ISO>` against
  the whole working set; not yet designed.
- **Cross-resource transactions.** Updating a note + a tag + a link in
  one call (today: separate operations, separate preconditions). If
  this becomes common, a transactional wrapper that takes a vector of
  preconditions could land. Premature today.
