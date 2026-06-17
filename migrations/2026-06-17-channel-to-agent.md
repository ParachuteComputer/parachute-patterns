---
title: channel → agent rename
date: 2026-06-17
status: active
originating-pr: parachute-channel#TBD (channel→agent full rename) + parachute-hub#TBD (hub wire-up) + parachute-patterns#TBD (this file)
---

# channel → agent rename

The `parachute-channel` module (webhook fan-out + MCP bridge, port 1941) is renamed to **`parachute-agent`**. This is a **full clean rename**, not a soft-alias: the npm package, repo, service short name, OAuth scopes, HTTP mount, admin endpoints, vault tags, environment variables, and bin names all move from `channel` to `agent`. Aaron locked the scope (see "Decisions locked" below) and accepted brief breakage so this runs as a **coordinated cutover**, not a long expand-migrate-contract arc — with **one exception**: the vault `#channel-message` tag migrates via **dual-read** (read both old + new, write new, re-tag existing notes, re-register triggers) so no live note silently drops out of routing mid-flight.

The old, already-retired `parachute-agent` repo (the Claude-in-containers module retired 2026-05-20, see its [DEPRECATED.md](https://github.com/ParachuteComputer/parachute-agent/blob/main/DEPRECATED.md)) currently squats the `parachute-agent` GitHub name. It must be renamed to `parachute-agent-legacy` and **then** archived (archiving alone does **not** free the name) **before** `parachute-channel` can take the `parachute-agent` name.

This file is the propagation checklist. Each item is a checkbox + `repo:path` + a PR-number column (filled as items land). The **Execution sequence** section orders the PRs so nothing breaks mid-flight given hub merges go through Aaron. The **Needs Aaron's hand** section collects the human-gated steps (npm, GitHub repo-rename auth, relaunching his live agents, re-minting their tokens, the one-time vault re-tag).

## Decisions locked (Aaron)

- **Full clean rename** of wire surfaces — OAuth scopes `channel:*` → `agent:*`, accepting that his live agent tokens must be re-minted and the agents relaunched (hard cutover, no grace period on scopes).
- **HTTP mount** `/channel/*` → `/agent/*`, **with a redirect** from the old path for operator bookmarks.
- **Service / CLI name** becomes `agent` (`parachute start agent`), but **keep a `channel` install alias for one release cycle** so `parachute install channel` still resolves.
- **Connection sink module name** `channel` → `agent`.
- **Admin endpoint** `/admin/channel-token` → `/admin/agent-token` (old path redirects).
- **Vault tag** `#channel-message` → `#agent-message` migrated **now** via dual-read: read both, write new, re-tag existing notes, re-register triggers against the new tag.
- **Old retired `parachute-agent` repo** → rename to `parachute-agent-legacy`, then archive (frees the name), then rename `parachute-channel` → `parachute-agent`.
- **npm** — publish `@openparachute/agent`; deprecate `@openparachute/channel` with a message pointing at the new package.

## Scoping refinements (engineering calls within the locked decisions)

Two refinements made during planning (surfaced for override):

- **`metadata.channel` field stays — rename the TAG only this arc.** The locked decision is the *tag* rename (`#channel-message` → `#agent-message`). The note **metadata field** `channel` (the routing key, e.g. `metadata.channel === "<name>"`) is invisible internal plumbing; renaming it to `metadata.agent` doubles the data-migration surface (dual-read the field across daemon routing, vault transport, webhook parsing, transcript loading) for zero user-visible benefit. **Decision: keep `metadata.channel`; defer the field rename** to a possible later cleanup. The re-tag run copies tags only, not the field.
- **Scopes/`aud` get a transitional dual-accept, not a pure hard cutover.** Although a hard cutover was accepted, the agent daemon (resource server) will **accept BOTH `channel:*` and `agent:*` scopes AND both `aud: "channel"|"agent"`** during the transition window, so live agent tokens keep validating until re-minted at leisure. The hub flips to *minting* `agent:*` at cutover; a later **contract PR** drops the dual-accept once everything is re-minted. This keeps the daily-driver agents (uni-dev/evolve/weaver) working across the deploy instead of 401-ing the instant hub merges.

(Workspace `~/ParachuteComputer/CLAUDE.md` — the committed-core/exploration table + module references — is also in scope; the discovery sweep missed it due to one agent's emit-flake. Tracked under Doc references below.)

## Why this is risky despite being "just a rename"

The inventories surfaced several **live-config couplings** that make this more than a find-and-replace:

- **JWT audience + scopes are baked into issued tokens.** `admin-channel-token.ts` hardcodes `aud: "channel"` and mints `channel:read/send/admin`. Operator tokens in `~/.parachute/operator.token` carry `channel:send`. None of these auto-refresh — after the rename, stale tokens 401 / get `invalid_scope`. This is the hard cutover that drives the "re-mint Aaron's tokens" task.
- **`OPTIONAL_MODULE_SCOPES` gating** advertises `channel:send` only when the module is installed (the hub#489 regression class). The gate must move to check the `agent` module + `agent:send`, or vault-only hubs over-advertise `agent:send`.
- **Sink-specific reply-path setup** lives in exactly one place: `prepareChannelSink()` fenced on `sink.module === "channel"`. Missing the fence rename silently breaks agent connections.
- **`services.json` / vault connection state** store `manifestName: "parachute-channel"` and `sink.module: "channel"`. Legacy rows won't auto-upgrade; they go invisible to routing without a migration. The `shortNameForManifest` reverse-map must learn `parachute-agent → agent`.
- **MCP install-command text** is embedded in the admin UI (`claude mcp add ... channel-${name} .../channel/mcp/${name}`). New connections render `agent-*`; connections already in the DB carry stale copyable text → operators copying old UI get 404 unless re-linked.
- **`#channel-message` is the highest-impact single change** — it spans vault schema declarations, triggers, inbound/outbound filtering, the connection template's source filter, and notes-UI queries. This is the one surface getting dual-read rather than hard cutover.

## Execution sequence

The constraint: **hub PRs merge through Aaron**, and channel↔hub are coupled (hub's `service-spec.ts`, scope gating, sink fence, and admin endpoint all reference the module). Land in this order so the tree is never broken between merges.

1. **Free the name (Aaron-gated, GitHub).** Rename retired `parachute-agent` → `parachute-agent-legacy`; confirm it's archived. The `parachute-agent` name is now free. *(No code; pure GitHub admin — see Needs Aaron's hand.)*

2. **patterns PR (this file + doc refs).** Land `migrations/2026-06-17-channel-to-agent.md` plus the patterns doc references (naming/repos, naming/bins, canonical-ports, oauth-scopes, the design/migration docs). Patterns is doc-only and merges freely; landing it first gives every downstream PR a canonical reference and updates `audit-canonical-refs.sh`'s now-ambiguous `parachute-agent` exclusion *before* the new agent module exists. **Critical sub-item:** update `scripts/audit-canonical-refs.sh` (line ~88) — it currently excludes `parachute-agent` to skip the *retired* module; after the rename that exclusion would hide the *new* module. Make it specific (exclude `parachute-agent-legacy` / `parachute-agent/DEPRECATED`, not bare `parachute-agent`).

3. **channel repo: rename in place, still publishing as `@openparachute/channel`.** Do the full in-repo rename (package name, bins, `module.json`, scopes in `auth.ts`, MCP capability/notification strings in `bridge.ts`, paths in `mcp-http.ts`, env vars, vault transport tags with **dual-read**, README/CLAUDE/design docs, 42 test files). **Publish `@openparachute/agent` from this PR's merge.** At this point the new package exists on npm but hub doesn't route to it yet — harmless, nothing in the install path points at it.

4. **GitHub repo rename (Aaron-gated).** Rename `parachute-channel` → `parachute-agent`. GitHub auto-redirects the old slug, but update the local checkout's remote and `gh repo set-default`. *(See Needs Aaron's hand.)*

5. **hub PR (the wire-up + cutover) — Aaron merges.** This is the load-bearing PR; it must land as **one coherent PR** so hub is never half-renamed:
   - `service-spec.ts`: rename `SERVICE_SPECS["channel"]` key → `agent`; package `@openparachute/agent`; `manifestName: parachute-agent`; `canonicalPaths: ["/agent"]`; `startCmd: ["parachute-agent"]`; **plus** the one-cycle `channel` install alias in `KNOWN_MODULES` / install resolution so `parachute install channel` still resolves to agent.
   - Rename `admin-channel-token.ts` → `admin-agent-token.ts`: `CHANNEL_TOKEN_SCOPES` → `agent:read/send/admin`; `aud: "channel"` → `aud: "agent"`; endpoint `/admin/channel-token` → `/admin/agent-token`.
   - `hub-server.ts`: route `/admin/channel-token` → `/admin/agent-token` **with a 301 redirect** from the old path; dispatch-table + header docstring comments.
   - `oauth-handlers.ts`: scope-prefix alias map `["channel:", "parachute-channel"]` → `["agent:", "parachute-agent"]`; comments/display text.
   - `scope-explanations.ts`: rename `channel:send` key → `agent:send`, label "Channel" → "Agent"; move the `OPTIONAL_MODULE_SCOPES` gate to the `agent` module.
   - `admin-connections.ts`: `prepareChannelSink` → `prepareAgentSink`; fence `sink.module === "channel"` → `"agent"`; webhook `/channel/api/vault/inbound` → `/agent/api/vault/inbound`; MCP-add text `channel-${name}` / `/channel/mcp/` → `agent-*`; `#channel-message` source filters → `#agent-message`.
   - `connections-store.ts`, `origin-check.ts`, `module-manifest.ts`, `api-modules.ts`, `api-modules-ops.ts`, `serve-boot.ts`, `web/ui` (Connections.tsx label + api.ts fallback): comments/paths/labels.
   - `service-spec.ts` `shortNameForManifest` reverse-map learns `parachute-agent → agent`.
   - **All hub test files** (see hub Tests section) — including snapshot regen for `oauth-handlers.test.ts` consent screens.
   - README port table; `help.ts` short-name list; `CLAUDE.md`.

6. **Live cutover (Aaron's hand, after hub merge + restart).** Re-mint Aaron's operator/agent tokens, relaunch his live agents, run the one-time vault re-tag. *(See Needs Aaron's hand.)*

7. **npm deprecation (Aaron's hand).** `npm deprecate @openparachute/channel "renamed to @openparachute/agent"`.

8. **Site docs PR** (`parachute.computer`) — doc-only, can land any time after step 2; ordering-independent because it's reference material, not code.

Why this order is safe: the new npm package and renamed channel repo (steps 3–4) are inert until hub routes to them (step 5). The `channel` install alias (step 5) keeps the old install verb alive for one cycle so operators mid-upgrade aren't stranded. The vault tag's dual-read (in step 3's transport rename) means the re-tag run (step 6) can happen *after* hub cutover without dropping notes in the window.

## Code references

### parachute-channel → parachute-agent (the module repo)

- [ ] `package.json` — `name: @openparachute/channel` → `@openparachute/agent`; bins `parachute-channel`, `parachute-channel-bridge` → `parachute-agent`, `parachute-agent-bridge`. *(PR: )*
- [ ] `.parachute/module.json` `name` — `"channel"` → `"agent"` (the short name hub routing + admin APIs resolve). *(PR: )*
- [ ] `.parachute/module.json` `paths` — `["/channel"]` → `["/agent"]` (hub proxy mount). *(PR: )*
- [ ] `.parachute/module.json` `scopes` — `channel:read/write/send/admin` → `agent:read/write/send/admin`. *(PR: )*
- [ ] `.parachute/module.json` `uiUrl`/`configUiUrl` — `/channel/home`, `/channel/admin` → `/agent/*`. *(PR: )*
- [ ] `.parachute/module.json` tag schema — `#channel-message`, `#channel-message/inbound`, `#channel-message/outbound` → `#agent-message*`. **Dual-read during migration window.** (`metadata.channel` field unchanged — see Scoping refinements.) *(PR: )*
- [ ] `.parachute/module.json` `displayName`/`tagline` — Channel → Agent. *(PR: )*
- [ ] `src/auth.ts` — `SCOPE_READ/WRITE/SEND/ADMIN = "channel:*"` → `"agent:*"` (validated against JWTs). *(PR: )*
- [ ] `src/bridge.ts` — MCP notification methods `notifications/claude/channel*` → `.../agent`; capability string `claude/channel` → `claude/agent`. *(PR: )*
- [ ] `src/mcp-http.ts` — endpoint paths `/mcp/<name>`, `/.well-known/oauth-protected-resource/mcp/<name>`, `/.well-known/oauth-authorization-server/mcp/<name>` (hub proxies `/agent/mcp/*`). *(PR: )*
- [ ] `src/transports/vault.ts` — tag names `#channel-message/inbound|outbound`; query predicates + note-tagging logic → `#agent-message/*`. **Dual-read.** (`metadata.channel` field stays.) *(PR: )*
- [ ] `src/provision-channel.ts` — vault connection provisioning: trigger def, filter predicates `has_metadata: ["channel"]`, `missing_metadata: ["channel_inbound_rendered_at"]` → agent equivalents. (Consider renaming file → `provision-agent.ts`.) *(PR: )*
- [ ] `src/daemon.ts` — inbound webhook `/api/vault/inbound` routes by `note.metadata.channel`; error messages; transcript-loading logic by channel name → agent. *(PR: )*
- [ ] `src/**/*.ts` — console/debug output, comments, UI labels naming the "channel" daemon/service. *(PR: )*
- [ ] Env vars (runtime, in `bridge.ts` / daemon / launcher / `spawn-agent.ts`): `PARACHUTE_CHANNEL_URL`, `_STATE_DIR`, `_TOKEN`, `_PORT` → `PARACHUTE_AGENT_*`. *(PR: )*
- [ ] Bin/launcher/e2e invocations of `parachute-channel`, `parachute-channel-bridge` by name. *(PR: )*
- [ ] `--dangerously-load-development-channels=server:parachute-channel` (Claude Code CLI discovery flag) → `server:parachute-agent`. *(PR: )*
- [ ] `.mcp.json` MCP server config name `parachute-channel` → `parachute-agent`. *(PR: )*

### parachute-hub

- [ ] `src/service-spec.ts` — `SERVICE_SPECS["channel"]` key → `agent`; `package: @openparachute/agent` (line ~462); `manifestName: parachute-agent` (line ~463); `canonicalPaths: ["/agent"]` (line ~472); `startCmd: ["parachute-agent"]` (line ~480); short/displayName/tagline; comments. *(PR: )*
- [ ] `src/service-spec.ts` — add **one-cycle `channel` install alias** so `parachute install channel` resolves to agent (`KNOWN_MODULES` / install resolution). *(PR: )*
- [ ] `src/service-spec.ts` `shortNameForManifest` reverse-map (line ~845) — learn `parachute-agent → agent`; ensures legacy `parachute-channel` rows in `services.json` resolve during the upgrade window. *(PR: )*
- [ ] `src/admin-channel-token.ts` → rename `src/admin-agent-token.ts` — `CHANNEL_TOKEN_SCOPES` → `agent:read/send/admin`; `aud: "channel"` → `aud: "agent"` (line ~35); endpoint `/admin/channel-token` → `/admin/agent-token`. *(PR: )*
- [ ] `src/hub-server.ts` — route `pathname === "/admin/channel-token"` → `/admin/agent-token` (line ~2736); **301 redirect** old → new; dispatch-table + header docstring comments. *(PR: )*
- [ ] `src/oauth-handlers.ts` — scope-prefix alias `["channel:", "parachute-channel"]` → `["agent:", "parachute-agent"]`; comments/display text (lines ~410, 892, 896). *(PR: )*
- [ ] `src/scope-explanations.ts` — rename key `channel:send` → `agent:send`, label "Channel" → "Agent" (line ~22); move `OPTIONAL_MODULE_SCOPES` gate to `agent` module (lines ~48–52). `scopeIsAdmin()` (line ~281) is generic — no change. *(PR: )*
- [ ] `src/admin-connections.ts` — `prepareChannelSink` → `prepareAgentSink`; fence `sink.module === "channel"` → `"agent"` (line ~699); webhook `/channel/api/vault/inbound` → `/agent/api/vault/inbound`; MCP-add text `channel-${name}` + `/channel/mcp/` → `agent-*` (line ~1743); `#channel-message` source filters → `#agent-message`. *(PR: )*
- [ ] `src/connections-store.ts` — sink module `'channel'` label → `'agent'`. *(PR: )*
- [ ] `src/module-manifest.ts` — comment example `channel.message.deliver -> channel:send` → `agent.message.deliver -> agent:send` (lines ~127, 780). *(PR: )*
- [ ] `src/origin-check.ts` — legacy `/admin/channel-token` comment (line ~196). *(PR: )*
- [ ] `src/api-modules.ts` — inline docs/comments; `/channel/admin/` → `/agent/admin/`, `/channel/ui/` → `/agent/ui/`. *(PR: )*
- [ ] `src/api-modules-ops.ts` — `parseModulesPath` comment example `s/channel/agent/`. *(PR: )*
- [ ] `src/commands/serve-boot.ts` — comments mentioning `/channel/*` routes. *(PR: )*
- [ ] `src/commands/install.ts` — verify short name `agent` (+ the `channel` alias) used consistently in install flow. *(PR: )*
- [ ] `src/help.ts` — `channel   parachute-channel daemon` → `agent   parachute-agent daemon`. *(PR: )*
- [ ] `web/ui/src/routes/Connections.tsx` — MCP label "channel" → "agent"; form placeholder example filter `#channel-message/inbound` → `#agent-message/inbound` (line ~657). *(PR: )*
- [ ] `web/ui/src/lib/api.ts` — `getHostAdminToken` fallback endpoint comment `/admin/channel-token` → `/admin/agent-token` (~line 724). *(PR: )*
- [ ] `README.md` — port table `1941 | parachute-channel` → `1941 | parachute-agent`. *(PR: )*
- [ ] `CLAUDE.md` — "Short names" section + architecture refs `s/channel/agent/`. *(PR: )*
- [ ] `CHANGELOG.md` — historical entries are immutable (no edit); new entry records the rename + `agent:*` scopes + `/agent/*` paths. *(PR: )*

### Data: vault tag + metadata migration (dual-read)

The `#channel-message` tag spans vault schema, triggers, filters, and notes-UI. This is the **dual-read** surface — read both old + new, write new, re-tag existing notes, re-register triggers. (The `metadata.channel` routing field is unchanged this arc — see Scoping refinements.)

- [ ] channel repo `src/transports/vault.ts` + `src/provision-channel.ts` + `src/daemon.ts` — emit/query `#agent-message*`; **accept both** old + new tags on read during the window. *(PR: )*
- [ ] hub `src/admin-connections.ts` — trigger registration `action.webhook /agent/api/vault/inbound`; connection template source filter `#channel-message/inbound` → `#agent-message/inbound`. *(PR: )*
- [ ] Vault `connectionTemplates[]` entry referencing `#channel-message` tag schema — update in lockstep with hub admin-connections (coordinate vault manifest + hub). *(PR: )*
- [ ] **One-time re-tag run** against the live vault: re-tag existing `#channel-message*` notes → `#agent-message*`, re-register triggers on the new tag. (`metadata.channel` left as-is.) *(Aaron's hand — see Needs Aaron's hand.)*

### Tests

- [ ] **parachute-agent (was channel):** all 42 `src/**/*.test.ts` — scope/path/tag/metadata/env-var assertions; bin names; capability/notification strings. *(PR: )*
- [ ] `hub src/__tests__/admin-channel-token.test.ts` → rename `admin-agent-token.test.ts` — update imports, scope assertions (`channel:read/send/admin` → `agent:*`), `aud: channel` → `aud: agent` JWT claim, endpoint paths. *(PR: )*
- [ ] `hub src/__tests__/admin-connections.test.ts` — line 166 manifestName; lines 191/259/266/318/743/798 `#channel-message/inbound` → `#agent-message/inbound`; line 670 `requested_by`; lines 724–764 agent-backed connection assertions; line 767 MCP add cmd; line 794 webhook; line 1028 scopes. *(PR: )*
- [ ] `hub src/__tests__/admin-module-token.test.ts` — lines 287/294/306 manifestName + scope assertions. *(PR: )*
- [ ] `hub src/__tests__/oauth-handlers.test.ts` — lines 120/172/183/210/238 `channel:send` → `agent:send`; lines 995/1038/1061/1079/1108/1133/1163 consent-screen expected scopes (**snapshot regen**). *(PR: )*
- [ ] `hub src/__tests__/scope-explanations.test.ts` — line 22 key; lines 99/136 assertions. *(PR: )*
- [ ] `hub src/__tests__/module-manifest.test.ts` — lines 34–64 connectionTemplates (`#channel-message/inbound`, "Link a channel" description, module name); lines 80–97 similar. *(PR: )*
- [ ] `hub web/ui/src/routes/Connections.test.tsx` — line 60 comment; line 64 `module:'channel'`; lines 73/230/258 `#channel-message`; lines 140/150/165/167 var `channel-eng` → `agent-eng`; lines 238/267/300/309/352 connection IDs; line 241 MCP add cmd. *(PR: )*
- [ ] `hub web/ui/src/routes/Modules.test.tsx` — line 365 name; line 366 `config_ui_url /channel/admin`; line 377 href; lines 390–399 module names + URLs. *(PR: )*
- [ ] `hub src/__tests__/admin-lock.test.ts` — line 24 import from `admin-agent-token`; line 244 endpoint. *(PR: )*
- [ ] `hub src/__tests__/api-modules.test.ts` — line 319 module name; lines 633–665 fixture paths/URLs; line 683 `config_ui_url`; line 685 `management_url`. *(PR: )*
- [ ] `hub src/__tests__/api-modules-ops.test.ts` — line 216 `parseModulesPath` example; line 1035 `/api/modules/agent/`; lines 1054–1058 module-name assertion. *(PR: )*
- [ ] `hub src/__tests__/admin-vaults.test.ts` — line 1005 scope `channel:send` → `agent:send`. *(PR: )*
- [ ] `hub src/__tests__/expose.test.ts` — lines 1138–1141 module name + health path. *(PR: )*
- [ ] `hub src/__tests__/operator-token.test.ts` — line 84 scope assertion. *(PR: )*
- [ ] `hub src/__tests__/resource-binding.test.ts` — lines 86/95/105 scope refs. *(PR: )*
- [ ] `hub src/__tests__/serve-boot.test.ts` — lines 308/328/375/397 module-name assertion. *(PR: )*
- [ ] `hub src/__tests__/setup.test.ts` — line 124 service entry name. *(PR: )*
- [ ] `hub src/__tests__/status.test.ts` — lines 229–230 `urlFor` argument. *(PR: )*
- [ ] `hub web/ui/src/routes/Home.test.tsx` — line 277 `management_url` path. *(PR: )*

## Doc references

### parachute-patterns

- [ ] `naming/repos.md` (line 20) — `ParachuteComputer/parachute-channel` → `parachute-agent`. *(PR: )*
- [ ] `naming/bins.md` (line 30) — `@openparachute/channel` → `@openparachute/agent`; `parachute-channel`, `parachute-channel-bridge` → `parachute-agent`, `parachute-agent-bridge` (secondary bin follows `parachute-<module>-<role>`). *(PR: )*
- [ ] `patterns/canonical-ports.md` (lines 31, 41, 101–103) — port 1941 entry `parachute-channel` → `parachute-agent` (**port 1941 stays**, only the name changes); resolve the line-101–103 open question (1941 is *assigned to parachute-agent*, not freed — the module is being renamed, not retired). *(PR: )*
- [ ] `patterns/oauth-scopes.md` (lines 12, 32, 82, 207) — `channel:send` → `agent:send` in scope table, non-vault scope list, non-inheritance note, where-applies; service namespace `vault, scribe, channel, hub` → `vault, scribe, agent, hub`. *(PR: )*
- [ ] `patterns/well-known-discovery-rfc.md` (line 103) — module list `parachute-scribe, parachute-channel, future modules` → `parachute-scribe, parachute-agent, future modules`. *(PR: )*
- [ ] `patterns/module-json-extensibility.md` (line 439, lines 436–444) — `#channel-message/inbound` → `#agent-message/inbound`; module self-description name field + events/actions. *(PR: )*
- [ ] `patterns/post-merge-hygiene.md` (line 83) — link/reference `parachute-channel` → `parachute-agent`. *(PR: )*
- [ ] `research/auth-architecture-shape.md` (lines 57, 63, 165) — operator-token hard-coded scope list `channel:send` → `agent:send` (3 occurrences). *(PR: )*
- [ ] `adoption/migration-notes.md` (lines 127, 1096, 1132, 1216, 1375, 1401) — all `parachute-channel` → `parachute-agent`; add a dated entry for this rename. *(PR: )*
- [ ] `design/2026-06-09-modular-ui-architecture.md` (lines 4, 20–21, 30, 60, 66, 68) — module-architecture refs + descriptive "channel" → "agent"; line 68 connection filter `#channel-message/inbound` → `#agent-message/inbound`. *(PR: )*
- [ ] `migrations/2026-06-09-modular-ui.md` (lines 17, 24, 68, 97–99, 110–112, 119, 122–123, 127–128) — all "channel" → "agent" incl. "manage channels" → "manage agents"; line 111 tag filter. *(PR: )*
- [ ] `migrations/2026-06-09-hub-module-boundary.md` (lines 220, 245, 266, 291, 299) — `/admin/channels`, `/admin/channel-token`, `admin-channels.ts` → `/admin/agents`, `/admin/agent-token`, `admin-agents.ts`. *(PR: )*
- [ ] `migrations/2026-06-04-cla-rollout.md` (line 62) — Tier 3 list `parachute-channel` → `parachute-agent`. *(PR: )*
- [ ] `scripts/rollout-cla.sh` (line 33) — list entry `parachute-channel` → `parachute-agent`. *(PR: )*
- [ ] `scripts/audit-canonical-refs.sh` (line ~88) — **the exclusion that's now ambiguous.** It excludes `parachute-agent` to skip the *retired* module; after this rename that hides the *new* module. Make specific: exclude `parachute-agent-legacy` / `parachute-agent/DEPRECATED`, not bare `parachute-agent`. *(PR: )*
- [ ] `README.md` (line 7) — module list `Scribe, Narrate, Channel, Agents` → dedup/rephrase (`Scribe, Narrate, Agent, …` — note the *new* Agent replaces both "Channel" and the now-legacy "Agents"). *(PR: )*

### parachute.computer (site + design docs)

- [ ] `design/2026-04-20-module-architecture.md` (line 41) — module-name list `channel` → `agent`. *(PR: )*
- [ ] `design/2026-04-20-module-architecture.md` (line 272) — SERVICE_SPECS example `vault/notes/scribe/channel` → `vault/notes/scribe/agent`. *(PR: )*
- [ ] `design/2026-04-20-module-architecture.md` (lines 168, 211) — scope example `channel:send` → `agent:send`. *(PR: )*
- [ ] `design/2026-04-20-hub-as-portal-oauth-and-service-catalog.md` (line 42) — consent-UI scope example `channel:send` → `agent:send`. *(PR: )*
- [ ] `design/2026-05-21-parachute-runner-design.md` (line 307) — conditional-triggers ref `parachute-channel` → `parachute-agent`. *(PR: )*
- [ ] `design/2026-05-21-parachute-runner-design.md` (line 207) — port table `channel 1941` → `agent 1941`. *(PR: )*
- [ ] `design/2026-05-21-parachute-surface-design.md` (line 385) — port table `channel 1941` → `agent 1941`. *(PR: )*

### Workspace docs

- [ ] Workspace `CLAUDE.md` — committed-core/explorations table: `parachute-channel` row (exploration — may retire) → `parachute-agent`; note the rename + that the old retired `parachute-agent` is now `parachute-agent-legacy`. Disambiguate from the 2026-05-20 retired-agent paragraph so future readers don't conflate the two. *(local edit — workspace root is not a git repo)*

### Do-NOT-touch (false positives — generic English "channel")

These use "channel" as an ordinary word, **not** the module — leave them alone:

- `parachute.computer/CLAUDE.md:105`, `multi-user-phase-1.md:168`, `vault-as-git-canonical-thought-experiment.md:92` — communication/sync/auth "channel".
- `parachute.computer/.../hub-as-supervisor-unification.md:202,208` — npm/bun distribution "channel" (`@openparachute/hub@<channel>` semver tag placeholder).
- hub `CHANGELOG.md` historical entries — immutable record; no past-tense edits.

## Operator-facing references

- [ ] `parachute-agent/README.md` (was channel) — daemon/bridge naming, MCP server config example, env vars `PARACHUTE_CHANNEL_*` → `PARACHUTE_AGENT_*`. *(PR: )*
- [ ] `parachute-agent/CLAUDE.md` (was channel) — all refs, env-var docs, the `--dangerously-load-development-channels=server:parachute-channel` flag → `server:parachute-agent`. *(PR: )*
- [ ] hub `README.md` port table — see Code references. *(PR: )*
- [ ] hub admin UI MCP-add copy text — see `admin-connections.ts`. New connections render `agent-*`; **existing DB connections carry stale copyable text** — operators copying old UI text 404. Decide: rewrite/re-link stale connections, or document the re-link step in release notes. *(PR: )*

## External references

- [ ] npm: **publish `@openparachute/agent`** (from the channel-repo rename PR merge). *(Aaron's hand — see below.)*
- [ ] npm: **deprecate `@openparachute/channel`** → message points at `@openparachute/agent`. *(Aaron's hand.)*
- [ ] GitHub: rename retired `parachute-agent` → `parachute-agent-legacy`, confirm archived (frees the name). *(Aaron's hand.)*
- [ ] GitHub: rename `parachute-channel` → `parachute-agent` (auto-redirects old slug; update local remote + `gh repo set-default`). *(Aaron's hand.)*
- [ ] GitHub: repo description for new `parachute-agent` names it correctly (and not the retired containers module). *(low priority)*

## Needs Aaron's hand

Human-gated steps that the propagation PRs cannot do themselves. Ordered to match the **Execution sequence**.

1. **Free the GitHub name (sequence step 1).** Rename the *retired* `parachute-agent` repo → `parachute-agent-legacy`, then confirm it's archived. **Archiving alone does not free the name** — the rename is the load-bearing action. Must happen before the channel repo can take `parachute-agent`.
2. **npm publish `@openparachute/agent` (after sequence step 3 merges).** Publish the renamed package. The hub `startCmd: ["parachute-agent"]` and the `parachute-agent` bin in `package.json` must line up, or supervised boot fails with "command not found."
3. **GitHub rename `parachute-channel` → `parachute-agent` (sequence step 4).** GitHub auto-redirects the old slug; afterward update the local checkout's `origin` remote and run `gh repo set-default`.
4. **Re-mint live tokens (sequence step 6, after hub merge + restart).** This is the **hard cutover** — tokens minted pre-rename carry `aud: "channel"` + `channel:*` scopes and will 401 / `invalid_scope` against `@openparachute/agent`. Re-mint:
   - the operator token (carries `channel:send`) → new `agent:send`;
   - per-agent tokens for the live agents **uni-dev**, **evolve**, **weaver** (the `/admin/agent-token` mint replaces the old `/admin/channel-token`).
5. **Relaunch the live agents (sequence step 6).** Restart **uni-dev**, **evolve**, **weaver** so they pick up the new `PARACHUTE_AGENT_*` env vars, the `/agent/mcp/*` MCP endpoints, the `agent-*` MCP server name, and the freshly-minted `agent:*` tokens. Active sessions on old `channel:*` tokens won't survive.
6. **One-time vault re-tag (sequence step 6).** Against the live vault: re-tag existing `#channel-message*` notes → `#agent-message*` and re-register the inbound/outbound triggers on the new tag. (`metadata.channel` is left unchanged — see Scoping refinements.) Dual-read in the agent daemon keeps old-tagged notes routing until this run completes, so it can lag the hub cutover without dropping messages — but it should run before the dual-read accept-both path is removed in a later cycle.
7. **npm deprecate `@openparachute/channel` (sequence step 7).** `npm deprecate @openparachute/channel "renamed to @openparachute/agent — see https://www.npmjs.com/package/@openparachute/agent"`.

## Cross-references

- [`../patterns/canonical-ports.md`](../patterns/canonical-ports.md) — port 1941 stays assigned; only the name changes.
- [`../patterns/oauth-scopes.md`](../patterns/oauth-scopes.md) — the `channel:*` → `agent:*` scope rename.
- [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — run after each PR lands to catch missed propagations; **its `parachute-agent` exclusion must be made specific in this migration** or it will hide the new module.
- [`../patterns/governance.md`](../patterns/governance.md) — review discipline; every PR here (incl. doc-only) gets a reviewer pass.
- [`2026-06-09-hub-module-boundary.md`](./2026-06-09-hub-module-boundary.md) — names the `/admin/channel-token` + `/admin/channels` endpoints that this rename moves.
- [`parachute-agent-legacy/DEPRECATED.md`] — the 2026-05-20 retirement of the *original* containers `parachute-agent`; the repo this rename pushes aside to free the name. Do not conflate the legacy containers module with the new (renamed-from-channel) agent module.
