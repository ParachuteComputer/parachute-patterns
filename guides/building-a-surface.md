# Building a surface over parachute-vault

> A reference for builders shipping a web app, dashboard, capture tool, or any other UI that reads + writes parachute-vault. Captures the patterns parachute-notes worked out in its first year so the next surface doesn't reinvent them.

## Who this is for

You're building a thing that talks to one or more parachute vaults from a browser, a server-side app, a mobile shell, a desktop client — anything that needs to authenticate as a writer, discover the operator's vault catalog, read notes, write notes, and stay sane across reconnects, offline windows, and concurrent edits.

Sibling reference: [`guides/multi-writer-workspace.md`](./multi-writer-workspace.md) covers conventions for *how the vault accumulates surfaces* (tag roles, scoped tokens, multi-writer auth, MCP basics, the operator's perspective). This guide is the *builder's* counterpart — same conventions, viewed from inside the surface code that connects to the vault.

Cite [`parachute-notes`](https://github.com/ParachuteComputer/parachute-notes) as the working prototype throughout: every pattern here is implemented at `src/lib/vault/` and tested. When in doubt about a corner case, read Notes' source. It's the spec until parachute-surface (the abstract SDK research direction, [`research/parachute-surface-direction.md`](../research/parachute-surface-direction.md)) lands.

## How to read this

1. **Mental model** — vault / hub / surface. Twelve lines.
2. **Authentication** — DCR + OAuth code-flow + PKCE + refresh rotation + scoped tokens.
3. **Vault discovery** — `/.well-known/parachute.json`, services catalog, multi-vault hubs.
4. **Reading the vault** — REST + MCP, query operators, cost knobs.
5. **Writing the vault** — OC precondition, atomic append/prepend, `content_edit`, batch, `validation_status`.
6. **Surface-declares-schema** — the patterns#57 pattern, with Notes' code.
7. **Cross-cutting concerns** — reachability, retry-with-backoff, auth-halt, offline, cross-tab sync.
8. **Reference worked examples** — minimal read-only dashboard, write with OC + autosave, schema-ensure on connect, offline-queued capture.
9. **Pointers to canonical references**.

You can read top-to-bottom or jump to whichever chapter matches the question in front of you. Cross-links keep the map together.

---

## 1. The mental model

Three layers. Each has one job:

- **Vault** ([`parachute-vault`](https://github.com/ParachuteComputer/parachute-vault)) — the data + content substrate. Notes, tags, links, schemas, indexed metadata. Stable shape; speaks REST and MCP.
- **Hub** ([`parachute-hub`](https://github.com/ParachuteComputer/parachute-hub)) — the portal + Authorization Server + service catalog. Hub-as-issuer mints the JWTs surfaces present to vault; hub-as-portal lets operators discover which vaults exist and which surfaces are available. The user-visible "front door" of a Parachute install.
- **Surface** — your code. Talks to vault for data and to hub for auth + discovery. Renders for humans.

Conventional flow when a new user opens your surface:

```
user clicks "Connect" →
  surface discovers AS via /.well-known/oauth-authorization-server →
  surface registers as an OAuth client (DCR; one-shot per browser per issuer) →
  surface redirects to hub authorize endpoint with PKCE →
  user consents on hub →
  hub redirects back with code →
  surface exchanges code for { access_token, refresh_token, vault, services } →
  surface saves token; uses access_token as Bearer on every vault call →
  401? exchange refresh_token for a new pair; retry once →
  refresh fails? surface marks vault auth-halted; user must re-consent
```

Surface code never talks to a "Parachute API" — it talks to vault and to hub, two different services that hub-as-issuer ties together at the auth boundary.

---

## 2. Authentication

### The OAuth 2.1 + PKCE + DCR shape

Three RFCs compose:

1. **OAuth 2.0 Authorization Server Metadata** (RFC 8414) — discover the AS endpoints. Hub serves `/.well-known/oauth-authorization-server`.
2. **Dynamic Client Registration** (RFC 7591) — register your surface as a client at `registration_endpoint`. One-shot per (issuer, redirect_uri) per browser; cache the resulting `client_id`. Notes caches in localStorage keyed by `(issuer, redirect_uri)` — see [`oauth.ts:68-77`](https://github.com/ParachuteComputer/parachute-notes/blob/main/src/lib/vault/oauth.ts).
3. **OAuth 2.1 + PKCE** (RFC 7636 S256) — the actual code flow. No client secret; PKCE is the proof-of-possession.

Refresh-token rotation per RFC 6749 §6: every successful refresh returns a new `refresh_token` that supersedes the prior one. Your surface must persist the rotated value or the next refresh will 400.

### Worked code: starting the flow

```ts
// surface/auth/begin.ts — adapted from parachute-notes/src/lib/vault/oauth.ts

const REDIRECT_PATH = "/oauth/callback";
const DEFAULT_SCOPE = "vault:read vault:write";

async function discoverAuthServer(issuerUrl: string) {
  const url = `${issuerUrl.replace(/\/$/, "")}/.well-known/oauth-authorization-server`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`Discovery failed: ${res.status}`);
  const meta = await res.json();
  // Required fields per RFC 8414 — fail loud if the AS is missing any.
  for (const k of ["issuer", "authorization_endpoint", "token_endpoint", "registration_endpoint"]) {
    if (!meta[k]) throw new Error(`AS metadata missing ${k}`);
  }
  if (!meta.code_challenge_methods_supported?.includes("S256")) {
    throw new Error("AS does not advertise S256 PKCE");
  }
  return meta;
}

async function registerClient(registrationEndpoint: string, redirectUri: string) {
  const res = await fetch(registrationEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    // `credentials: "include"` enables same-origin auto-approve (hub#199).
    credentials: "include",
    body: JSON.stringify({
      client_name: "My Surface",
      redirect_uris: [redirectUri],
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
    }),
  });
  if (!res.ok) throw new Error(`Registration failed: ${res.status}`);
  return (await res.json()) as { client_id: string };
}

async function generatePkce() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const verifier = base64UrlEncode(bytes);
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  const challenge = base64UrlEncode(new Uint8Array(hash));
  return { verifier, challenge };
}

export async function beginOAuth(issuerUrl: string) {
  const redirectUri = `${location.origin}${REDIRECT_PATH}`;
  const meta = await discoverAuthServer(issuerUrl);

  // Cache the client_id per (issuer, redirect_uri). DCR runs at most once.
  const cacheKey = `dcr:${meta.issuer}:${redirectUri}`;
  let clientId = localStorage.getItem(cacheKey);
  if (!clientId) {
    const reg = await registerClient(meta.registration_endpoint, redirectUri);
    clientId = reg.client_id;
    localStorage.setItem(cacheKey, clientId);
  }

  const { verifier, challenge } = await generatePkce();
  const state = base64UrlEncode(crypto.getRandomValues(new Uint8Array(16)));

  // Stash everything the callback handler will need in sessionStorage.
  sessionStorage.setItem("pendingOAuth", JSON.stringify({
    issuer: meta.issuer,
    tokenEndpoint: meta.token_endpoint,
    clientId,
    redirectUri,
    codeVerifier: verifier,
    state,
  }));

  const url = new URL(meta.authorization_endpoint);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("state", state);
  url.searchParams.set("scope", DEFAULT_SCOPE);
  location.href = url.toString();
}

function base64UrlEncode(bytes: Uint8Array): string {
  let s = ""; for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
```

### Worked code: completing the flow

Your callback route handles the redirect-back from hub:

```ts
// surface/routes/oauth-callback.ts — adapted from completeOAuth in oauth.ts:188

export async function handleCallback(searchParams: URLSearchParams) {
  const pending = JSON.parse(sessionStorage.getItem("pendingOAuth") ?? "null");
  if (!pending) throw new Error("No pending flow — start from the connect page");

  const code = searchParams.get("code");
  const state = searchParams.get("state");
  if (state !== pending.state) throw new Error("OAuth state mismatch");

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code: code!,
    code_verifier: pending.codeVerifier,
    client_id: pending.clientId,
    redirect_uri: pending.redirectUri,
  });

  const res = await fetch(pending.tokenEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status}`);

  const token = await res.json() as {
    access_token: string;
    refresh_token?: string;
    expires_in?: number;
    scope?: string;
    vault?: string;        // Hub-issued JWTs include the vault name claim.
    services?: Record<string, { url: string }>; // Service catalog — §3.
  };

  // Persist the access token, refresh token, and the per-vault metadata you
  // got back. You'll need pending.tokenEndpoint + pending.clientId again for
  // refresh, so save those too.
  saveToken(token.vault!, {
    accessToken: token.access_token,
    refreshToken: token.refresh_token,
    expiresAt: Date.now() + (token.expires_in ?? 3600) * 1000,
    services: token.services,
    tokenEndpoint: pending.tokenEndpoint,
    clientId: pending.clientId,
  });

  sessionStorage.removeItem("pendingOAuth");
  return token;
}
```

### Worked code: refresh-token rotation

When a vault call returns 401, exchange the refresh token for a fresh pair. Dedupe concurrent refreshes — refresh-token rotation means a second concurrent refresh would 400.

```ts
// surface/auth/refresh.ts — adapted from parachute-notes/src/lib/vault/refresh.ts

const inflight = new Map<string, Promise<string | null>>();

export async function forceRefresh(vaultId: string): Promise<string | null> {
  const existing = inflight.get(vaultId);
  if (existing) return existing;

  const promise = doRefresh(vaultId).finally(() => inflight.delete(vaultId));
  inflight.set(vaultId, promise);
  return promise;
}

async function doRefresh(vaultId: string): Promise<string | null> {
  const stored = loadToken(vaultId);
  if (!stored?.refreshToken) return null;

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: stored.refreshToken,
    client_id: stored.clientId,
  });

  const res = await fetch(stored.tokenEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!res.ok) {
    // 4xx → hub decided the token is bad. Mark auth-halted; the user must
    // reconnect. 5xx / network → transient; let the next call try again.
    if (res.status >= 400 && res.status < 500) {
      markAuthHalted(vaultId, "Vault session expired. Reconnect to resume syncing.");
    }
    return null;
  }

  const token = await res.json();
  saveToken(vaultId, {
    ...stored,
    accessToken: token.access_token,
    // CRITICAL: persist the rotated refresh_token. The old one is now invalid.
    refreshToken: token.refresh_token ?? stored.refreshToken,
    expiresAt: Date.now() + (token.expires_in ?? 3600) * 1000,
  });
  return token.access_token;
}
```

### Scope vocabulary

Per [`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md), the verb hierarchy is `vault:<name>:admin ⊇ vault:<name>:write ⊇ vault:<name>:read`. Hub-issued JWTs carry these on the `scope` claim.

Most read-only surfaces (dashboards) want `vault:<name>:read`. Capture surfaces (Notes, custom write tools) want `vault:<name>:read vault:<name>:write`. Admin tooling (token management, schema editors) wants `vault:<name>:admin`.

### Per-tag scoping (`scoped_tags`)

Orthogonal to the OAuth scope: a token can carry a `scoped_tags` allowlist that narrows the token to notes carrying allowlisted tags (or their sub-tags via `tags.parent_names` hierarchy). Full details in [`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md). Useful when your surface should only operate on one slice of a vault — e.g., a donor-pipeline-only dashboard gets a token with `scoped_tags: ["donor-pipeline"]` and can't accidentally read other notes.

Today `scoped_tags` is set at mint time via vault's `/admin/tokens` UI — your surface doesn't issue these itself, it just receives a token that's already been narrowed. The contract: out-of-scope reads return `404`, out-of-scope writes return `403`. Code the same recovery paths regardless of why a read 404'd.

---

## 3. Vault discovery

After authentication, your surface knows about *one* vault — the one whose name arrived on the `vault` claim. To support **multiple vaults from one hub** (the standard install), fetch `/.well-known/parachute.json` from the hub origin.

### Worked code: vault catalog

```ts
// surface/discovery/hub-vaults.ts — adapted from hub-discovery.ts:50

export interface HubVaultEntry {
  name: string;
  url: string;
  version: string;
  managementUrl?: string;
}

export async function fetchHubVaults(hubOrigin: string): Promise<HubVaultEntry[] | null> {
  const url = `${hubOrigin.replace(/\/$/, "")}/.well-known/parachute.json`;
  let res: Response;
  try {
    res = await fetch(url, { headers: { Accept: "application/json" } });
  } catch {
    return null; // Network failure → caller treats as "no list."
  }
  if (!res.ok) return null;

  const parsed = await res.json().catch(() => null);
  if (!parsed || !Array.isArray(parsed.vaults)) return null;

  return parsed.vaults.filter((v: any) =>
    typeof v.name === "string" && typeof v.url === "string" && typeof v.version === "string"
  );
}
```

### Services catalog on the token

Hub-issued JWTs also include a per-vault `services` object on the token response:

```json
{
  "access_token": "...",
  "vault": "team",
  "services": {
    "vault:team": { "url": "https://hub.example/vaults/team" },
    "scribe":     { "url": "https://hub.example/scribe" }
  }
}
```

Per `hub#247` (the per-vault catalog keys work), each vault gets a distinct `vault:<name>` key so multi-vault hubs don't collide. Read [`vault:${vault}`] when the token's `vault` claim names a specific vault; fall back to the collapsed `vault` entry on legacy hubs.

The services catalog is a one-shot — captured at OAuth completion, persisted alongside the token, used as the source of truth for which URL to hit. Don't re-derive it from the hub origin on every request.

---

## 4. Reading the vault

### REST + MCP — two surfaces, one substrate

Vault exposes both REST and MCP. REST is the bread-and-butter surface for browsers and scripts; MCP is the surface AI agents and MCP-aware clients connect to. The data model and verbs are identical — REST returns JSON; MCP returns the same shape via `tools/call`.

Notes uses REST exclusively (browsers don't speak MCP natively). A server-side surface that wants to host AI agents typically uses MCP. Pick whichever fits your runtime.

### Worked code: a minimal read client

```ts
// surface/vault/client.ts — adapted from parachute-notes/src/lib/vault/client.ts

interface ClientOptions {
  vaultUrl: string;
  accessToken: string;
  onAuthError?: () => Promise<string | null>;
  onReachability?: (signal: "healthy" | "unreachable", reason?: string) => void;
}

export class VaultClient {
  private token: string;

  constructor(private opts: ClientOptions) {
    this.token = opts.accessToken;
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    return this.requestWithRetry<T>(path, init, true);
  }

  private async requestWithRetry<T>(path: string, init: RequestInit, allowRetry: boolean): Promise<T> {
    const headers = new Headers(init.headers);
    headers.set("Authorization", `Bearer ${this.token}`);
    headers.set("Accept", "application/json");
    if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");

    let res: Response;
    try {
      res = await fetch(`${this.opts.vaultUrl}${path}`, { ...init, headers });
    } catch (err) {
      // Network-level failure: ECONNREFUSED, DNS, CORS pre-flight reject.
      this.opts.onReachability?.("unreachable", String(err));
      throw new VaultUnreachableError(0);
    }

    // 5xx = upstream is talking but unhealthy (vault restarting, proxy down).
    if (res.status >= 500) {
      this.opts.onReachability?.("unreachable", `HTTP ${res.status}`);
      throw new VaultUnreachableError(res.status);
    }

    // Any non-5xx means the vault answered. Reset reachability hysteresis.
    this.opts.onReachability?.("healthy");

    if ((res.status === 401 || res.status === 403) && allowRetry && this.opts.onAuthError) {
      const fresh = await this.opts.onAuthError();
      if (fresh) {
        this.token = fresh;
        return this.requestWithRetry<T>(path, init, false);
      }
      throw new VaultAuthError();
    }

    if (res.status === 409 || res.status === 428) {
      // 409 = baseline mismatch; 428 = baseline missing. Both recover via
      // refetch + retry — collapse into one error class. See §5 for OC.
      const body = await res.json().catch(() => ({}));
      throw new VaultConflictError(body);
    }

    if (!res.ok) throw new Error(`${init.method ?? "GET"} ${path} → ${res.status}`);
    if (res.status === 204) return undefined as T;
    return res.json();
  }

  queryNotes(params: URLSearchParams) {
    return this.request<Note[]>(`/api/notes?${params}`);
  }

  getNote(idOrPath: string, opts: { includeLinks?: boolean; includeAttachments?: boolean } = {}) {
    const p = new URLSearchParams({ id: idOrPath, include_content: "true" });
    if (opts.includeLinks) p.set("include_links", "true");
    if (opts.includeAttachments) p.set("include_attachments", "true");
    return this.request<Note>(`/api/notes?${p}`);
  }
}

export class VaultUnreachableError extends Error { constructor(public status: number) { super(); this.name = "VaultUnreachableError"; } }
export class VaultAuthError extends Error { constructor() { super(); this.name = "VaultAuthError"; } }
export class VaultConflictError extends Error {
  constructor(public body: { current_updated_at?: string; expected_updated_at?: string; message?: string }) {
    super(body.message ?? "Note was edited elsewhere");
    this.name = "VaultConflictError";
  }
}
```

### Query operators

`GET /api/notes` accepts (matching the MCP `query-notes` tool surface, [`core/src/mcp.ts:81`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/mcp.ts)):

- `tag` (or `tag[]=` for multiple) + `tag_match=any|all`.
- `exclude_tags`, `has_tags`, `has_links`.
- `path` (exact) / `path_prefix`.
- `search` — full-text.
- `metadata` — operator object on indexed fields: `?metadata[state][eq]=drafted&metadata[priority][gte]=5`. Operators: `eq | ne | gt | gte | lt | lte | in | not_in | exists`.
- `near` — graph neighborhood: `?near[note_id]=01J...&near[depth]=2`.
- `date_from` / `date_to` (filter on `created_at`); generalized `date_filter[field]=updated_at&date_filter[to]=...` for filtering on `updated_at` or any indexed metadata date field.
- `order_by` — bare indexed-field name (`priority`, not `metadata.priority`). Requires the field declared `indexed: true` on at least one tag the queried notes carry. Vault refuses non-indexed sorts.
- `sort=asc|desc`, `limit`, `offset`.

### Cost knobs

Three response shapes are cost-tunable per call:

- `include_content` — default `true` for single-note reads, `false` for list reads. Set `false` on list reads + frequent small edits to large notes (atomic `append` on a 50k-token transcript) — `byteSize` + `preview` are returned in place of full content.
- `include_links` — default `false`. Hydrates inbound + outbound links per note.
- `include_attachments` — default `false`. Includes attachment records.

The defaults are tuned for the common case (browser list, agent appending). Override deliberately when you need more or less.

---

## 5. Writing the vault

### Optimistic concurrency is the contract

`PATCH /api/notes/:idOrPath` requires either `if_updated_at` (the `updated_at` value you last read) or `force: true`. There is no "just write" path. See [`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md) for the full convention.

Two error shapes you must handle:

- **`409 Conflict`** — you sent `if_updated_at` but it doesn't match live state. Re-read, reconcile, retry. Body: `{ error_type, current_updated_at, your_updated_at, note_id, path, message }`.
- **`428 Precondition Required`** — you sent neither `if_updated_at` nor `force`. Almost always a bug-in-your-code. Body: `{ error_type, note_id, path, message }`.

Distinguish them: `428` says *you didn't try*; `409` says *you tried and lost the race*. A 428 means fix your code; a 409 means refetch and retry.

### Worked code: OC with autosave + reconcile

```ts
// surface/edit/save.ts

async function saveNote(client: VaultClient, noteId: string, draftContent: string) {
  // 1. Read the current note — get the baseline timestamp.
  const current = await client.getNote(noteId);

  // 2. PATCH with the baseline. The vault throws VaultConflictError if a
  //    concurrent write landed since we read.
  try {
    await client.request(`/api/notes/${encodeURIComponent(noteId)}`, {
      method: "PATCH",
      body: JSON.stringify({
        content: draftContent,
        if_updated_at: current.updated_at,
      }),
    });
  } catch (err) {
    if (err instanceof VaultConflictError) {
      // The note moved under us. Re-fetch + decide:
      // - For autosave on top of a stable doc: re-merge our diff into the
      //   fresh content, re-issue the PATCH. See Notes' editor code for the
      //   prose-merge logic (out of scope for vault).
      // - For human-confirmed save: surface the conflict to the user;
      //   they pick "overwrite" (re-PATCH with force: true) or "discard."
      throw err;
    }
    throw err;
  }
}
```

### Atomic `append` / `prepend`

For collaborative growth — every writer adds to one note — use `append` / `prepend` instead of `content`. They run as `content = content || ?` at SQL layer. Two concurrent appends both land; neither overwrites. **No `if_updated_at` required** for append-only / prepend-only updates ([`core/src/notes.ts:295-322`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/notes.ts)).

```ts
// Every team member contributes to a daily roll-up — no conflict possible.
await client.request(`/api/notes/${encodeURIComponent(noteId)}`, {
  method: "PATCH",
  body: JSON.stringify({ append: "\n- [Alice 14:32] Pricing question from prospect X." }),
});
```

`prepend` is frontmatter-aware: if the note opens with a `---\n...\n---\n` YAML block, the prepend lands *after* the closing fence so parsers expecting frontmatter at byte 0 still find it.

### `content_edit` — surgical find-and-replace

Mutually exclusive with `content` / `append` / `prepend`. Pass `{ content_edit: { old_text, new_text } }`. Errors if `old_text` is not found, or matches multiple times — add surrounding context to disambiguate. Useful when an agent wants to update a specific section of a long note without re-sending the whole body.

### Batch writes

Both `POST /api/notes` (create) and `PATCH /api/notes/:id` accept a batch shape: `{ notes: [...] }`. The whole batch runs in one SQLite transaction with BEGIN/COMMIT/ROLLBACK — mid-batch error rolls every prior insert back. Per-call cap: **`MAX_BATCH_SIZE = 500`** ([`core/src/notes.ts:150-157`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/notes.ts)). For seeding a vault with hundreds of notes (a one-shot import, a nightly sync), batch is the right shape — single-call writes for 500 notes complete in seconds.

### `validation_status` on the response

When you write a note tagged with a tag that declares schema fields (via `update-tag`), vault evaluates the write against the schema and attaches a `validation_status` field to the response. The status carries `errors`, `warnings`, and `schema_conflicts` arrays. Today validation is **advisory** — writes violating an enum or missing a required field succeed but ship a warning; opt-in strict mode is on the roadmap (vault#299).

Surface this in your UI when present. Notes surfaces validation_status via toast / inline indicator on save. Your dashboard should at minimum log it; ignoring `validation_status` is how multi-writer tag drift accumulates silently.

> Caveat: at time of writing the REST `PATCH /api/notes/:id` doesn't attach `validation_status` symmetrically with the MCP `update-note` tool — tracked at [`vault#287`](https://github.com/ParachuteComputer/parachute-vault/issues/287). Defensive code: check for both presence and absence.

---

## 6. The surface-declares-schema pattern (patterns#57)

> Vault is generic. Surfaces declare what they need.

Each surface that requires specific tags to function (i.e., your code queries `tag: "capture/text"` somewhere) should:

1. **Declare** its required schema in its own code — the declaration is the contract.
2. **Ensure idempotently** on first connect / first relevant action — call `update-tag` with the declarations; idempotent for already-correct rows.
3. **Expose an audit UI** comparing current vault state to declared state, with one-click fix.

This lets multiple surfaces coexist non-destructively on one vault. Notes is the first instance. See [`patterns#57`](https://github.com/ParachuteComputer/parachute-patterns/issues/57) for the full pattern; here's the implementation shape.

### Worked code: declaring + ensuring

```ts
// surface/schema/declaration.ts — adapted from parachute-notes/src/lib/vault/schema.ts

export interface RequiredTagDecl {
  name: string;
  description: string;
  parent_names?: string[];
}

export const MY_SURFACE_REQUIRED_SCHEMA = {
  tags: [
    { name: "capture", description: "Notes captured directly by the user." },
    { name: "capture/text",  parent_names: ["capture"], description: "Text capture." },
    { name: "capture/voice", parent_names: ["capture"], description: "Voice capture." },
  ] as const,
};
```

```ts
// surface/schema/ensure.ts — adapted from schema-ensure.ts:24

// Per-session guard. The `update-tag` calls are idempotent on the vault
// side (already-correct rows are no-op writes), but no need to round-trip
// if we already ensured this vault's schema in this session.
const ensuredVaults = new Set<string>();

export async function ensureMySchema(vaultId: string, client: VaultClient): Promise<void> {
  if (ensuredVaults.has(vaultId)) return;
  // Mark before async so concurrent invocations don't race into a double-fire.
  ensuredVaults.add(vaultId);

  try {
    // Sequential, not Promise.all — parents first so children resolve
    // `parent_names`. Vault PUT is permissive about ordering, but ordered
    // calls make failure modes clearer in logs.
    for (const decl of MY_SURFACE_REQUIRED_SCHEMA.tags) {
      await client.request(`/api/tags/${encodeURIComponent(decl.name)}`, {
        method: "PUT",
        body: JSON.stringify({
          description: decl.description,
          ...(decl.parent_names ? { parent_names: decl.parent_names } : {}),
        }),
      });
    }
  } catch (err) {
    // Roll back guard so a future call can retry. Schema-ensure is plumbing,
    // not user-actionable; don't rethrow. Log + continue.
    ensuredVaults.delete(vaultId);
    console.warn(`[schema-ensure] failed for vault ${vaultId}:`, err);
  }
}
```

### When to call `ensureMySchema`

Call it on the first vault-touching action that needs the schema in place — Notes calls it on first capture (the save path), not on app load. Two reasons:

- **Lazy.** A read-only session never needs to write tag schemas; deferring keeps the network footprint small.
- **Recoverable.** If schema-ensure fails (transient 5xx), the next capture retries.

For a write-heavy surface (a dashboard that always writes on user action), calling `ensureMySchema` once at app load is fine. The guard makes both shapes safe.

### Audit UI

The third leg of patterns#57: an audit screen that fetches `list-tags`, compares to the declaration, and offers one-click fix-up for missing rows. Notes hasn't shipped this yet (tracked at notes#129); for a Gitcoin-style dashboard, an audit panel in your settings view is a natural home. The audit query is just a `GET /api/tags` and a client-side diff against `MY_SURFACE_REQUIRED_SCHEMA`.

---

## 7. Cross-cutting concerns

The hard parts of surface-building Notes worked out from scratch. Capturing them here is the goal of this guide.

### Reachability — three-state machine

Vault unreachability has hysteresis. A single dropped packet shouldn't flip the banner to "down." Three states:

```
healthy → retrying → down
              ↘ (3rd consecutive failure)
healthy ← retrying  ← (any 2xx/4xx response)
healthy ← down      ← (any 2xx/4xx response)
```

Notes implements this as a Zustand store with an in-flight signal from the client ([`reachability-store.ts:79-123`](https://github.com/ParachuteComputer/parachute-notes/blob/main/src/lib/vault/reachability-store.ts)). The client passes every fetch outcome through `onReachability("healthy" | "unreachable", reason?)`:

- `2xx`, `4xx` → `healthy` (auth failure / not-found / conflict are still "vault answered").
- `5xx`, network failure → `unreachable`.

The store promotes through `healthy → retrying → down` on the 3rd consecutive failure. Recovery on any non-5xx response. Exponential backoff `[1s, 2s, 4s, 8s, 16s, 30s]` between probe attempts.

**Don't persist reachability state.** Reload should re-probe from scratch — a stale "down" verdict across sessions is a worse UX than a 200ms re-probe.

### Auth halt — distinct axis from reachability

When the refresh-token exchange returns 4xx (`invalid_grant`, revoked client, etc.), the user *must reconnect*. No probe schedule helps. Mark the vault auth-halted; surface a "Reconnect" banner; pause auto-retries until the user reconnects.

Notes uses a separate Zustand store (`auth-halt-store.ts`) that *is* persisted (the user's next session shouldn't silently retry a known-dead token). Reachability is transient; auth-halt is durable. Different stores, different semantics.

### Retry-with-backoff (and when not to retry)

React Query's default retry behavior — 3 retries with exponential backoff — is the wrong default for vault calls. The reasons:

- **Auth failures** (401/403) shouldn't retry once refresh is attempted and failed.
- **Conflicts** (409/428) shouldn't retry blindly — they need refetch-and-reconcile.
- **Reachability "down"** shouldn't burn retries while we know the vault is gone — wait for the probe to flip the state back.

Pattern: configure your data layer (React Query, SWR, manual) to honor your error classes:

```ts
// surface/queries/config.ts
queryClient.setDefaultOptions({
  queries: {
    retry: (failureCount, err) => {
      if (err instanceof VaultAuthError) return false;
      if (err instanceof VaultConflictError) return false;
      // VaultUnreachableError → let the reachability store decide.
      // Use a small cap; the store's recovery probe is the real loop.
      return failureCount < 1;
    },
    retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 4000),
  },
});
```

### Offline-first

Notes treats every write as a write-back: optimistically apply to local state, queue the network call, drain on reconnect. The queue lives in IndexedDB (via Dexie); the drain runs on a tick + on reachability `healthy` transitions.

The patterns here aren't vault-specific (any offline-first app has this shape), but two things matter for vault:

- **Use `force: true` on drain-time writes that have grown stale.** A queued PATCH from an hour ago wouldn't pass an OC check; rather than force the user to reconcile every offline edit, drain with `force: true` and accept that offline writes win over concurrent edits that landed while you were offline. Different orgs may want different policies — the API supports both shapes.
- **`append` is your friend.** Queued captures (Telegram bot, voice memo, mobile sync) are perfect for `append` — no concurrency check needed, drain order doesn't matter for correctness.

### Cross-tab sync

If your surface runs in multiple tabs at once (Notes' PWA does), use `BroadcastChannel` to invalidate caches when one tab writes. Notes broadcasts on every successful mutation; other tabs re-fetch the affected queries. See [`cross-tab-sync.ts`](https://github.com/ParachuteComputer/parachute-notes/blob/main/src/lib/vault/cross-tab-sync.ts) for the implementation.

### Error UX — be specific

Your surface UI should distinguish the failure modes:

- **`VaultUnreachableError`** → "Can't reach your vault right now. Retrying..." Banner + retry-now button. Don't say "Sign in" — auth isn't the problem.
- **`VaultAuthError` (post-refresh-failed)** → "Your vault session expired. Reconnect." Big, blocking. Refresh-token rotation drift; admin revoke. Manual reauth is the only path.
- **`VaultConflictError`** → "This note was edited elsewhere — refresh to see the latest." Inline near the affected note, not a global banner.
- **`VaultNotFoundError`** → "This note doesn't exist (anymore?)." Sometimes a genuine 404; sometimes a scoped-token out-of-scope read (vault returns 404 not 403 for these on purpose, to prevent existence-leak across the scope boundary — see [`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md) §Semantics).

---

## 8. Reference worked examples

### Minimal read-only dashboard

Read a list of notes by tag, render. ~25 lines.

```ts
// dashboard/page.ts
const token = loadToken("team");
const services = token.services;
const vaultUrl = services["vault:team"]?.url ?? services.vault?.url; // per-vault key + collapsed fallback

const client = new VaultClient({
  vaultUrl,
  accessToken: token.accessToken,
  onAuthError: () => forceRefresh("team"),
  onReachability: (s, r) => reportSignal("team", s, r),
});

const drafts = await client.queryNotes(new URLSearchParams({
  tag: "concept-seed",
  "metadata[state][eq]": "drafted",
  order_by: "priority",
  sort: "desc",
  limit: "20",
}));

renderDrafts(drafts);
```

### Write-flow with OC + autosave

The autosave loop on a single editable note.

```ts
// editor/autosave.ts
let lastSavedAt = note.updated_at; // From initial fetch

async function autosave(draftContent: string) {
  try {
    const updated = await client.request<Note>(`/api/notes/${encodeURIComponent(note.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ content: draftContent, if_updated_at: lastSavedAt }),
    });
    lastSavedAt = updated.updated_at;
  } catch (err) {
    if (err instanceof VaultConflictError) {
      // Concurrent write landed. Surface to user; offer "see latest" / "force overwrite."
      showConflictBanner({ current_updated_at: err.body.current_updated_at });
      return;
    }
    throw err;
  }
}

// Debounced trigger
let timer: ReturnType<typeof setTimeout>;
function onEdit(content: string) {
  clearTimeout(timer);
  timer = setTimeout(() => autosave(content), 1500);
}
```

### Schema-ensure on connect

Already covered in §6 — call `ensureMySchema(vaultId, client)` once per session, lazily on first write.

### Offline-queued capture

Skeleton: a write that queues to IndexedDB when offline, drains when reachability flips healthy.

```ts
// capture/queue.ts
async function captureNote(content: string, tags: string[]) {
  const draft = { id: ulid(), content, tags, metadata: {}, queuedAt: Date.now() };

  // Optimistic local insert.
  await queueDb.put(draft);
  invalidateLocalQueries();

  // Try immediate send; queue continues if it fails.
  void drainQueue();
}

async function drainQueue() {
  const pending = await queueDb.toArray();
  for (const draft of pending) {
    try {
      await client.request("/api/notes", {
        method: "POST",
        body: JSON.stringify({ content: draft.content, tags: draft.tags, metadata: draft.metadata }),
      });
      await queueDb.delete(draft.id);
    } catch (err) {
      if (err instanceof VaultUnreachableError || err instanceof VaultAuthError) return; // Wait for state change.
      // Permanent failure — surface to user, leave in queue for manual retry.
      console.error("[queue] permanent failure", err);
    }
  }
  invalidateLocalQueries();
}

// Drain on reachability healthy transition.
useVaultReachabilityStore.subscribe((s) => {
  if (Object.keys(s.byVault).length === 0) void drainQueue();
});
```

---

## 9. Pointers to canonical references

When this guide leaves a question open, these are the authorities:

- **[`parachute-vault/docs/HTTP_API.md`](https://github.com/ParachuteComputer/parachute-vault/blob/main/docs/HTTP_API.md)** — the REST surface, endpoint by endpoint. Note: as of 2026-05-13 this doc has stale sections; vault is tracking a refresh at vault#315. When in doubt, [`parachute-vault/src/routes.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/routes.ts) is the spec.
- **[`parachute-vault/core/src/mcp.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/mcp.ts)** — the MCP tool schemas. Same data model, MCP shape.
- **[`guides/multi-writer-workspace.md`](./multi-writer-workspace.md)** — operator's-side companion guide. Covers tag schemas, scoped tokens, multi-writer auth, the worked workspace setup.
- **[`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md)** — the per-tag-scope contract. How vault evaluates allowlists, what 403/404 means.
- **[`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md)** — the OC convention. Same shape on HTTP and MCP.
- **[`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md)** — the OAuth issuer architecture. Why your tokens carry the hub origin in their `iss` claim.
- **[`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md)** — the scope vocabulary (`vault:<name>:read|write|admin`).
- **[`research/parachute-surface-direction.md`](../research/parachute-surface-direction.md)** — where this is going. A first-party abstract surface layer is research, not shipped; today, every surface implements its own auth/discovery/state-management. Read this when you want to know what's coming.
- **[`parachute-notes/src/lib/vault/`](https://github.com/ParachuteComputer/parachute-notes/tree/main/src/lib/vault)** — the working prototype. When this guide leaves a corner ambiguous, read Notes' code.

## Honest caveats

- **No abstract surface SDK yet.** Today every surface implements its own auth client, query client, reachability state machine, schema-ensure path. Notes is the prototype; parachute-surface (the SDK direction) is research. If your team has bandwidth, the patterns above are stable enough to crib directly from Notes and adapt to your stack.
- **The HTTP_API.md doc has stale sections** as of this guide's writing. Vault's source is authoritative; the doc refresh is tracked.
- **`validation_status` parity** between REST and MCP is a known gap (vault#287). Code defensively.
- **Cross-origin DCR auto-approve** doesn't work yet (hub#201). Same-origin (surface served from hub's origin under a sub-path) works; truly cross-origin requires manual approve. Mostly invisible if your surface ships from a hub-served path.

## Feedback loop

If you build a surface and hit friction:

- Vault-substrate friction → file against [`parachute-vault`](https://github.com/ParachuteComputer/parachute-vault).
- Hub / auth / discovery friction → file against [`parachute-hub`](https://github.com/ParachuteComputer/parachute-hub).
- Cross-cutting convention questions → file against [`parachute-patterns`](https://github.com/ParachuteComputer/parachute-patterns).
- Cite the workflow, the writer (which role), why it matters. Real friction with a real use case attached moves items up priority lists.

When patterns emerge that should be folded into surface-direction or this guide, file against patterns — your surface's hard-won learnings become the next surface's documented shortcut.
