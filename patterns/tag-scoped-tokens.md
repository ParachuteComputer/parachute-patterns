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
- A note tagged ONLY with `#health/food` (hierarchy expansion via `_tags/<name>`)
- A note tagged ONLY with `#health/doctor` (same)
- A note tagged with `#health/food/breakfast` (recursive sub-tag)

The expansion uses vault's existing `getTagDescendants` machinery (same path that `query-notes` routes through post-#214 / #231).

## Why

[From Aaron's notes 2026-04-27 + 2026-04-30]

> *"...scoped tokens that can only write within a schema... other agents such as little telegram bots just have permission to modify stuff within that; only working with the tags you give it access to."*

> *"If I make a tag called #health and then a sub-tag #health/food, then I could have a bot that is just scoped on all of my #health tags including any sub-tags."*

The use case: per-purpose paraclaw bots. A `#health` Claw, a `#work` Claw, a `#journal` Claw — each spawned from the same vault, but with isolated visibility into the slice of notes the operator has tagged for it. Currently isolation is per-vault (separate `default` / `boulder` / `techne` vaults); this lets you slice within one vault.

Schema = tag in this design — the `_tags/<name>` config note IS the schema for tag `<name>`.

## How it composes

- **Read paths** — query-notes / GET /api/notes/:id / list-attachments filter results to only return notes with at least one allowlisted-root-tag (or sub-tag thereof).
- **Write paths** — POST /api/notes / PATCH require the new note to carry at least one allowlisted root-tag. POST without any matching tag returns `403 forbidden`.
- **Delete paths** — DELETE /api/notes/:id requires the existing note to be within scope. A token can't delete a note it can't read.
- **Tag operations** — list-tags returns only tags reachable from the allowlist (root tags + sub-tags). create-tag is allowed only if the new tag is a sub-tag of one of the allowlisted roots.
- **Schema operations** — `_tags/<name>` config notes are write-protected unless the token has `vault:<name>:admin` AND the tag is in the allowlist. A tag-scoped admin CAN modify the schema for tags within their allowlist.

## Composability with existing scopes

- `vault:<name>:read` + tag-allowlist `[health]` — token can READ notes tagged with `#health` or any `#health/*` sub-tag, nothing else.
- `vault:<name>:write` + tag-allowlist `[health]` — token can READ + WRITE within the `#health` slice. Cannot write notes outside `#health`.
- `vault:<name>:admin` + tag-allowlist `[health]` — admin ops (config, schema for `#health` and sub-tags) restricted to the `#health` slice.
- `vault:<name>:admin` + tag-allowlist `null` — current full-vault admin behavior.

## Mint authority

A tag-scoped admin **cannot** mint new tokens with broader allowlists. The mint endpoint enforces: *"a token's allowlist must be a subset of the minter's allowlist."* This prevents privilege escalation via mint:

- Admin with `[health]` minting a token with `[health, work]` → `403 forbidden`
- Admin with `[health]` minting a token with `[health/food]` → OK (subset)
- Admin with `[health]` minting a token with `[health]` → OK (equal)
- Admin with `null` (unscoped) minting any allowlist → OK (null is the universe)

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

## Adoption

| Module | Action |
| --- | --- |
| **vault** | Phase 1 — schema migration, auth-check, query-notes filtering, mint UI in admin SPA, regression tests. All in one PR per Aaron's call (UI + API together). |
| **paraclaw** | Update `attach-vault` flow to optionally accept a tag-list; surface in agent-group settings UI; pass through to spawned-container env |
| **hub** | No change at the OAuth layer — token shape stays the same |
| **notes** | No change — Notes app uses operator-scope tokens (full access) by default |

## Adoption notes

- Aaron approved this design 2026-05-02 (PR #24).
- Vault Phase 1 implementation includes API + UI in a single PR; the mint flow's tag-picker validates against existing root-tags via list-tags.
- Once shipped, file an entry in `adoption/migration-notes.md`.
- Follow-up issues to file: vault Phase 1, paraclaw `attach-vault` integration.
