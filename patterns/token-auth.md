# Token auth — `pvt_` tokens

## [DRAFT] — canonicalizing the shape across modules

## Convention

Parachute-issued bearer tokens use a `pvt_` prefix ("parachute token"), are
stored as sha256 hashes (never in clear), are scoped to a vault / tenant /
agent, and are revealed to the user exactly once via the issuing surface —
typically a cookie-gated modal after creation.

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
  scope is a bug.
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

- `parachute-vault` — vault tokens for REST / MCP auth.
- `parachute-cloud` — tenant-scoped vault access tokens.
- `@openparachute/agent` — inbound webhook tokens for trigger auth (when the
  runner exposes a webhook endpoint).

## Open questions

- Rotation story: today we revoke + re-issue. Should we add
  per-token-rotation (old token works for 24h after rotation)? Not needed
  until an automated client can't tolerate a flip.
- Per-scope TTL defaults: unset today. Reasonable future: `agent:invoke`
  tokens default to 90d, `vault:*` tokens default to no expiry (revoke
  explicitly).
