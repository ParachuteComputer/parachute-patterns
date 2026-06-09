# Auth stack — umbrella

> Signpost across the auth-cluster pattern docs. **If you're trying to
> X, read Y.** This file links — it doesn't duplicate. The
> authoritative shape for each piece lives in the linked doc; if those
> diverge from this one, the linked doc wins.

## The stack at a glance

```
┌─────────────────────────────────────────────────────────────┐
│  Operator browser / agent / external surface (notes, etc.)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │  OAuth code-flow (RFC 6749 + PKCE)
                               │  or paste a hub-minted JWT
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  hub (the OAuth issuer for the whole ecosystem)              │
│  • DCR (RFC 7591) — every public reg lands `pending`         │
│  • /oauth/authorize, /oauth/token, JWKS                      │
│  • Mints JWT access (15min) + refresh (30d, rotated)         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │  Bearer JWT with scopes
                               │  `vault:<name>:<verb>` etc.
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  resource server (vault / agent / scribe — today only vault) │
│  • Validates JWT vs hub JWKS, checks `aud` + `iss`           │
│  • Per-token attributes: scoped_tags allowlist               │
│  • Pure resource server — no module mints (pvt_* retired)    │
└─────────────────────────────────────────────────────────────┘
```

## If you're trying to…

### Understand who issues tokens and why everything points at hub

Read [`hub-as-issuer.md`](./hub-as-issuer.md). The single architectural
fact this rests on: every auth-capable module advertises **the hub
origin** as its `issuer`, regardless of where the module itself is
hosted. Token `iss` claims, discovery documents, and the service
catalog returned with the token all stem from one resolver so they
can never disagree.

### Pick a scope string for a new endpoint or capability

Read [`oauth-scopes.md`](./oauth-scopes.md) — the scope vocabulary
(`<service>[:<resource>]*:<action>`), the registered launch scopes
(`vault:<name>:<verb>`, `scribe:*`, `agent:*`,
`parachute:host:admin`), inheritance semantics (`admin ⊇ write ⊇
read`), and the non-requestable-scope mechanism for operator-only
capabilities.

### Implement the consent dance for a new third-party client

Read [`oauth-dcr-approval.md`](./oauth-dcr-approval.md). Dynamic
Client Registration (RFC 7591) lands every public registration as
`pending`. The four approval paths (CLI, browser inline button,
same-origin auto-approve, hub admin UI). The state machine and the
hub-side implementation pointers.

### Mint a token a user pastes into a script or CLI

Hub-minted JWTs are the **only live issuance**: `parachute auth
mint-token --scope vault:<name>:<verb>` (optionally `--ephemeral`), or
the admin SPA tokens page. Scoping incl. tag-allowlists:
[`tag-scoped-tokens.md`](./tag-scoped-tokens.md). The historical
module-minted `pvt_*` PAT path is retired — see the supersession
banner on [`token-auth.md`](./token-auth.md).

### Narrow a token to a specific slice of a vault

Read [`tag-scoped-tokens.md`](./tag-scoped-tokens.md). Tokens can
declare a `scoped_tags` allowlist at mint time. The OAuth scope
claim (`vault:<name>:<verb>`) stays clean; the allowlist rides the
hub-issued JWT in a dedicated **`permissions.scoped_tags` claim**
(post-C0, 2026-05-28), not a scope-string extension. Hierarchy
expansion via `tags.parent_names`, string-form fallback for orphan
sub-tags, fail-closed delete-tag guards.

### Wire one service to call another

Read [`service-to-service-auth.md`](./service-to-service-auth.md).
The validator-seam pattern: each callee runs incoming tokens
through one `validateToken(token) → {valid, scopes}` function.
Today's shared-secret implementation (CLI mints + writes to both
ends) is the body of that function; the future hub-issued-JWT
implementation is a body-swap. Callers and callees don't change.

### Serve OAuth metadata for an issuer with a path component

Read [`well-known-discovery-rfc.md`](./well-known-discovery-rfc.md).
RFC 8414 §3.1 mandates path-insertion (`<origin>/.well-known/<type>/<path>`),
not path-append. Vault serves both shapes; path-insertion is
canonical. Strict clients (Claude Code's MCP SDK, RFC 8414-conformant
libraries) **only** probe the canonical form.

