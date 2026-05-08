# Well-known discovery URLs (RFC 8414 / RFC 9728)

## Convention

When an OAuth issuer has a path component, the well-known metadata
documents do **not** live under that path. They live at the **origin
root** with the issuer path inserted **after** the well-known type
segment.

For an issuer at `https://hub.example/vault/foo`:

| Path | Status |
|---|---|
| `https://hub.example/.well-known/oauth-authorization-server/vault/foo` | ✅ canonical (RFC 8414 §3.1) |
| `https://hub.example/.well-known/oauth-protected-resource/vault/foo`   | ✅ canonical (RFC 9728 §3) |
| `https://hub.example/vault/foo/.well-known/oauth-authorization-server` | ⚠️ lenient fallback only |
| `https://hub.example/vault/foo/.well-known/oauth-protected-resource`   | ⚠️ lenient fallback only |

The path-insertion form is what RFC 8414 §3.1 actually mandates.
Strict clients — including Claude Code's MCP SDK and any RFC 8414-
conformant client — **only** probe the path-insertion form. Without
those routes, discovery 404s and authentication can't even start.

## What Parachute serves

Vault serves **both shapes** for every per-vault metadata document.
Path-insertion is the canonical, spec-conformant route. Path-append
exists as a lenient fallback for less-strict clients (older MCP
implementations, hand-rolled scripts, anything that hard-coded
`/vault/<name>/.well-known/...` before the project caught the spec
wrong).

Both shapes return **byte-identical JSON** via the same handler — they
differ only in URL. There is no "preferred" version of the document
itself; the spec compliance is in the routing.

Canonical implementation:
[`parachute-vault/src/routing.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/routing.ts)
— path-insertion regexes
(`/^\/\.well-known\/oauth-(authorization-server|protected-resource)\/vault\/([^/]+)/`)
sit at the top of `route()` so they win against per-vault routing.
Path-append cases are handled inside the per-vault block. Landed in
[`parachute-vault#149`](https://github.com/ParachuteComputer/parachute-vault/pull/149).

## Why both

- **Spec correctness.** RFC 8414 §3.1 + RFC 9728 §3 mean
  path-insertion. Strict clients are right to require it; serving it
  is non-negotiable.
- **Real-world tolerance.** A meaningful slice of clients in 2026 still
  probe the path-append form (it's easier to construct as
  `${issuer}/.well-known/${type}` than as origin-root + insertion).
  Serving it costs us nothing — same handler, different URL — and
  prevents avoidable churn for integrators.
- **Discoverability is a one-shot probe.** The cost of getting it
  wrong is very high (silent 404, no diagnosis), and the cost of
  serving both is essentially zero.

## Rules

- **Path-insertion is the canonical advertised URL.** When a metadata
  document points clients at the AS metadata locator
  (`authorization_servers` in protected-resource metadata, etc.),
  point at the path-insertion form. Path-append is a
  receive-side concession, not an advertised endpoint.
- **Both shapes return identical bytes.** Don't diverge their
  contents; the only legitimate difference is the URL the client used
  to fetch.
- **Path-insertion routes match before per-vault routes.** Otherwise
  `/vault/<name>/.well-known/...` rules eat them. This is a routing
  ordering rule — see the comment block at the top of vault's
  `route()`.
- **404 unknown vaults explicitly.** Both shapes should return a JSON
  404 (`{ "error": "Vault not found", "vault": "<name>" }`) rather than
  falling through to a generic 404. Unauthenticated discovery probes
  should get a structured answer.
- **CORS-open both shapes.** Browser-based clients (web pages doing
  OAuth dance, Claude Code's webview) need `Access-Control-Allow-Origin: *`
  on these documents. They're public metadata.

## What this isn't

- **`/.well-known/parachute.json`** is the ecosystem-aggregator
  document — a different concern. It lives at the **hub** origin (CLI
  serves it), not at any module's origin, and follows
  [`module-protocol.md`](./module-protocol.md). RFC 8414 and RFC 9728
  don't apply to it; we just borrow the `/.well-known/` namespace.
- **`/.well-known/openid-configuration`** is OIDC, not OAuth. Vault
  doesn't serve it. If/when the hub grows OIDC support in Phase B2,
  the same path-insertion rule applies.

## Where this applies

- **`parachute-vault`** — reference implementation. Both shapes,
  byte-identical bodies, path-insertion advertised. PR #149.
- **`parachute-hub`** — when hub becomes the
  IdP itself in Phase B2 (see [`hub-as-issuer.md`](./hub-as-issuer.md)),
  hub takes over both routes. Issuer is `https://hub.example` (no path
  component), so the path-insertion vs. path-append distinction
  collapses for hub-rooted issuers — both forms reduce to
  `/.well-known/<type>`. The distinction only matters when the issuer
  has a path.
- **`parachute-scribe`, `parachute-channel`, future modules** — when
  they begin serving OAuth metadata, follow the same rule. If your
  service mounts at `/svc/<name>`, you serve
  `/.well-known/<type>/svc/<name>` at the origin root **and**
  `/svc/<name>/.well-known/<type>` at the per-service path.

## Open questions

- **Sunset for path-append.** When does the lenient fallback go away?
  Likely never for the per-vault case while real clients still probe
  it. The cost is too low to justify breaking integrators.
- **Multi-vault aggregation.** Today each vault has its own
  metadata document (one issuer per vault). If/when multiple vaults
  share an issuer (hub IdP in Phase B2 with vault as resource server
  for N vaults), there's a question of whether the per-vault
  protected-resource metadata still varies, or whether it collapses
  to one document with multiple resources. Not yet decided; deferred
  to the B2 design.
