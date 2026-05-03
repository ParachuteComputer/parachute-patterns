# Tag-scoped tokens [DRAFT]

> One-line summary: a vault token can be narrowed to a specific set of root tags. The token only sees and writes notes that carry one of those tags (or a sub-tag of one of them).

## Convention

A vault token (`pvt_*`) optionally declares a **tag-allowlist** at mint time. Once set, the token's effective access is the intersection of:

1. **Scope** (existing) — `vault:<name>:read | write | admin` per `oauth-scopes.md`
2. **Tag allowlist** (new) — list of root tag names. Sub-tags inherit per the existing `_tags/<name>` hierarchy machinery (vault#214 / store-routing fix).

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

## Why

[From Aaron's notes 2026-04-27 + 2026-04-30]

> *"...scoped tokens that can only write within a schema... other agents such as little telegram bots just have permission to modify stuff within that; only working with the tags you give it access to."*

> *"If I make a tag called #health and then a sub-tag #health/food, then I could have a bot that is just scoped on all of my #health tags including any sub-tags."*

The use case: per-purpose paraclaw bots. A `#health` Claw, a `#work` Claw, a `#journal` Claw — each spawned from the same vault, but with isolated visibility into the slice of notes the operator has tagged for it. Currently isolation is per-vault (separate `default` / `boulder` / `techne` vaults); this lets you slice within one vault.

## How it composes

- **Read paths** — query-notes / GET /api/notes/:id / list-attachments filter results to only return notes with at least one allowlisted-root-tag (or sub-tag thereof).
- **Write paths** — POST /api/notes / PATCH require the new note to carry at least one allowlisted root-tag. POST without any matching tag returns `403 forbidden`.
- **Delete paths** — DELETE /api/notes/:id requires the existing note to be within scope. A token can't delete a note it can't read.
- **Tag operations** — list-tags returns only tags reachable from the allowlist (root tags + sub-tags). create-tag is allowed only if the new tag is a sub-tag of one of the allowlisted roots.
- **Schema operations** — `_tags/<name>` config notes are write-protected unless the token has `vault:<name>:admin` AND the tag is in the allowlist.

## Composability with existing scopes

- `vault:<name>:read` + tag-allowlist `[health]` — token can READ notes tagged with `#health` or any `#health/*` sub-tag, nothing else.
- `vault:<name>:write` + tag-allowlist `[health]` — token can READ + WRITE within the `#health` slice. Cannot write notes outside `#health`.
- `vault:<name>:admin` + tag-allowlist `[health]` — admin ops (config, schema) restricted to the `#health` slice.
- `vault:<name>:admin` + tag-allowlist `null` — current full-vault admin behavior.

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

If we later want third-party clients to request tag-scoped tokens via OAuth consent, that's a Phase 2 conversation about scope-string shape.

## Adoption

| Module | Action |
| --- | --- |
| **vault** | Implement: schema migration, auth-check, query-notes filtering, mint UI in admin SPA, regression tests |
| **paraclaw** | Update `attach-vault` flow to optionally accept a tag-list; surface in agent-group settings UI; pass through to spawned-container env |
| **hub** | No change at the OAuth layer — token shape stays the same |
| **notes** | No change — Notes app uses operator-scope tokens (full access) by default |

## Open questions

1. **What does "tag-scoped admin" actually grant?** A `vault:<name>:admin` + `tags: [health]` token: can it modify the `#health` schema (`_tags/health`)? The `#health/food` sub-schema? My read: yes to both — admin within the allowlist. Aaron, confirm?

2. **Tag-allowlist immutability** — once minted, can the allowlist be edited? Or is it like the scope (immutable for the life of the token, edit = new token)? My read: immutable — same shape as scope. Add tags = new token with revoke of old. Aaron, confirm?

3. **Hierarchy expansion semantics** — when a token's allowlist contains `health`, does it match a note tagged ONLY with `health/food` (no direct `health` tag)? My read: yes — the hierarchy expansion already does this for `query-notes` (vault#214). The auth check uses the same expansion. Aaron, confirm?

4. **Token visibility** — a tag-scoped token's `list-tokens` view (vault admin SPA) shows the allowlist. But should the vault admin SPA itself be scope-restricted? E.g., should a `vault:<name>:admin` + `tags: [health]` token be able to mint *new* tokens with broader allowlists? My read: NO — admin within the allowlist means admin restricted to that slice. The mint endpoint enforces "can only mint tokens whose allowlist is a subset of mine."

5. **"Schema" in your 2026-04-27 note** — you wrote about "scoped tokens that can only write within a schema." Is "schema" here distinct from "tag," or is it the same thing (since `_tags/<name>` config notes ARE the schema)? My read: same thing — schema = tag config note, tag-scope IS schema-scope. Aaron, confirm?

6. **First implementation milestone** — should the first PR ship just the data-model + auth-check (no UI), or include the mint-UI tag-picker? My read: data-model + auth-check first as a fixed-shape API; UI in Phase 2 once the contract is settled. Aaron, confirm?

## Adoption notes

- This pattern is `[DRAFT]` until at least vault has shipped Phase 1 (data-model + auth-check) and Aaron has confirmed it works for at least one real bot use-case.
- Once that happens, file an entry in `adoption/migration-notes.md` and remove the `[DRAFT]` marker.
- Filing issues for: vault (Phase 1 + Phase 2), paraclaw (attach-vault flow), notes (mint UI for tag-scoped tokens).
