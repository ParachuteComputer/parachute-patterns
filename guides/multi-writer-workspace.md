# Building a multi-writer workspace on parachute-vault

> A canonical reference for orgs and builders standing up a team knowledge graph on parachute. Covers what's supported today, with worked examples; flags what's in flight.

## Who this is for

Any team — content org, research lab, founder-plus-ops shop, an open-source project's collective brain — that wants a shared workspace where:

- **Multiple humans write** with distinct roles and visibility.
- **Agents write too** — nightly syncs, capture bots, drafters, scrapers.
- **Structured + unstructured content coexist.** A `state: drafted` enum lives next to a free-form transcript.
- **AI can read and write through MCP**, not just bolt on after the fact.
- **The data is yours** — local-first, self-host-by-default, portable.

If that's the shape you're building toward, this guide is the map.

If you're a single user writing personal notes, vault works fine as a single-writer tool too — much of this guide is overkill for that case. Drop the auth-and-roles sections; keep the schema and querying chapters.

## How to read this

The structure runs from foundations outward:

1. **Mental model** — what parachute is and isn't, before anything else.
2. **Multi-writer foundation** — auth, scopes, concurrency.
3. **Structure** — declaring what your data looks like.
4. **Writing** — creating and updating notes.
5. **Querying** — reading and traversing.
6. **Obsidian sync** — the round-trip with the file-on-disk world.
7. **Voice + attachments** via parachute-scribe.
8. **Agents as writers** — automation patterns.
9. **Webhooks + triggers** — reacting to changes.
10. **Templates** — a convention, not a feature.
11. **Public projection** — when the workspace isn't private anymore.
12. **What's coming** — items on the near-term roadmap.
13. **Worked example** — a full content-team setup, end to end.

You can skim 1–2 and then jump to whichever chapter matches your immediate question. The cross-links keep the map intact.

---

## 1. The mental model

### Vault is a workspace, not a database

The most useful framing: **vault is a workspace, not a CRUD database.** Notes carry content + tags + links + metadata. Reads + writes happen over MCP tools and a REST API. Two writers reading and writing the same note expect *each other's edits to land* — not last-write-wins.

This shapes everything below. If you arrive expecting "I'll just SQL my data in," many of vault's defaults will feel like friction. They're the right defaults for collaboration; they're the wrong defaults for write-only pipelines. The chapter on writing covers how to handle the write-only-pipeline case (`update-note` with path-as-id) without breaking the workspace grain for everyone else.

### Workspace atop journal — a useful split

A pattern that recurs across teams setting this up: keep your **append-only journal** (Slack archive, email corpus, transcript pile, git repo of nightly LLM derives — whatever you have) as the audited, immutable source of truth. Project **structured state** into the vault, where humans and agents work. The journal feeds the workspace; the workspace is where the daily work lives.

Vault doesn't replace the journal. It sits beside it as the queryable, multi-writer, agent-callable layer.

### Parachute's grain

Five design choices shape what fits and what doesn't:

**1. Optimistic concurrency, not last-write-wins.** `update-note` requires an `if_updated_at` precondition by default ([parachute-vault `core/src/notes.ts:104-127`](../../parachute-vault/core/src/notes.ts), [`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md)). Concurrent writers reconcile via a `ConflictError`. This is intentional — vault is a collaborative workspace, not a write-only data sink. The grain expects writers to read-then-write, not blanket-overwrite. If you must clobber (bulk migration, scripted backfill), pass `force: true` explicitly; the override is loud on purpose.

**2. `create-note` and `update-note` are deliberately distinct.** Create asserts "this is new"; update asserts "I know what was there and I'm changing it." There is no `upsert` verb. The framing assumes the writer either knows the note is missing or knows what they're changing. The chapter on writing covers the path-as-id pattern for sync flows that don't know prior state.

**3. Tag schemas are advisory by default.** `update-tag` lets operators declare enums, types, required fields, indexed fields, typed relationships ([`core/src/tag-schemas.ts:24-54`](../../parachute-vault/core/src/tag-schemas.ts)). Writes that violate the declarations succeed but carry a `validation_status` warning in the response. This is right for organic, exploratory work; it's wrong for high-stakes multi-writer environments where drift compounds. Opt-in field-level strict mode is on the roadmap (vault#299).

**4. Hub-as-Authorization-Server is the multi-writer foundation.** Each writer (human or agent) authenticates via hub; hub mints per-identity JWTs carrying `sub` (writer identity), per-vault scopes, and optionally a per-tag `scoped_tags` allowlist ([`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md), [`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md)). This is the substrate for everything in §2.

**5. Vault is generic; orgs declare their structure.** Vault doesn't know about "decisions," "pieces," "source-moments," or "donors." You declare a tag with `update-tag`, list its indexed fields, and those fields become first-class queryable on every note carrying that tag. Vault stays narrow; orgs project their domain onto it. This is the right level for a substrate — generic engine, operator-declared structure.

### Three modules, one workspace

The committed-core that this guide leans on:

| Module | Role |
|---|---|
| **parachute-vault** | The knowledge graph + MCP. Notes, tags, links, schemas. |
| **parachute-hub** | The portal + Authorization Server. Token issuance, identity, service catalog. |
| **parachute-scribe** | Transcription daemon. Picks up audio attachments + writes transcripts back. |
| **parachute-agent** | (Optional) Container-hosted Claude distribution for automation. |
| **parachute-notes** | (Optional) Frontend PWA for human authoring. |

Each is its own repo with its own conventions. Vault is the one this guide is centered on; the others appear where they matter.

---

## 2. The multi-writer foundation

### Hub-as-AS

A single OAuth issuer for the whole ecosystem. The hub mints tokens; vault validates them ([`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md)). When a writer authenticates against hub, they receive a JWT whose `aud` is the target vault (`vault.<name>`) and whose `scope` claim carries the granted permissions.

