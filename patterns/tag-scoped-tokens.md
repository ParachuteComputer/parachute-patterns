# Tag-scoped tokens

> **Status: shipped.** A vault token can be narrowed to a specific set of root tags. The token only sees and writes notes that carry one of those tags (or a sub-tag of one of them). Vault implementation: [`src/tag-scope.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/tag-scope.ts), shipped in [`vault#241`](https://github.com/ParachuteComputer/parachute-vault/pull/241) at rc.30 (2026-05-03).

## Convention

A vault token (`pvt_*`) optionally declares a **tag-allowlist** at mint time. Two axes compose:

1. **OAuth scope** — `vault:<name>:read | write | admin` per [`oauth-scopes.md`](./oauth-scopes.md). Verb-level capability.
2. **Tag allowlist** — list of root tag names stored on the token row as `scoped_tags`. Sub-tags expand per the `tags.parent_names` hierarchy (see [`tag-data-model.md`](./tag-data-model.md)).

The two axes are **separate by design**. The OAuth scope claim stays untouched — `vault:<name>:<verb>` — so hub-issued JWTs don't carry a noisy per-tag claim. The `scoped_tags` allowlist is a per-token vault-internal attribute, read at request time from the `tokens` row. Rationale in §"Why not extend the OAuth scope string."

The allowlist is set at mint time and not editable thereafter (no `PATCH /tokens/<id> { scoped_tags: ... }`); revise by minting a new token and revoking the old. The one exception is tag-rename cascade (§Lifecycle): a vault-side `POST /api/tags/<old>/rename` rewrites every `tokens.scoped_tags` row referencing `<old>` to `<new>` atomically, so the token's *content* tracks the renamed identity. The token id, label, and scope remain stable across the cascade.

Pseudocode for the auth check (real code: [`src/tag-scope.ts:31-101`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/tag-scope.ts)):

```ts
function authCheck(token, note, action) {
  if (!hasScope(token, `vault:${vault}:${action}`)) return forbidden();
  if (token.scoped_tags === null) return ok();             // unscoped — full vault access
  const allowed = expandTokenTagScope(store, token.scoped_tags);
  if (noteWithinTagScope(note, allowed, token.scoped_tags)) return ok();
  return forbidden();
}
```

Where `expandTokenTagScope` returns the union of `{root} ∪ descendants(root)` for each allowlisted root, via `store.expandTagsWithDescendants` which in turn calls `getTagDescendants` on the in-memory hierarchy built from `tags.parent_names`. `noteWithinTagScope` evaluates the expanded set AND a string-form fallback (`t.split("/")[0]` against the raw allowlist) so orphan sub-tags stay accessible — see §Storage details.

For operator-facing guidance on standing up a multi-writer workspace using these tokens, see [`guides/multi-writer-workspace.md`](../guides/multi-writer-workspace.md) §2 (the concrete worked example walks Alice/Bob/Carol through scoped-token issuance).

### Hierarchy match semantics

A token whose allowlist contains `health` matches:

- A note tagged `#health` (direct match)
- A note tagged ONLY with `#health/food` (hierarchy expansion via `tags.parent_names`)
- A note tagged ONLY with `#health/doctor` (same)
- A note tagged with `#health/food/breakfast` (recursive sub-tag)

The expansion routes through vault's `expandTokenTagScope` ([`src/tag-scope.ts:31-37`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/tag-scope.ts)) → `Store.expandTagsWithDescendants` ([`core/src/store.ts:299-307`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/store.ts)) → `getTagDescendants` ([`core/src/tag-hierarchy.ts:119`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/tag-hierarchy.ts)), which walks the in-memory hierarchy built from `tags.parent_names` (same resolver `query-notes` routes through; see [`tag-data-model.md`](./tag-data-model.md)). See §Storage details below for the full evaluation including the string-form fallback.

## Why

Originating motivation, Aaron's notes 2026-04-27 + 2026-04-30:

> *"...scoped tokens that can only write within a schema... other agents such as little telegram bots just have permission to modify stuff within that; only working with the tags you give it access to."*

> *"If I make a tag called #health and then a sub-tag #health/food, then I could have a bot that is just scoped on all of my #health tags including any sub-tags."*

The use case: per-purpose parachute-agent instances and per-purpose downstream bots. A `#health` agent, a `#work` agent, a `#journal` agent — each spawned from the same vault, but with isolated visibility into the slice of notes the operator has tagged for it. Per-vault isolation already existed (separate `default` / `boulder` / `techne` vaults); this lets you slice within one vault.

[Tracking issue: [`patterns#17`](https://github.com/ParachuteComputer/parachute-patterns/issues/17). The issue title proposed an OAuth-scope-string shape `vault:<name>:tag:<tagname>:<action>`; the shipped reality uses the `scoped_tags` token-attribute approach instead. See §"Why not extend the OAuth scope string" for the rationale.]

Schema-on-tag is a load-bearing concept in this design — see [`tag-data-model.md`](./tag-data-model.md) for the schema authoring shape. Each tag carries its own schema (description + indexed fields + typed relationships) directly on the `tags` row.

## How it composes

- **Read paths** — query-notes / GET /api/notes/:id / list-attachments filter results to only return notes with at least one allowlisted-root-tag (or sub-tag thereof).
- **Write paths** — POST /api/notes / PATCH require the new note to carry at least one allowlisted root-tag. POST without any matching tag returns `403 forbidden`.
- **Delete paths** — DELETE /api/notes/:id requires the existing note to be within scope. A token can't delete a note it can't read.
- **Tag operations** — `list-tags` returns only tags reachable from the allowlist (root tags + sub-tags). `update-tag` (the upsert tool — see [`tag-data-model.md`](./tag-data-model.md)) is allowed only if the target tag is at-or-under one of the allowlisted roots; same gate on `delete-tag`.
- **Schema operations** — `update-tag` (which writes the `tags` row's schema columns: `description`, `fields`, `relationships`, `parent_names`) is gated by `vault:<name>:admin` + tag-in-allowlist. A tag-scoped admin CAN modify the schema for tags within their allowlist.

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

The `POST /vaults/<name>/tokens` endpoint accepts an optional `tags` field:

```json
{
  "label": "health-bot",
  "scope": "vault:default:write",
  "tags": ["health", "wellness"],
  "expires_in": "30d"
}
```

When `tags` is omitted or `null`, the token is unscoped (full vault access). When present, the values must be existing root-tag names (no path separators).

The token mint UI in vault's admin SPA at `/admin/tokens` carries a tag-picker step that validates against existing root-tags via `list-tags`.

## Why not extend the OAuth scope string

Patterns#17 originally proposed `vault:<name>:tag:<tag>:<action>` as an OAuth scope shape. We rejected it in favor of a `scoped_tags` token attribute. Three reasons:

1. **Unbounded scope-string length.** A multi-tag token would emit `vault:default:tag:health:read vault:default:tag:wellness:read vault:default:tag:fitness:read ...`. Token headers / cookies bloat linearly with allowlist size.
2. **Wrong layer for vault-internal concern.** The OAuth scope claim is what hub-issued JWTs and resource servers exchange. Tag-level narrowing is a vault-internal authorization detail; emitting it in the OAuth-layer claim leaks an implementation choice into the cross-module contract.
3. **Per-token attribute, not per-action capability.** `read`/`write`/`admin` form a verb hierarchy within whatever scope is granted. Tags aren't a verb hierarchy — they're a content-shape attribute the token carries alongside its verbs. Mixing the two in one string conflates orthogonal axes.

Shipped shape: hub-issued JWTs carry the existing `vault:<name>:<action>` claim; vault reads the tag-allowlist from its own `tokens.scoped_tags` JSON column at request time. The two axes compose at the boundary without colliding in the wire format.

## Hub awareness

Hub doesn't need to know about tag-allowlists at the OAuth scope level. The `vault:<name>:<verb>` scope claim shape stays untouched on hub-issued JWTs; the per-tag narrowing is a vault-internal token attribute, evaluated at request time against the `tokens.scoped_tags` JSON column. Today's tag-scoped tokens are minted via vault's `/admin/tokens` endpoint (vault is the issuer of its own per-vault tokens — see [`patterns/hub-as-issuer.md`](./hub-as-issuer.md) Phase 0+1).

If third-party clients ever need to request tag-scoped tokens via the hub OAuth consent flow, that's a separate conversation about scope-string shape — see §"Why not extend the OAuth scope string" for the constraints we'd want to preserve.

## Semantics

**Per-request auth, no session affinity.** The auth check runs on every request against the current token state and current tag hierarchy. There is no session-level cache; if a tag is renamed mid-session, the next request reflects the rename. Race conditions where a note is being edited concurrently with an auth check are intentional — the note's tags at the moment of the auth check are what's evaluated, and any client retries against fresh state.

**Out-of-scope reads return 404, not 403.** A `[health]`-allowlisted token requesting a `#work`-tagged note gets `404 Not Found`, not `403 Forbidden`. This prevents existence-leakage across the scope boundary — the token can't infer that a note exists by getting a `403`. Same shape applies to find-path hops and link expansion: out-of-scope notes are silently filtered; the agent sees a partial graph rather than gaps marked "you can't see this."

**Out-of-scope writes return 403 (not 404).** Writes are gated *before* the write happens; the existence of the target isn't being probed. Returning 403 here is the correct shape — the operator/agent attempted a write outside their allowlist; the system tells them so explicitly.

**Tag string is the authority.** A note's `note_tags` rows are what the auth check evaluates against. The `tags` row carries the schema (description, fields, relationships, parent_names) but doesn't gate the auth check directly. A tag string `#health/food` on a note participates in scope evaluation regardless of whether `health/food` has a `tags.parent_names` entry pointing at `health` (the string-form `/`-prefix hierarchy is sufficient — see §Storage details mechanism 2).

## Lifecycle

**Tag rename cascades** (Aaron's directive 2026-05-02). When operator runs `POST /api/tags/<old_name>/rename` with `{ new_name: <new_name> }`:

1. The `tags` row's `name` PK is updated. `note_tags` and any other FK referencing `tags.name` cascade-update. (The legacy `tag_schemas` sidecar table was dropped in the v14 migration; no longer in scope for cascade.)
2. Sub-tags whose name has prefix `<old_name>/` are renamed to `<new_name>/...` recursively (each is its own row in `tags` with its own `parent_names`).
3. **`tags.parent_names` cascade** (post-vault#244): every tag with `<old_name>` in its `parent_names` JSON is rewritten to `<new_name>`. Without this, the hierarchy edge silently breaks on rename.
4. Tokens whose `scoped_tags` JSON array contains `<old_name>` (root-form) are auto-updated to contain `<new_name>` instead. Allowlist content changes; token id, label, and scope are preserved. Sub-tag renames (e.g., `health/food` → `health/snack`) are a no-op for token allowlists, since only root-form entries are stored there.
5. Note bodies referencing `#<old_name>` or `#<old_name>/...` are auto-updated.

The cascade is transactional — single `BEGIN IMMEDIATE`, ROLLBACK on any throw. Pre-flight collision check returns `{error: "target_exists", conflicting: [...]}` without touching the DB. **Shipped in [`vault#275`](https://github.com/ParachuteComputer/parachute-vault/pull/275)** (2026-05-04), replacing an earlier fail-closed-on-token-reference design that was carried in `vault#240`. The string-form fallback (§Storage details mechanism 2) backs the auth check so a partial cascade or pending rebuild never silently hides notes. Note: tags use `name TEXT PRIMARY KEY` — no separate stable-id column; rename is a multi-table data migration, not a single-column update.

**Tag delete fails closed if tokens reference it.** When operator runs `DELETE /api/tags/<name>` and any token has `<name>` (root-form) in its `scoped_tags` allowlist, the delete returns `409 Conflict` with `error_type: "tag_in_use_by_tokens"` and the list of referencing tokens. Operator must revoke or re-mint those tokens (with the tag removed from allowlist) before retrying the delete. **Tag merge is the same shape** — `POST /api/tags/merge` runs the same dependency check and 409s on the same envelope. This is loud-fail by design: tag deletion (and merge-with-consumption) is destructive, and the operator should notice the dependency rather than have allowlists silently orphaned. Reference: [`src/routes.ts:1338-1361`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/routes.ts) (delete), `routes.ts:1180-1200` (merge). The rename path *cascades* (above) rather than fail-closing, because rename preserves the tag's identity-as-meaning — only the string changes.

**Orphan sub-tag — fail-open.** A note carries tag `#health/food`. There's no `tags` row for `health/food`, or its `parent_names` doesn't include `health`. A token with allowlist `[health]` evaluating against this note: the auth check still returns true. The string-form `/`-prefix hierarchy (`rootOf("health/food") = "health"`) is the source of truth; a missing or incomplete `tags`-row hierarchy doesn't gate access. The `tags` row carries indexed fields and declared relationships, not auth state.

## Storage details

**Auth check semantics: root-only allowlist with `/`-prefix expansion.**

The `scoped_tags` JSON array contains root tag names only — no path separators in allowlist values themselves. The auth check expands implicitly via two mechanisms (in this order):

1. **Hierarchy-driven expansion** (when available): `getTagDescendants(<root>)` returns the set of all hierarchy-declared sub-tags under that root (i.e., tags whose `parent_names` transitively includes the root). Cached per-tag with sync invalidation on `tags.parent_names` row writes.
2. **String-form fallback** (always): for each note tag `t`, compute `rootOf(t) = t.split("/")[0]`. If `rootOf(t)` is in the allowlist, the note tag is in scope. This catches orphan sub-tags (no `parent_names` entry) AND catches the case where the descendants cache is stale.

The fallback makes the auth check robust to:
- Sub-tags that lack a `parent_names` entry
- Descendants cache rebuilds (the cache might briefly miss a descendant; the fallback covers it)
- Renamed tags during cascade (the fallback works on string state, not table state)

**Storage of scoped_tags:**

```sql
ALTER TABLE tokens ADD COLUMN scoped_tags TEXT;
-- JSON-encoded array, NULL = unscoped (full vault access)
-- Empty array `[]` is rejected at mint — would mean "see nothing"
```

Validation at the API boundary: must be a JSON array of strings, each string a valid root-tag name (no `/` separators, no whitespace, no leading `_`).

## Future evolution

The following extensions are explicitly deferred. Each is sound; none block Phase 1.

| Extension | Sketch | When to revisit |
| --- | --- | --- |
| **Read/write split** | Token has `read_tags` AND `write_tags`, where `read_tags ⊇ write_tags`. PostgreSQL RLS-style `USING` (read filter) and `WITH CHECK` (write filter). Use case: a journal bot that *reads* dreams (`#journal/dream`) but only *writes* logs (`#journal/log`). | When a real bot use-case wants asymmetric access. Track demand. |
| **Path-form allowlist** | Token's `scoped_tags` accepts `["health/food"]` for finer-than-root scoping. Root-form (`["health"]`) remains the default. | When operators want to delegate to a sub-team (e.g., a `#health/food` agent with no access to other `#health/*` sub-tags). |
| **Tag groups / abstractions** | Add a `tag_groups` table (or a `members` JSON column on `tag_groups` rows) bundling several tags. Token allowlist can reference a group; group membership resolves at auth-check time. | After 3+ tokens have the same allowlist literally. |
| **Multi-vault tokens** | Token allowlist becomes `{ "default": ["health"], "boulder": ["health"] }`. Cross-vault scoping via single token. | When operators want a single agent identity working across multiple vaults. |
| **Scope by metadata** | Token carries metadata-conditions (e.g., `source: "prism"`). Composes with tag-scope. Filed as `parachute-patterns#25`. | Phase 2+ of the agents-as-channels arc. |
| **Time-bounded per-tag scope** | `scoped_tags: [{tag: "health", until: "2026-12-31"}]` — different tags have different lifetimes. | When token-level expiry isn't enough granularity. |

## Adoption

| Module | Status |
| --- | --- |
| **vault** | **Shipped.** Schema migration v13 (`scoped_tags TEXT` column on `tokens`), auth-check via [`src/tag-scope.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/tag-scope.ts), query-notes filtering, mint UI in admin SPA, regression tests. Landed in [`vault#241`](https://github.com/ParachuteComputer/parachute-vault/pull/241) at rc.30 (2026-05-03). |
| **vault** | **Shipped.** Tag-rename cascade across `tokens.scoped_tags` (and every other surface) — transactional `BEGIN IMMEDIATE` + ROLLBACK on throw. Landed in [`vault#275`](https://github.com/ParachuteComputer/parachute-vault/pull/275) (2026-05-04, replacing the prior fail-closed 409 design). |
| **vault** | Path/folder/name split design: [`vault#238`](https://github.com/ParachuteComputer/parachute-vault/issues/238) (deferred design exploration). |
| **vault** | Wikilinks + tag-scope handling: [`vault#239`](https://github.com/ParachuteComputer/parachute-vault/issues/239) (deferred design exploration). |
| **parachute-agent** | Update `attach-vault` flow to optionally accept a tag-list; surface in agent-group settings UI; pass through to spawned-container env. **Not yet filed.** |
| **hub** | No change at the OAuth layer — `vault:<name>:<verb>` claim shape unchanged. Tag-allowlist is a vault-internal token attribute, not exposed in OAuth consent for Phase 1. |
| **notes** | No change — Notes app uses operator-scope tokens (full access) by default. Out-of-scope cells from any scoped token materialize as 404 from vault. |
| **patterns (this repo)** | Documented here + cross-linked from [`guides/multi-writer-workspace.md`](../guides/multi-writer-workspace.md). |

## Adoption notes

- Aaron approved this design 2026-05-02 (PR #24).
- Vault Phase 1 shipped 2026-05-03 ([`vault#241`](https://github.com/ParachuteComputer/parachute-vault/pull/241), rc.30); the mint flow's tag-picker validates against existing root-tags via list-tags.
- Tag-rename cascade shipped 2026-05-04 ([`vault#275`](https://github.com/ParachuteComputer/parachute-vault/pull/275)) — `scoped_tags` rewriting on rename replaced the fail-closed 409 originally specced in §Lifecycle.
- Migration-notes entries: [`adoption/migration-notes.md`](../adoption/migration-notes.md) — "2026-05-03 — Tag-scoped tokens Phase 1" and "2026-05-04 — Tag-scoped tokens — rename cascade replaces fail-closed 409."
- Outstanding follow-up: parachute-agent `attach-vault` integration (no issue filed yet).
