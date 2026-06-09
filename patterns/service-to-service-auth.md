# Service-to-service auth

## Convention

When one Parachute service calls another (vault → scribe webhook,
future module → vault, etc.), the caller presents a **bearer token**
in the `Authorization` header and the callee runs that token through
**a single validator function** that returns `{valid, scopes}`.

The trust broker for that token is the **CLI** at install time — it
mints the secret, writes it to both ends, and never re-derives it.
This pattern is what every service-to-service call in the ecosystem
uses today, and the validator function is the seam where the future
JWT cutover happens.

## Today's shape (Phase 0+1)

A random hex secret per pair. The CLI's `auto-wire` step on `parachute
install`:

1. Generates `SCRIBE_AUTH_TOKEN = randomBytes(32).toString("hex")` if
   one isn't already in vault's `.env`.
2. Writes it to **both** sides of the trust boundary:
   - `~/.parachute/vault/.env` → `SCRIBE_AUTH_TOKEN=<hex>` (caller env)
   - `~/.parachute/scribe/config.json` → `{ "auth": { "required_token": "<hex>" } }` (callee config)
3. Idempotent — re-installs preserve the existing token, never
   regenerate.
4. Restarts vault if running so the worker re-reads the env (otherwise
   it would keep the stale value and silently 401).

Canonical implementation:
[`parachute-hub/src/auto-wire.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/auto-wire.ts).

The callee (scribe) validates with a single function:

```ts
// parachute-scribe/src/auth.ts
export function validateToken(token: string | undefined): AuthResult {
  const required = process.env.SCRIBE_AUTH_TOKEN;
  if (!required) return { valid: true, scopes: [] };
  if (!token) return { valid: false, reason: "token-required" };
  if (token !== required) return { valid: false, reason: "token-mismatch" };
  return { valid: true, scopes: ["scribe:transcribe", "scribe:admin"] };
}
```

The caller (vault) reads the token canonically via
[`parachute-vault/src/scribe-env.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/scribe-env.ts)
(`SCRIBE_AUTH_TOKEN` is the canonical name; an older `SCRIBE_TOKEN` is
accepted with a deprecation warning).

## Target shape (Phase B2)

Hub-issued JWTs with service-specific scopes, validated via JWKS. The
upgrade is a **validator-swap** — the body of `validateToken`
changes; nothing else does:

```ts
// Phase B2 — same signature, same return type, JWT-aware body
export function validateToken(token: string | undefined): AuthResult {
  if (!token) return { valid: false, reason: "token-required" };
  const claims = verifyJwt(token, process.env.PARACHUTE_HUB_JWKS);
  if (!claims) return { valid: false, reason: "token-mismatch" };
  return { valid: true, scopes: claims.scope.split(" ") };
}
```

The shared scope-guard library is proposed in
[`parachute-hub#59`](https://github.com/ParachuteComputer/parachute-hub/issues/59).
Every service uses the same `verifyJwt(...)` helper and pins trust
to the hub origin (see [`hub-as-issuer.md`](./hub-as-issuer.md)).

This is why the existing `validateToken` already returns scopes from
the shared-secret path — the scope vocabulary
([`oauth-scopes.md`](./oauth-scopes.md)) is the same on both sides of
the swap. Today the scopes are hard-coded on a successful match;
tomorrow they come from JWT claims.

## Key framing

**Service-to-service auth is a separate trust axis from user OAuth.**

| Axis | Issuer | Consent | Lifecycle |
|---|---|---|---|
| User OAuth | Hub origin ([`hub-as-issuer.md`](./hub-as-issuer.md)) | Per user, per app | Token revocable per user |
| Service-to-service | CLI at install time | Implicit (operator runs install) | Rotates only on explicit re-issue |

They use the **same scope vocabulary** but **different validators**
today. Phase B2 converges them — the same JWKS-backed verifier
validates both. Until then, don't conflate them: a user-facing token
(a hub-minted JWT; historically a `pvt_*` PAT — retired, see
[`token-auth.md`](./token-auth.md)'s banner) should never be accepted
by an inter-service callee, and a service secret should never appear
on a user-facing surface.

## Rules

- **One validator function per service.** A single seam — function
  signature `(token) → {valid, scopes}` — is the only thing callees
  consult on every request. Don't sprinkle auth checks across route
  handlers.
- **The CLI mints, both ends store.** Services never generate their
  own inter-service secrets; the CLI is the only trust broker. Two
  ends with the same secret is a service-pair contract.
- **Idempotent install.** Existing secrets are preserved across
  re-installs. Regenerating a token without coordinating both ends
  would break a running deployment silently.
- **Restart after rotation.** When a token changes, both processes
  must re-read it before the next call. The CLI handles this for the
  caller (vault); callees that hot-reload config get it for free.
- **Loopback-only today.** Service-to-service traffic stays on
  `127.0.0.1`. Never expose the inter-service surface publicly until
  the JWT cutover lands — string-equal on a hex secret is fine for
  loopback, not for the open internet.
- **Scope-bearing return shape.** Even with a shared secret, the
  validator should return scopes (`["scribe:transcribe", "scribe:admin"]`
  on success). This keeps callers JWT-ready without a code change.
- **Exempt only the obvious.** `/health` and `/.parachute/info` are
  unauthenticated by convention (used by the CLI's status checks);
  every other route auths.

## Where this applies

- **`parachute-vault` → `parachute-scribe`** — reference pair. Vault
  posts audio attachments to scribe with `Authorization: Bearer
  ${SCRIBE_AUTH_TOKEN}`. Scribe validates via
  [`src/auth.ts`](https://github.com/ParachuteComputer/parachute-scribe/blob/main/src/auth.ts).
- **`parachute-hub`** — implements the trust
  broker in `auto-wire.ts`. Future inter-service pairs (e.g.
  channel → vault for triggered actions) follow the same pattern: a
  named env on the caller, a config field on the callee, idempotent
  generation.
- **Future third-party modules** — declare an inter-service secret
  env var in your `.parachute/module.json` (when
  [`module-json-extensibility.md`](./module-json-extensibility.md)
  lands). The CLI's auto-wire reads the declaration and provisions
  the pair.

## Open questions

- **Rotation story.** Today rotation is "edit both ends, restart both
  processes." Acceptable for loopback. After B2, JWT expiry handles
  most rotation; explicit `parachute auth rotate <pair>` may still be
  useful for revocation events.
- **N-to-1 fan-in.** A service called by N callers (future hub →
  vault for privileged writes) needs N secrets, or one secret + a
  caller identifier in the token. JWT cutover solves this naturally
  via `aud` / `azp` claims; pre-cutover we'd need to bend the shape.
- **Cross-host (cloud) deployments.** Loopback-only is fine for the
  single-machine install. A cloud topology where vault and scribe
  run on different hosts needs the JWT cutover before it can ship —
  string-equal-over-the-wire is not acceptable.

## What's out of scope here

- **User OAuth scopes and issuer** — see
  [`oauth-scopes.md`](./oauth-scopes.md) and
  [`hub-as-issuer.md`](./hub-as-issuer.md).
- **User tokens** — hub-minted JWTs (scoping:
  [`tag-scoped-tokens.md`](./tag-scoped-tokens.md)); the retired
  `pvt_*` PAT path is [`token-auth.md`](./token-auth.md) (superseded —
  see its banner). Different trust axis; do not interchange with
  service secrets.
- **Service-to-service over MCP** — MCP transport carries its own
  bearer (a hub-minted user JWT, not a service secret). Covered in
  [`mcp-transport.md`](./mcp-transport.md).
