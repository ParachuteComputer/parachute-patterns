# Tag-scoped tokens

> One-line summary: a vault token can be narrowed to a specific set of root tags. The token only sees and writes notes that carry one of those tags (or a sub-tag of one of them).

## Convention

A vault token (`pvt_*`) optionally declares a **tag-allowlist** at mint time. Once set, the token's effective access is the intersection of:

1. **Scope** (existing) — `vault:<name>:read | write | admin` per `oauth-scopes.md`
2. **Tag allowlist** (new) — list of root tag names. Sub-tags inherit per the existing `_tags/<name>` hierarchy machinery (vault#214 / store-routing fix). The allowlist is **immutable** for the life of the token; editing the allowlist means minting a new token and revoking the old.

Pseudocode for the auth check:

```ts
function authCheck(token, note, action) {
  if (!hasScope(token, `vault:${vault}:${action}`)) return forbidden();
  if (token.tagAllowlist === null) return ok();           // unscoped — current behavior
  const noteTags = note.tags;                              // including hierarchy expansion
  if (noteTags.some(t => token.tagAllowlist.includes(rootOf(t)))) return ok();
  return forbidden();
}
```

Where `rootOf(t)` is `t.split('/')[0]` so `health/food` resolves to `health` for the allowlist check.

### Hierarchy match semantics

A token whose allowlist contains `health` matches:

- A note tagged `#health` (direct match)
- A note tagged ONLY with `#health/food` (hierarchy expansion via `tags.parent_names`)
- A note tagged ONLY with `#health/doctor` (same)
- A note tagged with `#health/food/breakfast` (recursive sub-tag)

The expansion uses vault's existing `getTagDescendants` machinery (same path that `query-notes` routes through post-#214 / #231). See §Storage details below for the full evaluation including the string-form fallback.

## Why

[From Aaron's notes 2026-04-27 + 2026-04-30]

> *"...scoped tokens that can only write within a schema... other agents such as little telegram bots just have permission to modify stuff within that; only working with the tags you give it access to."*

> *"If I make a tag called #health and then a sub-tag #health/food, then I could have a bot that is just scoped on all of my #health tags including any sub-tags."*

The use case: per-purpose paraclaw bots. A `#health` Claw, a `#work` Claw, a `#journal` Claw — each spawned from the same vault, but with isolated visibility into the slice of notes the operator has tagged for it. Currently isolation is per-vault (separate `default` / `boulder` / `techne` vaults); this lets you slice within one vault.

Schema-on-tag is a load-bearing concept in this design — see [`tag-data-model.md`](./tag-data-model.md) for the schema authoring shape. Each tag carries its own schema (description + indexed fields + typed relationships) directly on the `tags` row.

## How it composes

- **Read paths** — query-notes / GET /api/notes/:id / list-attachments filter results to only return notes with at least one allowlisted-root-tag (or sub-tag thereof).
- **Write paths** — POST /api/notes / PATCH require the new note to carry at least one allowlisted root-tag. POST without any matching tag returns `403 forbidden`.
- **Delete paths** — DELETE /api/notes/:id requires the existing note to be within scope. A token can't delete a note it can't read.
- **Tag operations** — list-tags returns only tags reachable from the allowlist (root tags + sub-tags). create-tag is allowed only if the new tag is a sub-tag of one of the allowlisted roots.
- **Schema operations** — the `update-tag` API (which writes to the `tags` row's schema columns: `description`, `fields`, `relationships`, `parent_names`) is gated by `vault:<name>:admin` + tag-in-allowlist. A tag-scoped admin CAN modify the schema for tags within their allowlist. Same gating applies to `update-note-schema` / `set-schema-mapping` for note-validation schemas.

## Composability with existing scopes

- `vault:<name>:read` + tag-allowlist `[health]` — token can READ notes tagged with `#health` or any `#health/*` sub-tag, nothing else.
- `vault:<name>:write` + tag-allowlist `[health]` — token can READ + WRITE within the `#health` slice. Cannot write notes outside `#health`.
- `vault:<name>:admin` + tag-allowlist `[health]` — admin ops (config, schema for `#health` and sub-tags) restricted to the `#health` slice.
- `vault:<name>:admin` + tag-allowlist `null` — current full-vault admin behavior.

## Mint authority

A tag-scoped admin **cannot** mint new tokens with broader allowlists. The mint endpoint enforces: *"a token's allowlist must be a subset of the minter's allowlist."* This prevents privilege escalation via mint:

- Admin with `[health]` minting a token with `[health, work]` → `403 forbidden` (broader)
- Admin with `[health, work]` minting a token with `[health]` → OK (subset)
- Admin with `[health]` minting a token with `[health]` → OK (equal)
- Admin with `[health]` minting a token with `[health/food]` → `400 bad request` (path-form values are rejected; only root-tag names allowed in the allowlist)
- Admin with `[health]` minting a token with `tags` field omitted → `403 forbidden` (would widen to unscoped)
- Admin with `null` (unscoped) minting any allowlist → OK (null is the universe)
- Admin with `null` minting with `tags` omitted → produces an unscoped token (back-compat)

## Token issuance

The `POST /vaults/<name>/tokens` endpoint (post-#220) gains an optional field:

```json
{
  "label": "health-bot",
  "scope": "vault:default:write",
  "tags": ["health", "wellness"],
  "expires_in": "30d"
}
```

When `tags` is omitted or `null`, the token is unscoped (current behavior). When present, the values must be existing root-tag names (no path separators).

The token mint UI (vault admin SPA, currently at `/admin/tokens` post-#220) gains a tag-picker step.

## Storage

Migration on the `tokens` table in vault DB:

```sql
ALTER TABLE tokens ADD COLUMN scoped_tags TEXT;  -- JSON-encoded array, NULL = unscoped
```

JSON-encoded so the column stays SQLite-portable. Validation at the API boundary (no schemaless mush).

## Why not extend the OAuth scope string

OAuth 2.0 §3.3 scope strings *could* express this as `vault:<name>:tag:<tag>:<action>`, but:

1. Multi-tag tokens would have unbounded scope-string length (`vault:default:tag:health:read vault:default:tag:wellness:read vault:default:tag:fitness:read ...`)
2. Hub-issued JWTs would carry a noisy claim that's actually a vault-internal concern
3. The `tags` field is a per-token attribute, not a per-action capability — the existing `read/write/admin` hierarchy still applies WITHIN the tag scope

Keeping `tags` as a separate token field is cleaner. Hub-issued JWTs only carry the existing `vault:<name>:<action>` claim; the tag-allowlist is read by vault from its own `tokens` table at request time.

## Hub awareness

Hub doesn't need to know about tag-allowlists at the OAuth level. Tokens with tag scope are minted via vault's `/admin/tokens` endpoint, not via the hub OAuth flow. The hub is the directory + issuer for cross-module tokens; tag-scoped tokens are within-vault.

If we later want third-party clients to request tag-scoped tokens via OAuth consent, that's a separate conversation about scope-string shape.

## Semantics

**Per-request auth, no session affinity.** The auth check runs on every request against the current token state and current tag hierarchy. There is no session-level cache; if a tag is renamed mid-session, the next request reflects the rename. Race conditions where a note is being edited concurrently with an auth check are intentional — the note's tags at the moment of the auth check are what's evaluated, and any client retries against fresh state.

**Out-of-scope reads return 404, not 403.** A `[health]`-allowlisted token requesting a `#work`-tagged note gets `404 Not Found`, not `403 Forbidden`. This prevents existence-leakage across the scope boundary — the token can't infer that a note exists by getting a `403`. Same shape applies to find-path hops and link expansion: out-of-scope notes are silently filtered; the agent sees a partial graph rather than gaps marked "you can't see this."

**Out-of-scope writes return 403 (not 404).** Writes are gated *before* the write happens; the existence of the target isn't being probed. Returning 403 here is the correct shape — the operator/agent attempted a write outside their allowlist; the system tells them so explicitly.

**Tag string is the authority.** A note's `note_tags` rows are what the auth check evaluates against. The `_tags/<name>` config notes provide schema (indexed fields, descriptions) but don't gate the auth check directly. A tag string `#health/food` on a note participates in scope evaluation regardless of whether `_tags/health/food` exists as a schema note (the string-form `/`-prefix hierarchy is sufficient).

## Lifecycle

**Tag rename cascades** (Aaron's directive 2026-05-02). When operator runs `PATCH /api/tags/<old_name>` with `{ name: <new_name> }`:

1. The `tags` row's `name` PK is updated. `note_tags`, `tag_schemas` (legacy, retired post-vault#244), and any other FK referencing `tags.name` cascade-update.
2. Sub-tags whose name has prefix `<old_name>/` are renamed to `<new_name>/...` recursively (each is its own row in `tags` with its own `parent_names`).
3. **`tags.parent_names` cascade** (post-vault#244): every tag with `<old_name>` in its `parent_names` JSON is rewritten to `<new_name>`. Without this, the hierarchy edge silently breaks on rename.
4. Tokens whose `scoped_tags` JSON array contains `<old_name>` (root-form) are auto-updated to contain `<new_name>` instead. Allowlist content changes; token id, label, and scope are preserved. Sub-tag renames (e.g., `health/food` → `health/snack`) are a no-op for token allowlists, since only root-form entries are stored there.
5. Note bodies referencing `#<old_name>` or `#<old_name>/...` are auto-updated.

The cascade is transactional — partial failure rolls back. Audit log entry per cascade with old → new mapping. **Implementation is filed as `vault#240`** (separate from Phase 1 of patterns#24); the v13 auth check stays robust to rename via the string-form fallback (per §Storage details mechanism 2). Note: tags use `name TEXT PRIMARY KEY` — no separate stable-id column; rename is a multi-table data migration not a single-column update.

**Tag delete fails closed if tokens reference it.** When operator runs `DELETE /api/tags/<name>` and any token has `<name>` (root-form) in its `scoped_tags` allowlist, the delete returns `409 Conflict` with the list of referencing token labels. Operator must revoke or re-mint those tokens (with the tag removed from allowlist) before retrying the delete. This is loud-fail by design: tag deletion is destructive and the operator should notice the dependency.

**Orphan sub-tag — fail-open.** A note carries tag `#health/food`. There's no schema declared for `health/food` (no `tags.parent_names` entry pointing at `health`). A token with allowlist `[health]` evaluating against this note: the auth check still returns true. The string-form `/`-prefix hierarchy (`rootOf("health/food") = "health"`) is the source of truth; missing schema declarations don't gate access. Schemas are about indexed fields and declared relationships, not auth.

> **Note (post-vault#244 / patterns#29):** Tag schemas + hierarchy parents now live as columns on the `tags` row (`tags.fields`, `tags.parent_names`), not in `_tags/<name>` config notes. The legacy `_tags/<name>` notes remain in vaults as inert historical record. The orphan-sub-tag concept above refers to "no `parent_names` entry declaring this sub-tag's parent," not "no `_tags/<name>` config note." Behavior unchanged; vocabulary updated.

## Storage details

**Auth check semantics: root-only allowlist with `/`-prefix expansion.**

The `scoped_tags` JSON array contains root tag names only — no path separators in allowlist values themselves. The auth check expands implicitly via two mechanisms (in this order):

1. **Schema-driven expansion** (when available): `getTagDescendants(<root>)` returns the set of all schema-declared sub-tags under that root. Cached per-tag with sync invalidation on `tags.parent_names` row writes (post-vault#244 / patterns#29; previously fired on `_tags/*` note writes).
2. **String-form fallback** (always): for each note tag `t`, compute `rootOf(t) = t.split("/")[0]`. If `rootOf(t)` is in the allowlist, the note tag is in scope. This catches orphan sub-tags (no schema declared) AND catches the case where the schema cache is stale.

The fallback makes the auth check robust to:
- Sub-tags that lack a schema note
- Schema cache rebuilds (the cache might briefly miss a descendant; the fallback covers it)
- Renamed tags during cascade (the fallback works on string state, not schema state)

**Storage of scoped_tags:**

```sql
ALTER TABLE tokens ADD COLUMN scoped_tags TEXT;
-- JSON-encoded array, NULL = unscoped (full vault access)
-- Empty array `[]` is rejected at mint — would mean "see nothing"
```

Validation at the API boundary: must be a JSON array of strings, each string a valid root-tag name (no `/` separators, no whitespace, no leading `_` since those are config-note conventions).

## Future evolution

The following extensions are explicitly deferred. Each is sound; none block Phase 1.

| Extension | Sketch | When to revisit |
| --- | --- | --- |
| **Read/write split** | Token has `read_tags` AND `write_tags`, where `read_tags ⊇ write_tags`. PostgreSQL RLS-style `USING` (read filter) and `WITH CHECK` (write filter). Use case: a journal bot that *reads* dreams (`#journal/dream`) but only *writes* logs (`#journal/log`). | When a real bot use-case wants asymmetric access. Track demand. |
| **Path-form allowlist** | Token's `scoped_tags` accepts `["health/food"]` for finer-than-root scoping. Root-form (`["health"]`) remains the default. | When operators want to delegate to a sub-team (e.g., a `#health/food` Claw with no access to other `#health/*` sub-tags). |
| **Tag groups / abstractions** | Define `[tag_group]` config notes (similar to `_tags/<name>`) that bundle several tags. Token allowlist can reference a group; group membership is dynamic. | After 3+ tokens have the same allowlist literally. |
| **Multi-vault tokens** | Token allowlist becomes `{ "default": ["health"], "boulder": ["health"] }`. Cross-vault scoping via single token. | When operators want a single agent identity working across multiple vaults. |
| **Scope by metadata** | Token carries metadata-conditions (e.g., `source: "prism"`). Composes with tag-scope. Filed as `parachute-patterns#25`. | Phase 2+ of the agents-as-channels arc. |
| **Time-bounded per-tag scope** | `scoped_tags: [{tag: "health", until: "2026-12-31"}]` — different tags have different lifetimes. | When token-level expiry isn't enough granularity. |

## Adoption

| Module | Action |
| --- | --- |
| **vault** | Phase 1 — schema migration, auth-check, query-notes filtering, mint UI in admin SPA, regression tests. All in one PR on `ag-unforced-dev` (UI + API together). Tracking PR will be filed under vault as Phase 1 implementation; this row will be updated with the PR number when it opens. |
| **vault** | Tag-rename-cascade implementation: `vault#240` (separate, post-Phase 1). |
| **vault** | Path/folder/name split design: `vault#238` (deferred design exploration). |
| **vault** | Wikilinks + tag-scope handling: `vault#239` (deferred design exploration). |
| **paraclaw** | Update `attach-vault` flow to optionally accept a tag-list; surface in agent-group settings UI; pass through to spawned-container env. |
| **hub** | No change at the OAuth layer — token shape stays the same. |
| **notes** | No change — Notes app uses operator-scope tokens (full access) by default. |

## Adoption notes

- Aaron approved this design 2026-05-02 (PR #24).
- Vault Phase 1 implementation includes API + UI in a single PR; the mint flow's tag-picker validates against existing root-tags via list-tags.
- Once shipped, file an entry in `adoption/migration-notes.md`.
- Follow-up issues to file: vault Phase 1, paraclaw `attach-vault` integration.