Vault validates incoming JWTs via [`src/auth.ts`](../../parachute-vault/src/auth.ts) — `validateHubJwt` checks the signature, the audience, and the scope set. The `sub` claim arrives in every write request as the writer identity (today used for authz; per-identity attribution on notes is in flight — see §12).

### Per-vault scopes

Tokens carry one of three scopes per vault:

- `vault:<name>:read` — read-only (query-notes, list-tags, find-path, vault-info).
- `vault:<name>:write` — read + create + update notes, attachments, links, tags.
- `vault:<name>:admin` — write + token management + schema authoring + delete.

A single token can carry scopes for multiple vaults. The check is per-request, per-vault ([`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md)).

### Per-tag scoped tokens

A vault token can be narrowed to a `scoped_tags` allowlist. Once set, the token only reads + writes notes that carry at least one allowlisted tag — or a sub-tag, via the `tags.parent_names` hierarchy ([`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md), [`src/tag-scope.ts`](../../parachute-vault/src/tag-scope.ts)).

A token with `scoped_tags: ["donor-pipeline"]` can:

- Read notes tagged `#donor-pipeline`, `#donor-pipeline/intro`, `#donor-pipeline/closed`.
- Write into the same slice — but a `create-note` with no allowlisted tag returns 403.
- See only those tags in `list-tags`.

The allowlist is immutable for the life of the token; widening it means minting a new token.

### Optimistic concurrency

