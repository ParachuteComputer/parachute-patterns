# Token auth — `pvt_` tokens

## Convention

Parachute-issued **personal access tokens** use a `pvt_` prefix
("parachute token"), are stored as sha256 hashes (never in clear), are
scoped to a vault / tenant / agent, and are revealed to the user
exactly once via the issuing surface — typically a cookie-gated modal
after creation.

`pvt_*` tokens are the **user-facing PAT** path: a logged-in human
generates one in the issuing module's UI and pastes it into a script,
a CLI, or a third-party tool. They sit alongside the **OAuth bearer
token** path ([`hub-as-issuer.md`](./hub-as-issuer.md)), which is for
agent-to-service and service-to-service flows where the consumer goes
through the consent dance. Same scope vocabulary on both — see
[`oauth-scopes.md`](./oauth-scopes.md).

## Shape

```
pvt_<base64url random 32 bytes>
```

Stored as:

```
sha256(pvt_...) hex → (tenant_id, scope, created_at, last_used_at, label)
```

## Rules

- **Prefix is `pvt_`.** Makes tokens instantly grep-able in logs and in
  leaked credentials scanners. No module should use a different prefix.
- **Store only the hash.** The server never has a plaintext token after
  issuance. Comparing: hash the incoming bearer, look up by hash.
- **Scope is required.** Every token has a named scope
  (`vault:read`, `vault:write`, `agent:invoke`, etc.). A token without
  scope is a bug. Scope strings follow
  [`oauth-scopes.md`](./oauth-scopes.md) — `pvt_*` and OAuth bearer
  tokens share one vocabulary so a `vault:read` grant means the same
  thing on either side of the validator seam.
- **Reveal once.** The UI that issues a token shows the full `pvt_...`
  exactly one time, gated by the user's active session cookie. After modal
  close, the UI shows only a last-4 suffix + label. The caller is
  responsible for copying it then.
- **Last-used tracking.** Record `last_used_at` on each successful auth so
  stale tokens can be surfaced in an admin view.
- **Revocation is by hash.** Deleting the hash row revokes instantly.

## Why

- Prefix + scope + hash is the pattern GitHub / Anthropic / most modern
  token issuers use. Nothing exotic.
- The cookie-reveal pattern prevents a leaked clipboard or ps-listing from
  burning a token post-issuance — the plaintext exists only in the user's
  browser for one modal's lifetime.
- One sha256 hash per row gives O(1) lookup without a KV rotation concern.

## Where this applies

- `parachute-vault` — vault tokens for REST / MCP auth. Today this is
  the only shipped issuer of `pvt_*` tokens.
- Future modules with a user-facing PAT surface — same shape, same
  scope vocabulary. Modules whose only credentialed callers are agents
  or other services should prefer the OAuth bearer path
  ([`hub-as-issuer.md`](./hub-as-issuer.md)) over minting their own
  `pvt_*` issuer.

## Open questions

- Rotation story: today we revoke + re-issue. Should we add
  per-token-rotation (old token works for 24h after rotation)? Not needed
  until an automated client can't tolerate a flip.
- Per-scope TTL defaults: unset today. Reasonable future: `agent:invoke`
  tokens default to 90d, `vault:*` tokens default to no expiry (revoke
  explicitly).
