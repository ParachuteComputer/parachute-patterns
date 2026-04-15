# MCP transport

## Convention

Parachute-hosted MCP servers speak **Streamable HTTP** at `<base>/mcp` and
authenticate via bearer tokens over `Authorization: Bearer <pvt_...>`.

- Canonical example: `parachute-vault` serves its MCP at `<vault-url>/mcp`.
- Clients: agents in `@openparachute/agent` connect via
  `@modelcontextprotocol/sdk` + the Streamable HTTP transport. Source:
  [parachute-agents/src/vault.ts](https://github.com/ParachuteComputer/parachute-agents/blob/main/src/vault.ts).

## Why Streamable HTTP (not SSE)

- Supports bidirectional streaming over a single HTTP connection.
- Works behind most load balancers and serverless runtimes (Cloudflare
  Workers, fly machines) without special long-lived-connection handling.
- SSE is the legacy transport. Prefer Streamable HTTP for any new server.

## Auth shape

Two schemes supported by `@openparachute/agent`'s MCP tool entry. See
`schemas/agent-markdown.md` for the frontmatter spec.

### Bearer (static token)

```yaml
mcp:
  name: my-service
  url: https://svc.example.com/mcp
  auth:
    type: bearer
    token_env: MY_SERVICE_TOKEN     # or `token: <literal>` (discouraged)
```

### OAuth (client credentials)

```yaml
mcp:
  name: my-service
  url: https://svc.example.com/mcp
  auth:
    type: oauth
    client_id_env: MY_SERVICE_CLIENT_ID
    client_secret_env: MY_SERVICE_CLIENT_SECRET
    token_url: https://svc.example.com/oauth/token
    scope: "read write"
```

Runs the RFC 6749 `client_credentials` grant and caches the access token
per-server. PKCE, authorization_code, and refresh_token flows are out of
scope until an agent actually needs one.

## Rules

- **URLs must be http(s).** Non-http schemes (`file://`, etc.) are rejected
  at schema-parse time — an agent markdown file can't smuggle a bad
  transport into the client. See
  [parachute-agents/src/agents.ts](https://github.com/ParachuteComputer/parachute-agents/blob/main/src/agents.ts).
- **Never inline a token in the markdown** when the file is checked into a
  repo or stored in vault. Use `token_env` and supply the secret via the
  runner's environment.
- **Scope the token.** Follow `patterns/token-auth.md` — every Parachute
  token has a declared scope; MCP tokens typically have something like
  `vault:read` or `agent:invoke`.
- **Path convention.** Servers should mount MCP at `/mcp` (not `/api/mcp`,
  not `/v1/mcp`). Keeps client URLs uniform.

## Open questions

- Do we want an OAuth `authorization_code` + PKCE flow for user-scoped
  tokens (as opposed to service-scoped client_credentials)? Likely yes when
  a first end-user app on top of an agent lands. Not urgent.