Already named above. The shape (from [`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md); the HTTP/MCP response body, as mapped by [`src/routes.ts:1032-1048`](../../parachute-vault/src/routes.ts) from core's `ConflictError`):

```jsonc
// Request
{
  "id": "01J9Z2K3...",
  "content": "...",
  "if_updated_at": "2026-04-21T17:33:08.412Z"
}

// 409 Conflict response
{
  "error_type":         "conflict",
  "current_updated_at": "2026-04-21T17:35:11.207Z",
  "your_updated_at":    "2026-04-21T17:33:08.412Z",
  "note_id":            "01J9Z2K3...",
  "path":               "donors/acme.md",
  "message":            "conflict: note \"01J9Z2K3...\" has been modified ..."
}

// 428 Precondition Required (caller sent neither `if_updated_at` nor `force: true`)
{
  "error_type": "precondition_required",
  "note_id":    "01J9Z2K3...",
  "path":       "donors/acme.md",
  "message":    "update requires `if_updated_at` ... or `force: true`."
}
```

Two distinct statuses on purpose: `428` says *you didn't try*; `409` says *you tried and lost the race*. Agents should react differently to each — a `428` is almost always a bug-in-my-code; a `409` is "re-read, reconcile, retry."

### Atomic append + prepend

The exception that makes concurrent contribution easy. `update-note` accepts `append` and `prepend` fields that run as `content = content || ?` at the SQL layer ([`core/src/notes.ts:295-322`](../../parachute-vault/core/src/notes.ts)). Two concurrent appends both land — neither overwrites the other. No `if_updated_at` required, because there's nothing to clobber. Use this for the "everyone leaves a note on a standup," "every agent contributes a row to a daily roll-up," "log a fresh capture" patterns.

```ts
// MCP call
await mcp.callTool("update-note", {
  id: "01J9Z2K3...",
  append: "\n- [Alice 14:32] Pricing question from prospect X."
});
```

Frontmatter-aware: if the note opens with YAML frontmatter, `prepend` lands *after* the closing `---\n` so parsers expecting frontmatter at byte 0 still find it ([`core/src/notes.ts:302-322`](../../parachute-vault/core/src/notes.ts)).

### A concrete three-writer setup

Worked example. Three humans on a content team — Alice (founder, captures ideas), Bob (campaign ops, logs publishes), Carol (narrative director, authors storyboards) — plus one nightly agent.

> **Flags shown are illustrative — run `hub tokens mint --help` for the real surface.** The concepts (per-identity tokens, per-vault scopes, per-tag allowlists) are stable; the command shape is still evolving.

```bash
# As the vault admin, mint tokens via hub. Each writer authenticates once;
# hub issues their JWT bearing the right scopes.

# Alice — full vault write (founder needs to range freely).
hub tokens mint --user alice@team.org --scope "vault:team:write"

# Bob — write, scoped to "piece" and "performance" tag trees.
hub tokens mint --user bob@team.org \
  --scope "vault:team:write" \
  --scoped-tags "piece,performance"

# Carol — write, scoped to "storyboard" and "asset" tag trees.
hub tokens mint --user carol@team.org \
  --scope "vault:team:write" \
  --scoped-tags "storyboard,asset"

# Nightly sync agent — write, scoped to "source" (it only writes
# source-moment notes from the upstream corpus).
hub tokens mint --identity nightly-sync \
  --scope "vault:team:write" \
  --scoped-tags "source"
```

Each writer gets a token; their MCP client (Claude Desktop, Obsidian plugin, custom script) authenticates with it. Vault enforces scope on every call. Carol cannot accidentally write to `#piece` notes; the nightly agent cannot touch storyboards.

When you grow to ten writers, the same pattern scales — one token per identity, narrowed via `scoped_tags` or `vault:<name>:read`-only as appropriate.

---

## 3. Declaring your structure (tag schemas)

### Tags are first-class identities

A tag in vault isn't just a string. The `tags` table carries a row per tag with description, `fields` (the indexed-metadata declarations), `relationships` (typed-link cardinality), and `parent_names` (hierarchy). See [`patterns/tag-data-model.md`](../patterns/tag-data-model.md) for the full surface.

The `update-tag` MCP tool is the upsert: pass the tag name, the description, the field schema, the relationships. Vault stores it in the row.

### Declaring fields with `update-tag`

A tag declares zero or more metadata fields. Each field has a `type`, optional `enum`, optional `indexed: true`. Indexed fields get a generated column + B-tree index on the notes table, so `query-notes` can filter and sort by them ([`core/src/tag-schemas.ts:24-33`](../../parachute-vault/core/src/tag-schemas.ts), [`core/src/indexed-fields.ts`](../../parachute-vault/core/src/indexed-fields.ts)).

```ts
// MCP call: declare the `concept-seed` tag schema.
// Note: `tag` is the parameter name (singular). Indexed field types
// are limited to string | integer | boolean.
await mcp.callTool("update-tag", {
  tag: "concept-seed",
  description: "A frame × source-moment pairing that could become a publishable piece.",
  fields: {
    state: {
      type: "string",
      description: "Production stage. Advances left-to-right.",
      enum: ["idea", "drafted", "scripted", "produced", "published", "killed"],
      indexed: true
    },
    format: {
      type: "string",
      enum: ["tweet", "video", "post", "podcast", "clip"],
      indexed: true
    },
    priority: { type: "integer", indexed: true },
    owner:    { type: "string",  indexed: true }
  },
  // `relationships` is an object keyed by the verb on the edge; each
  // value declares { target_tag, cardinality, description? }.
  relationships: {
    uses_frame:  { target_tag: "frame",         cardinality: "many-required" },
    uses_source: { target_tag: "source-moment", cardinality: "many" }
  }
});
```

After this declaration:

- Any note tagged `#concept-seed` is expected to carry the declared metadata fields.
- Writes that violate the enum (e.g. `state: "wip"`) succeed but ship a `validation_status: { errors: [...] }` warning in the response — the advisory model.
- `query-notes` can filter directly via `metadata: { state: { eq: "drafted" }, format: { eq: "video" } }`.
- `list-tags` surfaces the schema so an AI agent reading it picks valid values.

### Advisory now, opt-in strict later

Today the validation is advisory ([`patterns/tag-data-model.md` §Validation](../patterns/tag-data-model.md)). On the roadmap (vault#299): per-field `strict: true` flag — when set, violations of that field's declared constraints cause the write to fail instead of warning. Operators opt fields in field-by-field; advisory remains the default.

The design call still open is which axes flip together. The current direction: **all-or-nothing per field** — `strict: true` flips enum + required + type + cardinality together on that field. A required field that's missing is just as broken as an enum value that's wrong; two flags is fine if there's a reason to separate them, but the realistic policy is coherent posture per field.

For now: rely on the advisory model. Build a small drift-detection agent if it matters — query for notes whose `validation_status` is non-empty, surface them on a dashboard, fix manually. When strict mode ships, layer it on top of the same schema declarations.

### Hierarchy + inheritance

Tags can nest via `parent_names`. A note tagged `#health/food/breakfast` inherits the schema of `#health/food`, which inherits from `#health`. Field declarations layer top-down ([`patterns/tag-data-model.md` §Schema inheritance](../patterns/tag-data-model.md)). This lets you share common fields (e.g. `source`, `derived_at`) across many tag trees by declaring them once on a top-level `_default` or a shared parent.

```ts
// Declare a shared "derived" parent that any sync-derived tag inherits from.
await mcp.callTool("update-tag", {
  tag: "derived",
  description: "Notes projected from an external source.",
  fields: {
    source:      { type: "string", indexed: true },
    derived_at:  { type: "string", indexed: true },
    derived_by:  { type: "string", indexed: true }
  }
});

// Then a concrete tag inherits from it.
await mcp.callTool("update-tag", {
  tag: "source-moment",
  parent_names: ["derived"],
  fields: {
    freshness: { type: "string", enum: ["hot", "warming", "cold"], indexed: true }
  }
});
```

Notes tagged `#source-moment` now carry `source`, `derived_at`, `derived_by`, and `freshness` as queryable indexed fields, with no duplication of declaration.

---

## 4. Writing into the vault

### `create-note` — single + batch

The simplest write. Pass content, optional path, optional tags, optional metadata, optional links. Returns the created note (including its `id` and `updated_at`).

```ts
await mcp.callTool("create-note", {
  content: "## Armstrong inversion\n\nCoinbase memo × rebuild-humans frame.",
  path: "concept-seeds/armstrong-inversion.md",
  tags: ["concept-seed"],
  metadata: {
    state: "idea",
    format: "video",
    priority: 1,
    owner: "alice"
  },
  links: [
    { target: "frames/rebuild-humans.md", relationship: "uses-frame" },
    { target: "source-moments/coinbase-memo-2026-05-05.md", relationship: "uses-source" }
  ]
});
```

`target` on a link accepts either a note ID or a path ([`core/src/mcp.ts:349`](../../parachute-vault/core/src/mcp.ts)) — the same resolution rule as `update-note`'s `id` argument.

Batch shape: pass `notes: [...]` instead of single-item fields. The whole batch runs in one SQLite transaction — `BEGIN`/`COMMIT`/`ROLLBACK` wraps the loop. Mid-batch error rolls every prior insert back. Per-call cap is **`MAX_BATCH_SIZE = 500`** ([`core/src/notes.ts:150-157`](../../parachute-vault/core/src/notes.ts)).

```ts
await mcp.callTool("create-note", {
  notes: [
    { content: "...", path: "people/alice.md", tags: ["person"], metadata: { role: "founder" } },
    { content: "...", path: "people/bob.md",   tags: ["person"], metadata: { role: "ops" } },
    // ... up to 500 items per call
  ]
});
```

For seeding a vault with hundreds of notes (228 person files; 30 days of social drafts; curated frames; etc.), batch is the right shape. Single-call writes for a 500-note seed take seconds, not minutes.

### `update-note` — single + batch + path-as-id

`update-note` accepts an `id` argument that's either a note ID or a path. It tries ID-lookup first, falls back to path-lookup. This is the foundation of the "sync from an external source" pattern.

```ts
// Updating a known note by ID.
await mcp.callTool("update-note", {
  id: "01J9Z2K3...",
  content: "Updated body.",
  if_updated_at: "2026-05-11T14:22:01.000Z"
});

// Updating by path — useful when you don't track IDs.
await mcp.callTool("update-note", {
  id: "people/alice.md",        // resolves by path
  content: "Updated body.",
  if_updated_at: "2026-05-11T14:22:01.000Z"
});
```

Identity preserved (the note keeps its ID); incoming wikilinks preserved (path is unchanged); `updated_at` refreshed.

### The sync-from-external-source pattern

When you sync from a journal (git corpus, Slack export, Notion dump), you usually don't know prior state — the source has rewritten the markdown for that path, and you want vault to mirror it.

**The canonical shape: query first, then create-or-update.** Two round trips per item in the missing case.

```ts
async function syncOne(path: string, content: string, metadata: object) {
  // `query-notes` with `id` accepts a path. Returns the note directly,
  // or `{ error: "Note not found", id }` on miss.
  const existing = await mcp.callTool("query-notes", { id: path });

  if (existing && !existing.error) {
    await mcp.callTool("update-note", {
      id: path,
      content,
      metadata,                          // merged into existing metadata
      if_updated_at: existing.updated_at
    });
  } else {
    await mcp.callTool("create-note", { content, path, metadata, tags: ["derived"] });
  }
}
```

This is the parachute-grain shape — explicit about intent (the sync writer asserts "I know what was there"), keeps concurrency safety intact, and costs one extra query per item only in the missing case.

Avoid the apparent shortcut of `update-note` with `force: true` plus a try/catch fallback to `create-note`. It suppresses concurrency safety on every call, and vault throws `Error("Note not found: ...")` with no machine-readable `code` field ([`core/src/notes.ts:385-392`](../../parachute-vault/core/src/notes.ts)) — catching it reliably means string-matching the message, which is brittle. The query-first shape is correct *and* shorter.

A future `update-note` flag — `if_missing: "create"` — would collapse this to one round trip. It's logged but not committed to a date; orgs hitting real round-trip ceilings should write up a use case to push it up the priority list.

### Atomic append/prepend revisited

For collaborative growth patterns — every writer adds to the same note — use `append` / `prepend`. SQL-atomic; no precondition required.

```ts
// Every team member contributes to a daily roll-up.
await mcp.callTool("update-note", {
  id: "daily/2026-05-12.md",
  append: `\n- [Alice 09:14] Shipped the Armstrong storyboard.\n`
});

// Five concurrent appends → all five lines land, in some order.
```

### Why no `upsert` verb

The shape would conflate "I'm adding something new" with "I know what's there and I'm changing it" into one call. That weakens the collaboration model — `update-note` having a real if-precondition is what protects two writers from clobbering each other; folding `create` into it would either drop the precondition (losing safety) or make the precondition optional (which is just `force: true` with extra steps).

Path-as-id resolution gets you 90% of the upsert ergonomics with one extra round trip in the missing case. The extra round trip is the cost of keeping `create` and `update` honest.

---

## 5. Querying + traversal

### `query-notes` — the universal read

One tool, many modes:

- **Single by ID or path** — `{ id: "01J9..." }` or `{ id: "people/alice.md" }`.
- **Filter** — `{ tag: "concept-seed", metadata: { state: { eq: "drafted" } } }`. Multiple tags: `{ tag: ["concept-seed", "draft"], tag_match: "any" }`.
- **Search** — `{ search: "rebuild humans" }` for content full-text.
- **Graph neighborhood** — `{ near: { note_id: "...", depth: 2 } }` scopes results to notes within N hops of an anchor (follows wikilinks + typed links).
- **Date range** — `date_from` / `date_to` filter on `created_at` (ingestion time). For `updated_at` ("what changed since X") or any indexed metadata date field, use the generalized `date_filter: { field, from, to }` shape.

The filter grammar lives in [`core/src/mcp.ts` `query-notes` tool definition](../../parachute-vault/core/src/mcp.ts) (`name: "query-notes"`, starting line ~84). Operator vocabulary on indexed metadata fields: `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`, `exists`.

```ts
// Find drafted video concept-seeds owned by Alice, sorted by priority desc.
await mcp.callTool("query-notes", {
  tag: "concept-seed",
  metadata: {
    state:  { eq: "drafted" },
    format: { eq: "video" },
    owner:  { eq: "alice" }
  },
  order_by: "priority",
  sort: "desc",
  limit: 20
});
```

`order_by` requires the field to be declared `indexed: true` on at least one tag carried by the queried notes ([`core/src/mcp.ts:141`](../../parachute-vault/core/src/mcp.ts)). Vault refuses non-indexed sorts to prevent table-scan footguns. Pass the bare field name (`"priority"`), not a dotted path.

### Preview-only reads

For agents doing many small edits on large notes (atomic `append` on a 50k-token transcript, for instance), re-fetching the body on every call is the dominant cost. Pass `include_content: false` to get a lean shape — `id`, `path`, `tags`, `metadata`, `byteSize`, `preview` (the first ~200 chars), without full content. The `validation_status` is preserved on the lean shape when present.

### Wikilinks

`[[wikilinks]]` in note content are parsed and stored as edges in the `links` table when notes are created or updated ([`core/src/wikilinks.ts`](../../parachute-vault/core/src/wikilinks.ts)). When a link target doesn't exist yet, the link lives in `unresolved_wikilinks` and **auto-resolves** when the target note is later created at the matching path. This means you can write notes referring to placeholders before the placeholders exist; the graph hydrates as you fill it in.

### `find-path` — BFS traversal

Shortest-path between two notes via the links graph. Useful for "is this concept reachable from that source?" and "show me the trail from a published piece back to its seed and source-moment."

```ts
await mcp.callTool("find-path", {
  source: "pieces/2026-05-08-tweet.md",
  target: "source-moments/coinbase-memo-2026-05-05.md",
  max_depth: 5
});
// Returns the shortest chain of note IDs and relationships, or null if
// unreachable within max_depth. `source` and `target` accept ID or path.
```

A full graph query language (Cypher-ish, GraphQL-ish) isn't on the near-term roadmap. `find-path` + neighborhood expansion + filter chaining covers most workflows; full traversal is XL build.

### Attachments + their metadata

Attachments hang off notes; each has a `metadata` JSON column. Today the metadata isn't natively filterable in `query-notes`. Workaround: query notes with `include_attachments: true`, filter the returned attachments client-side. A proper `query-attachments` tool or `?attachment_meta[...]=...` filter is logged but low-priority. Use the workaround for the first iteration.

---

## 6. Bidirectional Obsidian sync

A vault is round-trippable with an Obsidian-shape directory. The `import` walks a markdown directory, parses YAML frontmatter into note metadata, parses `[[wikilinks]]` into edges, parses inline `#tags` and frontmatter `tags: [...]` into the tags table ([`core/src/obsidian.ts:42-111`](../../parachute-vault/core/src/obsidian.ts)). The `export` writes notes back as markdown files with frontmatter intact.

This means a team member who lives in Obsidian can use Obsidian as their UI — opening the vault directory as an Obsidian workspace, authoring notes in their preferred editor — and the vault stays the source of truth. The other writers, the agents, the MCP clients all see the same notes.

Re-import semantics today: one-shot create. If a re-imported file already exists at the same path, vault produces a `PathConflictError` ([`core/src/notes.ts:139-148`](../../parachute-vault/core/src/notes.ts)). To re-import with merge semantics — i.e. update-by-path for existing files, create for new — wrap the importer with the same option-A pattern from §4. The pattern is straightforward; nothing in vault stops you. A native re-import-merge flag is logged but low-priority.

Wikilink IDs are stable across round-trips when paths are stable. A renamed file in Obsidian (new path) currently lands as a new note; a future native rename-detection pass could match by frontmatter-id when present.

---

## 7. Voice + attachments via parachute-scribe

Scribe is the transcription module. Architecture:

1. A client uploads an audio attachment to a vault note with `transcribe: true` in the upload metadata.
2. Vault writes the attachment and fires a trigger.
3. Scribe (running locally or in the cloud per your install) picks up the job.
4. Scribe runs the audio through its configured provider (Whisper API, Deepgram, etc.).
5. Scribe writes the transcript back into the note's content, overwriting a `_Transcript pending._` placeholder.

Wire-up example for a capture flow (a Telegram bot, a desktop hotkey, a phone shortcut):

```ts
// 1. Create a placeholder note.
const note = await mcp.callTool("create-note", {
  content: "_Transcript pending._",
  tags: ["capture"],
  metadata: { source: "telegram", from: "alice" }
});

// 2. Upload the audio as an attachment with transcribe: true.
await fetch(`${VAULT_URL}/api/notes/${note.id}/attachments`, {
  method: "POST",
  headers: { Authorization: `Bearer ${TOKEN}` },
  body: formData  // includes the audio file and { transcribe: true }
});

// 3. Done. Scribe takes over. The note's content updates async when transcription lands.
```

Scribe is vault-level, not Notes-PWA-level — configure scribe once against the vault and every client (Telegram bot, Notes PWA, future agents) gets transcripts as a free service. The Notes UI doesn't need to know transcription is configured; that's vault's concern.

---

## 8. Agent-as-writer patterns

### parachute-agent vs your own cron

Two paths for agent-driven writes:

**Plain script + cron.** A small Bun/Python/node script that reads its source, talks to vault's REST API or MCP with a long-lived token, runs on a system cron. Lowest-friction shape for one or two scheduled jobs.

**parachute-agent.** A distribution of Claude that runs in containers, with named agent groups, scheduled or webhook-triggered execution, hub-issued auto-rotated tokens, a UI to monitor runs, and first-class vault writes attributable to the agent identity.

Rule of thumb:

- **1–2 scheduled jobs:** plain script + cron. The token-rotation and monitor-UI overhead of parachute-agent doesn't earn its weight yet.
- **3+ agent groups with distinct scopes + schedules:** parachute-agent. Token rotation handled for you; restart/reconfigure without redeploying scripts; the agent's writes are attributable to its identity in the (forthcoming) per-identity attribution columns.

You can start with a script and migrate to parachute-agent later. The vault doesn't care which is doing the writing; the writes look the same.

### Hub-issued scoped tokens for agents

Same pattern as humans — but you'll typically scope agents narrowly. The nightly source-scraping agent needs `vault:<name>:write` + `scoped_tags: ["source"]` and nothing else.

```bash
hub tokens mint --identity nightly-source-scraper \
  --scope "vault:team:write" \
  --scoped-tags "source"
```

Two design notes:

1. **Don't use a single service token for many agents.** Each agent gets its own identity, so the attribution columns (when they land — vault#298) tell you which agent did what.
2. **Token rotation is hub's job.** With parachute-agent, rotation is automatic. With your own scripts, rotate manually via `hub tokens rotate <id>` and update the script's secret store.

### Writing back to the vault from agents

Same MCP/REST surface as humans. An agent drafting a storyboard runs:

```ts
await mcp.callTool("create-note", {
  content: storyboardMarkdown,
  path: `storyboards/${seedSlug}.md`,
  tags: ["storyboard"],
  metadata: {
    parent_seed: seedId,
    status: "draft",
    drafted_by: "agent.storyboard-drafter"
  }
});
```

Today the `sub` claim from the JWT arrives at vault but isn't persisted on the note. Add the writer identity to a metadata field on the agent side (e.g. `drafted_by` above) if you want it queryable today. When per-identity attribution columns ship (vault#298), the field becomes redundant and you can drop it.

---

## 9. Webhooks + triggers

Vault has a generic trigger system ([`src/triggers.ts`](../../parachute-vault/src/triggers.ts)). A trigger declares a **predicate** (tags + metadata-presence) and an **action** (webhook URL + send/response mode). When a note mutation matches, the trigger fires a webhook and applies the response back to the note.

Example trigger config (vault config.yaml — shape from [`src/config.ts:210-234`](../../parachute-vault/src/config.ts)):

```yaml
triggers:
  - name: notify-publish
    events: [updated]            # default: [created, updated]
    when:
      tags: [piece]
      has_metadata: [published_at]
    action:
      webhook: https://hooks.team.org/published
      send: json                 # default: json

  - name: kick-off-perf-tracking
    events: [created]
    when:
      tags: [piece]
    action:
      webhook: https://perf-tracker.team.org/new-piece
```

Predicate grammar today (the `when` block — full surface in [`src/config.ts:170-181`](../../parachute-vault/src/config.ts)):

- **`tags: [...]`** — note carries any of these tags (or sub-tags).
- **`has_metadata: [...]`** — note has all of these metadata keys set (non-null).
- **`missing_metadata: [...]`** — note has none of these keys set.
- **`has_content: true|false`** — content is non-empty / empty.

Restricting on the *event* (create vs update) lives on the trigger itself via `events: [...]`, not inside `when`.

Not supported today inside `when`:

- **Value-equality predicates.** "Fire when `state` equals `published`" — workaround: subscribe to all writes against the tag, filter in the consumer.
- **State-transition matching.** "Fire when `state` transitions from `produced` → `published`" — deeper change; logged.

Extending `when.metadata` with the same operator grammar as `query-notes` (eq/ne/in) is on the roadmap. Transition matching is lower priority.

### Inbound: posting to vault from external events

The other direction — "Telegram message arrives → write to vault" — is just `POST /api/notes` with a bearer token. There's no special inbound-webhook idiom. The Telegram bot, Slack bot, email gateway, etc. each:

1. Authenticate to hub once, get a scoped token (typically `vault:<name>:write` + `scoped_tags: ["capture"]`).
2. On their inbound event, POST a note via the REST API or call `create-note` via MCP.
3. Tag appropriately so downstream queries can find it.

A capture pattern that recurs: tag inbound captures with `#capture` and a source tag (`#capture/telegram`, `#capture/email`), let a human or a tagging agent re-tag weekly. Friction-zero on the way in; structure layers on later.

---

## 10. Templates (a convention, not a feature)

There's no parachute-side template feature. The convention:

**Create a note tagged `#template/<name>` whose content is the skeleton.** Authoring tools (Obsidian template plugin, your custom UI, an agent) copy the template's body and frontmatter when creating a new note from it.

```ts
// Define a storyboard template once.
await mcp.callTool("create-note", {
  path: "_templates/storyboard.md",
  content: `## {{title}}\n\n### Frames\n\n### Prompts\n\n### Voiceover\n\n### Sound\n\n### Length\n`,
  tags: ["template/storyboard"],
  metadata: { template_name: "storyboard" }
});

// Authoring UI: fetch the template, substitute {{vars}}, call create-note.
// query-notes with `id` returns the note directly (with content by default).
const template = await mcp.callTool("query-notes", { id: "_templates/storyboard.md" });
const body = template.content.replace("{{title}}", inputTitle);
await mcp.callTool("create-note", {
  path: `storyboards/${slug}.md`,
  content: body,
  tags: ["storyboard"],
  metadata: { parent_seed: seedId, status: "draft" }
});
```

The convention costs zero vault changes. The cost is one substitution step in your authoring layer. The benefit: templates are themselves vault notes — queryable, versionable, editable in any vault client. No parallel template store.

A parachute-side template feature is not on the roadmap. The convention is the answer.

---

## 11. Public projection (where surface direction comes in)

### Single-note publishing today

Vault has a `published_tag` config and a `/view/<noteId>` route. Notes carrying the published tag are renderable at the public URL — a tweet-card-shaped view of one note, rendered server-side, no auth required.

This is sufficient for "share this one decision memo publicly" or "embed this one explainer on a blog." It is **not** sufficient for "build a public KPI dashboard," "render an org's content roadmap," "publish a tag-filtered index page that updates as the vault grows."

### When the workspace becomes a surface

For richer public projection — themable, configurable, tag-filtered, possibly built once and deployed static — the right home is the **surface** layer, currently in research at [`research/parachute-surface-direction.md`](../research/parachute-surface-direction.md).

The framing there:

- **Vault** stores the content.
- **Surface** is the customizable presentation layer atop vault. It can render in two modes:
  - **Static** — build once, deploy as HTML.
  - **Active** — runtime renderer sourcing from vault API.

The same surface implementation should be capable of both. WovenBoulder (an external civic-wiki build atop vault) is the first SSG-shape exploration; Notes PWA is the active-shape exemplar.

For first-iteration public projection, options today:

- **Single-note publishing** works for one-off pages.
- **A thin custom web app over the REST API** works for early dashboards. Query vault with a read-only token, render server-side or as a static export.
- **WovenBoulder-style external SSG** if you want full theme control and don't mind a separate build pipeline.

When surface-direction lands, the right shape is "configure a surface deployment for your projection — theme, layout, source vault, which tag filters become page templates — and deploy." That's months out, not days; if your projection needs are pressing, build the thin custom layer now.

---

## 12. What's coming

In flight or logged, in rough priority order:

**Hub multi-user infrastructure.** Sign-in flows, user management, consent surfaces. Hub-side work; vault attribution is downstream of this.

**Per-identity attribution columns** (vault#298). `created_by` and `last_updated_by` as first-class columns on the notes table, auto-filled from JWT `sub` at write time. Queryable directly via `query-notes` filter (`?last_updated_by=alice@team.org`).

**Field-level strict mode** (vault#299). Per-field `strict: true` flag on tag schemas. When set, declared constraints (enum + required + type + cardinality) flip from advisory to enforced. All-or-nothing per field.

**Audit log table** (vault#300). Full write history — separate from `last_updated_by` (latest-state). Deferred for design; logged for tracking.

**Surface direction** (patterns#54). Customizable presentation layer atop vault. Currently in research.

**`update-note` `if_missing: "create"`.** Lowest-effort upsert path; saves one round trip on sync-from-external-source flows. Logged, not committed.

**Webhook `when.metadata` operator grammar.** `eq`/`ne`/`in` on metadata values, matching `query-notes`. Logged.

**Attachment metadata query filter.** `?attachment_meta[prompt]=...` or a dedicated `query-attachments` tool. Logged.

**Hosted parachute** (vault#5). Requires async Store interface refactor. Long path.

If something here matters for your build, file an issue against the relevant repo citing your use case — concrete friction with a real workflow attached moves items up priority lists faster than generic asks.

---

## 13. Worked example: a content-team workspace from scratch

End-to-end walkthrough. You're standing up a 3-human + 1-agent content team workspace.

### Step 1 — install hub and vault

```bash
# On the team server (or a laptop for testing).
npx @openparachute/hub init
parachute install vault
parachute start
```

Hub runs on `:1939`, vault on `:1940`. Hub's installer walks you through binding the hub origin (a Tailscale URL, a domain, or just loopback for local-only).

### Step 2 — create the team vault

```bash
parachute vault create team
```

A vault named `team` lives at `~/.parachute/vault/team/`. Its SQLite DB is empty; no tags declared.

### Step 3 — declare tag schemas

A small bootstrap script the team-lead runs once. Hub's MCP discovery surfaces the schemas to every connected client thereafter.

```ts
// bootstrap-schemas.ts — run once against the team vault.
import { vaultMcp } from "./mcp-client.ts";

// Shared "derived" parent — every sync-derived tag inherits source-tracking.
// Indexed types: string | integer | boolean. Field `type` must agree across
// all tags that declare the same field.
await vaultMcp.callTool("update-tag", {
  tag: "derived",
  description: "Notes projected from an external source.",
  fields: {
    source:     { type: "string", indexed: true },
    derived_at: { type: "string", indexed: true },
    derived_by: { type: "string", indexed: true }
  }
});

await vaultMcp.callTool("update-tag", {
  tag: "concept-seed",
  description: "A frame × source pairing that could publish.",
  fields: {
    state:    { type: "string", enum: ["idea","drafted","scripted","produced","published","killed"], indexed: true },
    format:   { type: "string", enum: ["tweet","video","post","podcast"], indexed: true },
    priority: { type: "integer", indexed: true },
    owner:    { type: "string",  indexed: true }
  },
  // `relationships` is an object keyed by relationship name (the verb on the
  // edge); each value declares { target_tag, cardinality, description? }.
  relationships: {
    uses_frame:  { target_tag: "frame",         cardinality: "many-required" },
    uses_source: { target_tag: "source-moment", cardinality: "many" }
  }
});

await vaultMcp.callTool("update-tag", {
  tag: "source-moment",
  description: "An external event/datapoint a piece can ride.",
  parent_names: ["derived"],
  fields: {
    freshness: { type: "string", enum: ["hot","warming","cold"], indexed: true }
  }
});

await vaultMcp.callTool("update-tag", {
  tag: "piece",
  description: "A final published artifact.",
  fields: {
    channel:      { type: "string", indexed: true },
    published_at: { type: "string", indexed: true },
    kpi:          { type: "integer", indexed: true },
    parent_seed:  { type: "string" }
  }
});

await vaultMcp.callTool("update-tag", {
  tag: "storyboard",
  description: "Frame-by-frame breakdown for a video seed.",
  fields: {
    status:      { type: "string", enum: ["draft","review","approved","produced"], indexed: true },
    parent_seed: { type: "string" }
  }
});

await vaultMcp.callTool("update-tag", { tag: "capture", description: "Inbound raw captures." });
await vaultMcp.callTool("update-tag", { tag: "frame",   description: "Conceptual unit; the thing the org believes." });
```

### Step 4 — mint scoped tokens

> **The `hub tokens mint` flag names below are illustrative.** The hub CLI surface is still evolving — run `hub tokens mint --help` for the current flags before pasting these commands. The scope and tag-allowlist *concepts* are stable; the *command shape* may differ.

```bash
# Three humans + one agent.
hub tokens mint --user alice@team.org --scope "vault:team:write"
hub tokens mint --user bob@team.org   --scope "vault:team:write" --scoped-tags "piece,performance"
hub tokens mint --user carol@team.org --scope "vault:team:write" --scoped-tags "storyboard,asset"
hub tokens mint --identity nightly-sync --scope "vault:team:write" --scoped-tags "source"
```

Each writer pastes their token into their MCP client config (Claude Desktop, Obsidian plugin) or their script's secret store.

### Step 5 — first batch import

Seed the vault with the 30 frames you already carry, the 228 people, the last 30 days of source-moments from your existing journal.

```ts
// seed.ts — one-shot, run by an admin.
import { vaultMcp } from "./mcp-client.ts";
import { parseJournal } from "./journal-reader.ts";

const frames = parseJournal("frames/*.md");
const people = parseJournal("people/*.md");
const sources = parseJournal("source-moments/last-30d/*.md");

// Frames — small batch, easy.
await vaultMcp.callTool("create-note", {
  notes: frames.map(f => ({
    content: f.body,
    path: `frames/${f.slug}.md`,
    tags: ["frame"],
    metadata: { origin: f.origin, status: f.status }
  }))
});

// People — 228 items, well under MAX_BATCH_SIZE=500.
await vaultMcp.callTool("create-note", {
  notes: people.map(p => ({
    content: p.body,
    path: `people/${p.slug}.md`,
    tags: ["person"],
    metadata: { role: p.role, last_touch: p.lastTouch }
  }))
});

// Sources — also fits.
await vaultMcp.callTool("create-note", {
  notes: sources.map(s => ({
    content: s.body,
    path: `source-moments/${s.slug}.md`,
    tags: ["source-moment"],
    metadata: {
      source: s.gitRef,
      derived_at: s.derivedAt,
      derived_by: "journal-sync-v1",
      freshness: s.freshness
    }
  }))
});
```

A 228-note batch lands in seconds. The whole seed runs in under a minute.

### Step 6 — first nightly sync (option-A pattern)

```ts
// nightly-sync.ts — runs from cron at 02:00.
import { vaultMcp } from "./mcp-client.ts";
import { readDerivedToday } from "./journal-reader.ts";

const items = readDerivedToday();  // ~50-200 items per night

for (const item of items) {
  const existing = await vaultMcp.callTool("query-notes", { id: item.path });

  if (existing && !existing.error) {
    // `update-note` merges metadata keys into the existing record — no need
    // to spread manually. Just pass the fields you want to change.
    await vaultMcp.callTool("update-note", {
      id: item.path,
      content: item.body,
      metadata: { ...item.metadata, derived_at: item.derivedAt },
      if_updated_at: existing.updated_at
    });
  } else {
    await vaultMcp.callTool("create-note", {
      content: item.body,
      path: item.path,
      tags: ["source-moment"],
      metadata: {
        source: item.gitRef,
        derived_at: item.derivedAt,
        derived_by: "nightly-sync",
        freshness: "hot"
      }
    });
  }
}
```

Token used: the `nightly-sync` identity's scoped token. Writes are constrained to `#source` tag tree by the `scoped_tags` allowlist; a misbehaving sync script can't accidentally touch storyboards.

### Step 7 — first agent-driven write

A storyboard drafter agent. Triggered manually by Alice: "draft a storyboard for seed X."

```ts
// storyboard-drafter.ts — invoked on-demand by an MCP-aware orchestrator.
import { vaultMcp, claudeApi } from "./clients.ts";

export async function draftStoryboard(seedId: string) {
  // Single-id query returns the note directly (not wrapped).
  // Pass `include_content: true` to ensure the body is in the response.
  const seed = await vaultMcp.callTool("query-notes", {
    id: seedId,
    include_content: true
  });

  // List query: returns an array. Pass `include_content: true` since the
  // default for list queries drops content.
  const voiceAnchors = await vaultMcp.callTool("query-notes", {
    tag: "voice-anchor",
    include_content: true
  });
  const brand = voiceAnchors.map(n => n.content).join("\n\n");

  const draft = await claudeApi.complete({
    system: "You are a storyboard drafter. Stay in brand voice.",
    messages: [{
      role: "user",
      content: `Draft a storyboard for this seed:\n\n${seed.content}\n\nBrand:\n${brand}`
    }]
  });

  return vaultMcp.callTool("create-note", {
    content: draft.text,
    path: `storyboards/${seed.metadata.slug}.md`,
    tags: ["storyboard"],
    metadata: {
      parent_seed: seedId,
      status: "draft",
      drafted_by: "agent.storyboard-drafter"
    },
    // Link `target` accepts a note ID or a path.
    links: [
      { target: seedId, relationship: "drafts" }
    ]
  });
}
```

The agent's token is scoped to `#storyboard`. The new note appears in Carol's queries (her token covers `#storyboard`). She reviews, edits, advances the status — `update-note { metadata: { status: "review" } }`.

### Step 8 — first query that pays for itself

Once a few weeks of writes land, the queries get useful:

```ts
// "What's drafted that I haven't touched in 7 days?"
// date_filter on `updated_at` is the generalized shape; the top-level
// `date_from` / `date_to` shorthand only filters on `created_at`.
await vaultMcp.callTool("query-notes", {
  tag: "concept-seed",
  metadata: { state: { eq: "drafted" } },
  date_filter: { field: "updated_at", to: "2026-05-05T00:00:00Z" },
  order_by: "priority",
  sort: "desc"
});

// "Find published pieces for KPI 3 this week."
// `kpi` and `published_at` must be declared `indexed: true` on the
// `piece` tag schema for operator queries to route through the index.
await vaultMcp.callTool("query-notes", {
  tag: "piece",
  metadata: {
    kpi:          { eq: 3 },
    published_at: { gte: "2026-05-05" }
  }
});

// "Trace the shortest path from a published piece back to a known source-moment."
// `find-path` is point-to-point on note IDs/paths — there's no tag-based
// destination. If you want "any source-moment reachable from here," pull
// the neighborhood and filter:
const neighborhood = await vaultMcp.callTool("query-notes", {
  near: { note_id: pieceId, depth: 4 },
  tag: "source-moment"
});
// Then run find-path against a specific target:
await vaultMcp.callTool("find-path", {
  source: pieceId,
  target: neighborhood[0]?.id,
  max_depth: 4
});
```

None of these need pre-canned scripts. Each is a single MCP call (or in the find-path-by-tag case, two — a neighborhood scope plus a point-to-point trace). The structure you declared in step 3 is what makes them work.

---

## Cross-links

- [`guides/building-a-surface.md`](./building-a-surface.md) — companion guide for *building a surface over parachute-vault* (the builder's-side counterpart to this doc — auth, discovery, OC writes, schema-ensure, reachability).
- [`patterns/governance.md`](../patterns/governance.md) — review discipline, RC versioning, patterns check.
- [`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md) — the precondition contract.
- [`patterns/tag-data-model.md`](../patterns/tag-data-model.md) — full surface for tag schemas + hierarchy + typed relationships.
- [`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md) — per-tag token narrowing.
- [`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md) — OAuth issuer architecture.
- [`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md) — scope vocabulary.
- [`patterns/vault-mcp-discovery.md`](../patterns/vault-mcp-discovery.md) — how MCP clients discover schemas.
- [`research/parachute-surface-direction.md`](../research/parachute-surface-direction.md) — surface layer (public projection).

## Feedback

If you build on this and hit friction:

- Vault-substrate friction → file against `parachute-vault`.
- Auth / multi-writer / token friction → file against `parachute-hub`.
- Cross-cutting convention questions → file against `parachute-patterns`.
- Cite the workflow, the writer (which role), why it matters. Use cases move items up priority lists faster than generic asks.

This guide is the canonical reference. When patterns evolve, this doc updates first.
