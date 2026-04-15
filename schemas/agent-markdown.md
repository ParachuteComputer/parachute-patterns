# Agent markdown schema

## Convention

One markdown file = one agent. YAML frontmatter describes how it fires and
what it can do; the body is the system prompt.

Canonical Zod schema:
[parachute-agents/src/agents.ts](https://github.com/ParachuteComputer/parachute-agents/blob/main/src/agents.ts).
That file is the authority — this doc summarizes it for reference and for
modules adopting the same schema (e.g. Prism's `skill-builder`).

## Shape

```yaml
---
name: <unique slug>
description: <human readable; used when exposing the agent via MCP>
trigger:
  type: webhook | cron | vault | manual
  # per-type fields below
model: <provider>/<model>        # e.g. anthropic/claude-sonnet-4-6
backend: vercel-ai | claude      # optional; overrides runner default
tools: [<built-in> | { mcp: {...} }, ...]
on_save:
  tags: [<string>, ...]
  path: <template>
---

System prompt body in markdown.
```

## Triggers

- **webhook** — `source: discord | slack | telegram | http | any`,
  `match: always | contains_url | regex:<pattern>`.
- **cron** — `schedule: "<cron expression>"`.
- **vault** — `on_event: created | updated`, optional
  `filter: { tags: [...], not_tags: [...] }`, `poll_seconds: >=10` (default 60;
  push-based firing is future work).
- **manual** — fires only via explicit invocation.

## Tools

Two forms in the same array:

```yaml
tools:
  - fetch_url             # string: built-in tool
  - vault                 # string: built-in tool
  - mcp:                  # object: attach an external MCP server
      name: some-service
      url: https://example.com/mcp
      auth:
        type: bearer
        token_env: SOME_SERVICE_TOKEN
```

MCP auth supports `bearer` (`token` or `token_env`) and `oauth`
(client-credentials grant via `client_id_env` / `client_secret_env` /
`token_url`). Non-http(s) URLs are rejected at parse time. See
`patterns/mcp-transport.md` for wire-level details.

## Backend

`vercel-ai` (default) routes through Vercel AI SDK + the runner's configured
provider. `claude` routes through `@anthropic-ai/sdk` Messages API, picking
up auth from `ParachuteAgentConfig.claudeAuth`. The markdown is identical in
both cases — only the inference path changes.

## Source options

Agent markdown maps (`path → string`) can come from:

- `loadAgentsFromDir(dir)` — filesystem
- `loadAgentsFromVault({ vault, tag })` — vault notes tagged
  `agent-definition` (default)
- `loadAgentsInline(map)` — hand-authored map

See `patterns/loadAgents.md` for the shared source convention.

## Rules

- Frontmatter must parse against `agentFrontmatterSchema` — no extra fields
  at the top level (zod will pass-through unknown keys, but new keys should
  be added to the schema first).
- Agent `name` must be unique within a runner. `loadAgents` throws on
  duplicates.
- `description` is required for any agent that will be exposed via MCP —
  it's what the caller sees when listing available agents.

## Adoption

Prism's `skill-builder` (Benjamin's project) covers similar ground. When
Prism adopts `@openparachute/agent` as its runner, this schema is the
handshake. Log schema extensions in `adoption/migration-notes.md` so we keep
both sides in sync.
