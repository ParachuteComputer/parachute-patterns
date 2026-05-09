# OAuth DCR approval lifecycle

## Convention

The hub is the OAuth issuer ([`hub-as-issuer.md`](./hub-as-issuer.md)) and
the gatekeeper for which OAuth clients exist on the install. **Every
public Dynamic Client Registration (RFC 7591) lands as `pending`.** A
pending client cannot exchange auth codes; it cannot reach `/oauth/token`.
The operator must explicitly grant approval via one of four paths before
the client can complete a flow. Same-origin SPAs (running at the hub's
origin) auto-approve when the operator's session cookie is present and
the request's `Origin` matches the issuer. Cross-origin SPAs (or
fresh-cache scenarios where the session isn't on the registration POST)
hit an inline approve button on the `/oauth/authorize` pending page —
one click and the flow continues.

The authoritative implementation is in
[`parachute-hub/src/oauth-handlers.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/oauth-handlers.ts)
(`handleRegister`, `handleApproveClientPost`, `originMatchesIssuer`) and
[`parachute-hub/src/clients.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/clients.ts)
(`approveClient`, `listClientsByStatus`). The browser surface is
[`parachute-hub/src/oauth-ui.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/oauth-ui.ts)
(`renderApprovePending`). The CLI surface is
[`parachute-hub/src/commands/auth.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/commands/auth.ts)
(`auth pending-clients`, `auth approve-client`, `auth revoke-grant`).
This doc captures the lifecycle and the *why*; if it disagrees with
the code, the code wins and this doc is wrong.

## Lifecycle

```
            register (no auth)
public DCR ─────────────────────► pending
                                     │
                                     │ operator demonstrates authority
                                     ▼
                                 approved
                                     │
                                     │ parachute auth revoke-grant <id>
                                     │ (or DB edit; explicit operator action)
                                     ▼
                                  removed
```

- **`pending` is the default** for any client registered via public DCR
  (`POST /oauth/register` with no auth headers).
- **`pending` → `approved` is one-way and operator-driven.** No automatic
  promotion from a passive event (time, request volume, anything).
- **`approved` does not expire.** Revocation is operator-explicit
  (`parachute auth revoke-grant <id>` or removing the row from
  `hub.db`).
- A pending client hitting `/oauth/token` gets `invalid_client` per RFC
  6749. A pending client hitting `/oauth/authorize` gets the
  human-readable "App not yet approved" page (with or without an inline
  approve button — see "Inline approve button" below).

## Four paths to `approved`

