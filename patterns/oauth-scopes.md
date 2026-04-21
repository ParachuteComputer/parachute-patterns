# OAuth scopes

## Convention

Parachute OAuth tokens carry **whitespace-separated scope strings**
(OAuth 2.0 §3.3). Every scope follows the same shape:

```
<service>[:<resource>]*:<action>
```

- First segment — the service (vault, scribe, channel, hub, or any
  third-party module's declared name).
- Last segment — the action (`read`, `write`, `admin`, or a service-specific
  verb like `transcribe`, `send`).
- Middle segments (zero or more) — a resource hierarchy that narrows the
  scope. Today the only narrowing segment in use is `vault:<name>:<verb>`
  (per-vault), which is **parsed but treated as a synonym** for
  `vault:<verb>` in Phase 2.

## Launch scopes (Phase 0+1)

| Scope | Grants |
| --- | --- |
| `vault:read` | Read any vault via REST + MCP |
| `vault:write` | Write + read (inheritance) |
| `vault:admin` | Write + read + `/.parachute/config*` |
| `scribe:transcribe` | POST audio to scribe's transcription endpoint |
| `scribe:admin` | Manage scribe config |
| `hub:admin` | Reserved; not yet enforced |
| `channel:send` | Post messages via channel |

Third-party modules declare their own namespace (`my-service:read`, etc.)
and the hub renders consent for those scopes the same way.

## Inheritance

```
admin ⊇ write ⊇ read       (for vault)
```

- `vault:admin` satisfies any check for `vault:write` or `vault:read`.
- `vault:write` satisfies `vault:read`.
- **Non-vault scopes exact-match only.** `scribe:admin` does **not**
  currently imply `scribe:transcribe` — each non-inheritance-tree scope
  stands alone. This is deliberate: we add inheritance per-service
  when the verb set clearly lines up as read/write/admin.

Canonical implementation:
[`parachute-vault/src/scopes.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/scopes.ts)
(`hasScope`, `parseScopes`, `scopeForMethod`). Enforcement landed in
[PR #97](https://github.com/ParachuteComputer/parachute-vault/pull/97).

## Parser rules

- **Split on whitespace** for the scope string; **split on `:`** for each
  scope.
- **`vault:<name>:<verb>` collapses** to `vault:<verb>` during parse
  (Phase 2 synonym — per-vault narrowing is a Phase 2+ feature).
- **Empty resource segments are preserved verbatim** (`vault::read` stays
  `vault::read`, so it can't satisfy a `vault:read` check — a one-line
  defence against a malformed DB row).
- **Unknown scopes pass through** the parser untouched. They simply won't
  match anything, which is the right failure mode for a future-scope that
  reaches an old server.

## 403 response shape

When a request is authenticated but under-scoped, modules return:

```json
{
  "error": "Forbidden",
  "error_type": "insufficient_scope",
  "message": "This endpoint requires the 'vault:write' scope.",
  "required_scope": "vault:write",
  "granted_scopes": ["vault:read"]
}
```

`error_type: "insufficient_scope"` is the machine-readable key clients
should branch on (so they can present "Reconnect with broader access" UI
without parsing the human message).

## HTTP ↔ scope mapping

Vault's default, reused verbatim by any API-surface module with the same
verb set:

| Method | Scope |
| --- | --- |
| `GET` / `HEAD` / `OPTIONS` | `<service>:read` |
| `POST` / `PUT` / `PATCH` / `DELETE` | `<service>:write` |
| `/.parachute/config*` (regardless of method) | `<service>:admin` |

MCP tools are partitioned by intended effect, not by HTTP verb — see the
per-tool gate table in vault's PR #97.

## Soft-launch back-compat

v0.2-era tokens carry a legacy `permission` column (`"full"` or `"read"`)
instead of a scope string. For **one release cycle after enforcement
lands**, these are mapped on the fly by
`legacyPermissionToScopes(permission)`:

- `"full"` / `"admin"` / `"write"` → `[vault:read, vault:write, vault:admin]`
- `"read"` → `[vault:read]`

A one-shot per-process-per-token warning is logged on first use so
operators can see which tokens need rotation. The mapper is marked
`@deprecated`; remove it one release after v0.4.

The OAuth `token_endpoint_auth_methods_supported`/`scopes_supported`
metadata similarly keeps `full` + `read` alongside the `vault:*` scopes
for one release cycle so legacy clients don't hard-break on discovery.

## Rules

- **Declare scopes up front** in your module's `.parachute/module.json`
  under `scopes.defines`. The hub renders consent prompts from this list.
- **Use OAuth-standard whitespace serialization**, not comma-separated.
  Parsers MUST accept any whitespace run including `\t` + `\n`.
- **Don't invent synonyms.** A module adding a new verb should add the
  verb, not alias an existing scope. New scopes are additive and cheap.
- **Respect the `admin ⊇ write ⊇ read` contract** when your module has
  exactly that verb set. If your verbs are `send` / `admin`, don't force
  them into the read/write/admin tree — they're separate axes.
- **`vault:admin` (or any `:admin`) gates `/.parachute/config*`** on that
  module. This is the cross-cutting rule every module should honour.

## Future: per-resource narrowing (Phase 2+)

`vault:<name>:<verb>` is parsed today but collapsed to `vault:<verb>`.
The real shape, once enforced:

- `vault:work:read` — read the `work` vault only.
- `vault:work:notes/inbox/:read` — read one path prefix inside one vault
  (notional; not yet designed).
- `scribe:groq:transcribe` — use only the `groq` provider on scribe.

The parser already knows to split on `:`; the matcher is what gains the
"most-specific-grant-wins" logic when we flip this on.

## Where this applies

- `parachute-vault` — reference implementation + enforcement (PR #97).
- `parachute-scribe` — scopes declared under `x-scopes` in the config
  schema; enforcement follows once hub starts issuing JWTs. See scribe's
  CLAUDE.md ("Scopes declared, not yet enforced").
- `parachute-channel` — `channel:send` defined; enforcement tracking the
  same JWT cutover.
- `parachute-notes` — requests `vault:read vault:write scribe:transcribe`
  on first-run OAuth consent.

## Open questions

- When does `scribe:admin ⊃ scribe:transcribe` land? Not today, by the
  "exact-match for non-vault" rule. Likely when scribe grows a second
  non-admin verb and the tree clearly forms.
- Rotation / step-up story: a token granted `vault:read` requests
  `vault:write` later via refresh flow, hub re-prompts. Specced in the
  module-architecture design doc, not yet implemented.