### Get industry-survey-level depth on the whole auth surface

Read [`research/auth-architecture-shape.md`](../research/auth-architecture-shape.md).
The 2026-05-09 working note that traces all five concurrent token
shapes (`parachute_hub_session` cookie, hub-issued OAuth access JWT,
hub-issued refresh JWT, `operator.token`, `pvt_*` PAT, plus the
legacy `SCRIBE_AUTH_TOKEN` shared-secret on s2s), surveys how
mature systems (Auth0, Clerk, Supabase, Cloudflare Access) shape
the equivalent surface, and records the decision direction (hub as
sole AS; vault/agent/scribe as RS) plus migration tracker
[hub#212](https://github.com/ParachuteComputer/parachute-hub/issues/212).
Research-tier — pattern docs are for resolved patterns; this is
the longer arc still being worked through.

## The two token paths (one live, one historical)

Two paths used to reach the same resource server with the same scope
vocabulary; since the `pvt_*` retirement (vault#412, the 2026-05-28
capability-attenuation arc) only the OAuth path issues:

| Path | Issuer | Token shape | Storage | Audience | Status |
| --- | --- | --- | --- | --- | --- |
| **OAuth bearer** | hub | JWT signed by hub JWKS | not stored; validated stateless | bound (`aud=vault.<name>` etc.) | **the only live issuance** — agents, third-party SPAs, programmatic consumers, *and* paste-into-script credentials (`parachute auth mint-token`, optionally `--ephemeral`) |
| **`pvt_*` PAT** | vault (or other RS) | random opaque token, `pvt_` prefix | sha256 hash in RS DB | implicit (per-row) | **retired** — see the supersession banner on [`token-auth.md`](./token-auth.md) |

The PAT path was legacy and direct: hub never saw it, vault validated
against its own `tokens` table. The ergonomic problems PATs solved
(pasted secrets in scripts, short-lived automation credentials) are
now served by hub-minted JWTs — scoped, optionally ephemeral, and
revocable through the hub's token registry — so the flat-secret
escape hatch retired instead of accumulating its own layer cake. No
module mints; issuance is the hub's
([`hub-module-boundary.md`](./hub-module-boundary.md)).

## How the cluster composes

Every PR that touches auth typically touches more than one of these
files because the underlying concepts compose:

- A new resource server adopts `hub-as-issuer` + `oauth-scopes` +
  `well-known-discovery-rfc` together. None of those make sense
  alone.
- A new capability registers a scope (`oauth-scopes`), might add a
  per-token attribute (`tag-scoped-tokens` shape), and gets enforced
  at request time on the RS.
- A new client either goes through DCR (`oauth-dcr-approval`) and
  consents (hub-side) or asks the operator to paste a hub-minted JWT
  (`parachute auth mint-token`; the retired PAT path is `token-auth`).
- A new inter-service edge either inherits the validator seam
  (`service-to-service-auth`) on a shared-secret basis or upgrades
  to hub-issued JWTs (Phase B2 cutover).

Each PR's `## Patterns check` per [`governance.md`](./governance.md)
Rule 3 should name which auth-cluster docs the change touches.

## Cross-links

- [`hub-as-issuer.md`](./hub-as-issuer.md) — the issuer architecture
- [`oauth-scopes.md`](./oauth-scopes.md) — the scope vocabulary
- [`oauth-dcr-approval.md`](./oauth-dcr-approval.md) — DCR + consent
- [`token-auth.md`](./token-auth.md) — `pvt_*` PAT path (historical —
  superseded; see its banner)
- [`tag-scoped-tokens.md`](./tag-scoped-tokens.md) — sub-vault scope
- [`service-to-service-auth.md`](./service-to-service-auth.md) —
  inter-service edges
- [`well-known-discovery-rfc.md`](./well-known-discovery-rfc.md) —
  metadata URLs
- [`research/auth-architecture-shape.md`](../research/auth-architecture-shape.md)
  — full survey + decision direction
- [`guides/multi-writer-workspace.md`](../guides/multi-writer-workspace.md)
  §2 — operator-facing scoped-token worked example
- [`governance.md`](./governance.md) Rule 3 — patterns-check
  discipline