| Path | Trigger | Code | Originating PR |
|---|---|---|---|
| **Operator-bearer header** | `Authorization: Bearer <hub-admin-token>` (with `hub:admin` scope) on `POST /oauth/register` | [`oauth-handlers.ts:handleRegister`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/oauth-handlers.ts) — bearer branch | [hub#74](https://github.com/ParachuteComputer/parachute-hub/pull/74) |
| **Same-origin session cookie + matching Origin** | Hub session cookie present on `POST /oauth/register` AND request `Origin` matches `deps.issuer` | [`oauth-handlers.ts:handleRegister`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/oauth-handlers.ts) — cookie branch + `originMatchesIssuer` | [hub#200](https://github.com/ParachuteComputer/parachute-hub/pull/200) |
| **Inline approve button** | Operator browser navigates to `/oauth/authorize` for a pending client; session detected → approve form rendered → operator clicks → `POST /oauth/authorize/approve` | [`oauth-handlers.ts:handleApproveClientPost`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/oauth-handlers.ts) + [`oauth-ui.ts:renderApprovePending`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/oauth-ui.ts) | [hub#209](https://github.com/ParachuteComputer/parachute-hub/pull/209) |
| **CLI** | `parachute auth approve-client <id>` (operator with shell access to the hub install) | [`commands/auth.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/commands/auth.ts) + [`clients.ts:approveClient`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/clients.ts) | [hub#74](https://github.com/ParachuteComputer/parachute-hub/pull/74) |

The four paths exist because the operator demonstrates authority in
different contexts and the right friction profile is different in each:

- **Operator-bearer** — scripted / automation. The install path uses this
  so `parachute install vault` can self-register a first-party module
  without a human follow-up. Trust comes from possession of an
  operator-token with `hub:admin` scope.
- **Cookie + Origin** — operator's own SPA on the hub's own origin.
  Requiring approval here is friction without benefit: the operator is
  *already* the operator, the SPA is *their* SPA. Trust comes from the
  session cookie + the same-origin gate (CSRF defense).
- **Inline button** — operator's browser, pending client (cross-origin
  SPA, fresh cache, redirect_uri changed). The friction event is rare
  but real. Trust comes from triple-belt: CSRF token + active session +
  Origin/Referer match.
- **CLI** — headless / multi-machine / SSH-only contexts. Trust comes
  from shell access to the hub install (= already trusted).

## Security model

Each path has a different gate, sized to the context:

- **Operator-bearer.** Bearer token validated as `hub:admin`-scoped via
  the hub's normal scope check (see [`oauth-scopes.md`](./oauth-scopes.md)
  for scope semantics). If a bearer is presented but invalid or
  insufficiently-scoped, registration fails loudly with the RFC 6750
  shape — not a silent fall-through to `pending`. A caller who tried to
  authenticate but failed wants to know why.
- **Cookie + Origin.** Three-belt defense:
  1. Live (un-expired) session row keyed by the `parachute_hub_session`
     cookie.
  2. Request `Origin` (or `Referer` fallback) matches `deps.issuer` —
     `originMatchesIssuer`. URL.origin compares scheme + host + port.
  3. The session cookie itself is `SameSite=Lax`, so the browser blocks
     it from cross-site POSTs in the first place. The `originMatchesIssuer`
     check is the server-side belt for the cases where Lax doesn't cover
     us (curl probes, privacy-extension Origin stripping). A request
     with neither `Origin` nor `Referer` is treated as suspicious and
     rejected.
- **Inline button.** Same triple-belt as the cookie path, plus a CSRF
  token (double-submit cookie). The token is minted at GET render time
  and embedded in the form. Plus `return_to` is validated as a
  hub-relative `/oauth/authorize?...` path — open-redirect defense, plus
  it prevents the endpoint being used as a generic redirect-after-approve
  gadget. The operator sees `client_id`, `client_name`, `redirect_uris`,
  and the requested scopes before clicking.
- **CLI.** Assumes the operator has shell access to the hub install.
  The threat model treats shell access as already trusted — anything
  the CLI can do, anything else on the same shell can do. The CLI path
  exists to *enable* operators (headless boxes, scripts), not to gate
  them.

The shared invariant: **a client only becomes `approved` after the
operator has demonstrated authority via one of the four paths.**
There is no path that promotes a client without an explicit operator
action.

## The deliberate non-fix: cross-origin auto-approve

The interesting part of this pattern is what it *doesn't* do. A
cross-origin SPA — the agent's container UI talking to a tailnet hub,
or notes-via-cloudflare talking to the same — cannot auto-approve via
the cookie path. The "fix" looks straightforward (add CORS headers,
let the cookie ride) and was repeatedly tempting; we explicitly chose
not to ship it.

Four browser/policy gaps compound:

1. **`SameSite=Lax`** on the session cookie blocks the cookie from
   cross-origin POSTs by browser policy. This is a deliberate cookie
   property, not a bug.
2. **No CORS** on `/oauth/register` — no `Access-Control-Allow-Origin`,
   no `Access-Control-Allow-Credentials`. Adding them would invite
   third-party origins into the registration surface.
3. **No OPTIONS preflight** handler on `/oauth/register`. A
   credentialed cross-origin POST would preflight and fail.
4. **`originMatchesIssuer`** explicitly rejects cross-origin `Origin`
   values as a CSRF defense — even if the cookie *did* arrive, the
   server-side belt would reject the request.

Four options were considered (2026-05-08 design conversation):

- **A1 — first-party origin allowlist alone.** Add a list of trusted
  origins; if `Origin` matches one, treat as same-origin for the cookie
  check. **Eliminated:** doesn't actually work. The cookie's
  `SameSite=Lax` blocks the cookie *before* the server-side check runs.
  The allowlist would never see a cookie to validate.
- **A2 — second cookie with `SameSite=None; Secure` for DCR.**
  Mint a separate cookie with relaxed cross-site policy, scoped only
  to the DCR endpoint. Works in principle. **Costs:** expands the
  cookie surface (now there are two session-equivalent cookies),
  breaks HTTP loopback dev (Secure requires HTTPS), broader CSRF
  target (cross-site POSTs can ride the new cookie even with the
  origin allowlist on top).
- **A3 — same-origin relay popup.** SPA opens a hub-origin popup, the
  popup does the registration with the normal cookie (now same-origin),
  the popup `postMessage`s the `client_id` back. Robust to future
  browser changes, no new cookie surface. **Costs:** moderate code
  (popup orchestration on both sides), popup UX (can be blocked, can
  be confusing), still asynchronous on first run.
- **A4 — inline approve button on `/oauth/authorize` for pending
  clients with operator session.** The cross-origin DCR still leaves
  the client `pending`. The operator's browser then navigates the
  OAuth flow normally; the pending-client page detects their session
  and offers a one-click approve. **Picked.**

A4 won because:

1. **The friction event is rare.** Operators only see the approve
   button on first registration of a fresh client — browser cache
   clear, redirect_uri change, fresh device, new SPA. Not on every
   load (SPAs cache `client_id` in localStorage; see "For SPA
   developers" below). One click on a rare event is a fine ceiling.
2. **The security model is unchanged.** A4's inline approval requires
   the same operator authority as the CLI approve. We're not weakening
   the gate; we're just rendering it where the operator already is.
3. **Small code surface.** Roughly 50 lines in the handler plus a
   form section in the existing pending-client page, plus tests.
4. **Doesn't depend on browser policy** that may tighten further.
   `SameSite=Lax` and CORS rules are moving target; A4 is independent
   of both.

If a future scenario justifies cross-origin auto-approve — e.g.,
agent deployed at a separate hostname with high client-registration
churn — A2 or A3 can be layered on top of A4 without removing it.
A4 is the floor; the others would be additive.

[hub#201](https://github.com/ParachuteComputer/parachute-hub/issues/201)
tracked the original cross-origin auto-approve attempt and is closed
as deferred; this section is the canonical record of why.

## For SPA developers

- **Same-origin SPA** (your SPA loads from the hub's origin — e.g.
  Notes at `<hub>/notes/`): no special handling required. `fetch`
  defaults send the cookie. Just `POST /oauth/register` normally; the
  client lands `approved` if the operator's logged in.
- **Cross-origin SPA** (your SPA at a different origin): expect the
  inline approve button on the operator's first run. Don't try to
  bypass it. **Don't add `credentials: 'include'`** thinking it solves
  the problem — it doesn't (see the deferred section above; the gates
  are deeper than CORS).
- **Either way: cache your `client_id` in localStorage.** Re-registering
  on every page load both wastes a round-trip and re-triggers the
  approve gate. Re-register only when `redirect_uri` changes (e.g.
  the SPA moved hosts).

## For operators

- **First time you link an SPA to a vault**, expect either silent
  auto-approve (same-origin, you're logged in) or a one-click approve
  page.
- **"App not yet approved" with a button** → that's the inline approve
  UX. Review the `client_id` / `client_name` / `redirect_uris` / scopes
  shown, then click "Approve and continue."
- **"App not yet approved" without a button** → you're not logged into
  the hub in this browser. Visit `/admin/login`, sign in, then retry
  the SPA — or use the CLI path.
- **Headless contexts**: `parachute auth approve-client <id>`. List
  pending clients with `parachute auth pending-clients` to find the
  id.
- **Revoke when needed**: `parachute auth revoke-grant <client_id>` —
  removes the consent grant so the next flow re-prompts. To delete
  the client entirely, edit `hub.db` directly (no CLI command for full
  deletion yet — issue if needed).

## Where this applies

- **`parachute-hub`** — implements all four paths and the lifecycle.
  Single source of truth for client status.
- **`parachute-vault`** — Phase 0+1 issues OAuth on behalf of the hub
  (see [`hub-as-issuer.md`](./hub-as-issuer.md)) but does not run DCR
  itself. Vault-level vault-token issuance is a separate path and is
  not gated by this approval flow.
- **First-party modules** (vault, scribe, agent, notes) — register
  via the operator-bearer path during `parachute install <svc>`. They
  never see `pending`.
- **Third-party SPAs** — register via public DCR. They start
  `pending`. Operator promotes via one of the three operator-driven
  paths (cookie auto-approve, inline button, or CLI).

## Open questions

- **Re-approval flow on `redirect_uri` rotation.** Today an SPA that
  changes its `redirect_uri` re-registers (new `client_id`, new
  approval round). A first-class "update redirect_uri" flow without
  re-approval is plausible but not built. Defer until needed.
- **Auto-revoke on extended idle.** No automatic revocation today. If
  a client doesn't successfully complete a flow within N days of
  approval, do we revoke? Probably not (the friction event of
  re-approving outweighs the security win for installs with low
  churn), but it's an open question for cloud deployments.
- **Multi-operator approval.** Today the install has one operator.
  Multi-human team setups (post-2026) may want
  approval-requires-quorum. Out of scope for now; flagged for the
  multi-human governance bump (see
  [`governance.md`](./governance.md)'s "Open questions").

## Implementing changes

- [hub#74](https://github.com/ParachuteComputer/parachute-hub/pull/74)
  — base approval gate. Public DCR lands `pending`; operator-bearer
  and CLI paths land `approved`.
- [hub#199](https://github.com/ParachuteComputer/parachute-hub/issues/199)
  — design issue for same-origin auto-approve via session cookie
  (closed by #200).
- [hub#200](https://github.com/ParachuteComputer/parachute-hub/pull/200)
  — same-origin auto-approve via session cookie + Origin match.
  Adds the cookie branch to `handleRegister` and the
  `originMatchesIssuer` helper.
- [hub#201](https://github.com/ParachuteComputer/parachute-hub/issues/201)
  — cross-origin auto-approve original design. Closed; see "The
  deliberate non-fix" above.
- [hub#208](https://github.com/ParachuteComputer/parachute-hub/issues/208)
  — design issue for the inline approve button (closed by #209).
- [hub#209](https://github.com/ParachuteComputer/parachute-hub/pull/209)
  — inline approve button implementation. Adds
  `handleApproveClientPost` + the form section in
  `renderApprovePending`.
