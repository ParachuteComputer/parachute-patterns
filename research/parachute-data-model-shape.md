# Parachute data model — paths, tags, schemas, links, scope

> Architectural reflection. Not a pattern to adopt yet — a reading of the current state, a clarification of conceptual layers Aaron and team-lead have been conflating, and a survey of paths forward. Written 2026-05-03 in response to Aaron's request to "make sure I'm understanding what we're doing even here."
>
> Living companion to: `research/tag-scoped-tokens-survey.md`, `research/knowledge-tool-data-models.md` (in flight).
>
> **Status: DRAFT — Aaron is reading.**

---

## TL;DR

- **A tag has a schema; tag is not the schema.** A tag is an identity (a row in the `tags` table); the schema is OPTIONAL data attached to that tag (declared field shapes for indexed query). Aaron's recent framing is the precise one: "tag has a schema."
- **Tags currently use `name` as primary key.** No stable identity beyond the string. Renaming a tag means migrating every reference — `note_tags`, `tag_schemas`, links inside note bodies, scoped_tags JSON arrays, wikilink resolutions. Aaron's mental model assumed otherwise; reality must be reconciled before tag-rename-cascade is implemented.
- **Path is a single optional unique string.** Notes can have a path or not. Aaron's `(folder, name)` split idea is one shape; current is path-as-blob.
- **Wikilinks resolve by note-id reference, not by name string.** The `links` table stores `source_id` → `target_id` after wiki-form parsing. Rename of the target's path or name is silent for the link table — but the literal `[[Apples]]` text in the source's content still says "Apples." Resolution at write time, not at read time.
- **The conceptual layers that have been conflated:** identity (id-or-name), location (path or absent), label (name string for human/wikilink reference), shape (schema = field declarations), scope (token allowlist of tag names). At least five distinct concerns; the current model puts most of them on the same primary key.
- **The single most consequential decision in the next quarter:** does tag get a stable ID separate from its name? If yes, rename becomes cheap and the cascade in patterns#26 §Lifecycle is implementable in a small fix-PR. If no, every "rename" is a multi-step data-migration with audit-log + transactional rollback.

---

## 1. Current state — actual vault schema (2026-05-03)

From `/Users/parachute/.parachute/vault/data/default/vault.db` (Aaron's running install at vault rc.29):

### Tables

```sql
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  content TEXT DEFAULT '',
  path TEXT,                          -- nullable, unique-when-non-null
  created_at TEXT NOT NULL,
  updated_at TEXT,
  metadata TEXT DEFAULT '{}'          -- JSON
);

CREATE TABLE tags (
  name TEXT PRIMARY KEY               -- ⚠ name is identity
);

CREATE TABLE tag_schemas (
  tag_name TEXT PRIMARY KEY REFERENCES tags(name) ON DELETE CASCADE,
  description TEXT,
  fields TEXT                         -- JSON: { "field_name": { "type": "string", ... }, ... }
);

CREATE TABLE note_tags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_name TEXT NOT NULL REFERENCES tags(name),  -- ⚠ ref by name
  PRIMARY KEY (note_id, tag_name)
);

CREATE TABLE links (
  source_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  target_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  relationship TEXT NOT NULL,
  created_at TEXT NOT NULL,
  metadata TEXT DEFAULT '{}',
  UNIQUE(source_id, target_id, relationship)
);
```

Plus: `attachments`, `tokens` (with `scoped_tags TEXT` JSON column post-vault Phase 1), `notes_fts*` (FTS5 sidecar for full-text search).

### Live counts on Aaron's `default` vault

- 2280 notes
- 46 tags
- 10 tag_schemas (only ~22% of tags have a schema declared)
- 2556 note_tags entries (~1.1 tags per note average; distribution likely skewed toward heavy-tagged notes)
- 945 links
- 295 attachments

### Conventions encoded (NOT in the schema, but in code + docs)

- Tag hierarchy via `/`-prefix: tags named `health/food` are conceptually descendants of `health`. Stored as flat strings; hierarchy is computed by string-split and cached.
- `_tags/<name>` config notes: a note with path `_tags/health` is the OPERATOR-FACING way to author a tag's schema. The note's body / metadata declares `fields` for the tag. The schema row in `tag_schemas` is derived from this.
- Sub-tag schemas: `_tags/health/food` is the schema-author surface for tag `health/food`.

---

## 2. The conceptual layers (what's been getting conflated)

When Aaron and I have been saying "tag is a schema" or "tag-as-channel" or "tag-scoped tokens" we've been pointing at five distinct facets of the tag concept:

| Layer | Concrete embodiment | Question it answers |
|---|---|---|
| **Identity** | A row in `tags` (today: `name TEXT PRIMARY KEY`) | "Is this the same tag as that one?" |
| **Label / name** | The `name` column (today: also the PK) | "What does the user / agent type to refer to this tag?" |
| **Hierarchy position** | `/`-prefix in the name (`health/food` is below `health`) | "What other tags is this related to?" |
| **Schema** (optional) | A `tag_schemas` row, authored via `_tags/<name>` config note | "What indexed fields do notes with this tag carry?" |
| **Scope** | A `tokens.scoped_tags` JSON array element (just shipped in vault Phase 1) | "Which tokens / agents can see/write notes with this tag?" |

**The conflation problem**: today's schema makes the FIRST TWO collapse — name IS identity. So when you "rename a tag," you're not just changing a label; you're changing identity, and every reference (note_tags, tag_schemas FK, scoped_tags JSON, link-text in notes, find-path edges) has to be migrated.

**The architectural choice** is whether to split identity from label. That has cascading consequences across all five layers.

### Same conflation on the path side

Path has at least three distinct facets:

| Layer | Concrete embodiment | Question it answers |
|---|---|---|
| **Tree position** | The slash-prefix part of `path` (e.g., `Memos/2026/05/`) | "Where in my file tree does this live?" |
| **Name** | The leaf segment of `path` (e.g., `welcome`) | "What's it called for wikilink + display?" |
| **Tag-schema location** | Notes whose path starts with `_tags/` | "Is this note a schema declaration for tag X?" |

These three are also collapsed today: path is one string; renaming a folder vs renaming a note vs renaming a schema all look the same.

Aaron's idea (split path into `(folder, name)`) untangles the first two. The third is harder because it requires deciding whether `_tags/<name>` stays as a path-encoded convention or becomes a separate schema table with no path coupling.

---

## 3. Walking the use cases

Let me spell out what a few things actually mean against the current model. This makes the architectural choices concrete.

### Use case A: "Tag a note with `#health`"

User adds `#health` to a note in their editor. What happens:

1. The parser sees `#health` in the body, extracts the tag name.
2. Vault upserts a `tags` row: `INSERT INTO tags(name) VALUES ('health') ON CONFLICT DO NOTHING`.
3. Vault upserts a `note_tags` row: `(note_id, 'health')`.
4. The literal text `#health` stays in the note body. It is the canonical reference to the tag at READ TIME.

If `health` is later renamed to `wellness`:
- The `tags` row's PK changes (or row is deleted-and-re-inserted)
- All `note_tags` rows referencing 'health' need to be updated to 'wellness'
- All `tag_schemas` rows similarly
- All literal `#health` text in note bodies needs to be rewritten (otherwise next reparse re-creates the `health` tag)
- All `scoped_tags` JSON arrays with `'health'` → `'wellness'`
- Audit log entry per cascade

That's the implementation cost of rename today.

### Use case B: "Add a schema to `#health`"

Operator creates a note at path `_tags/health` with a body declaring fields:

```yaml
---
description: Health-related notes
fields:
  doctor: { type: string, indexed: true, description: "Provider name" }
  date: { type: date, indexed: true, description: "Date of event" }
---
```

What happens:
1. The path `_tags/health` is recognized by the schema-detection logic (probably in `core/src/notes.ts` or a hook on note write).
2. The note's metadata is parsed; the `fields` block is extracted.
3. A `tag_schemas` row is inserted: `('health', '<description>', '<json-of-fields>')`.
4. Future notes tagged `#health` get their `metadata` indexed against the declared fields.

The tag itself is just `'health'` — the schema is data attached to the tag identity.

### Use case C: "Rename `#health` to `#wellness`"

Today: substantial. See use case A's rename steps.

In Aaron's preferred world (tags have stable IDs):
1. The `tags` row's `name` field is updated. The tag's underlying ID is unchanged.
2. `note_tags`, `tag_schemas`, `scoped_tags` JSON — none of these need updating, because they reference by ID.
3. Note body text `#health` → `#wellness` still needs rewriting (so re-parse doesn't re-create `health`). UNLESS the parser stores tag references by ID at parse time too — which is a much bigger change.
4. The `_tags/health` path renames to `_tags/wellness` — IF the path is name-derived. (If path is operator-controlled and only convention-linked, the path can stay; the linkage is broken; UI refreshes.)

The cheapest cascade in the stable-ID world is still: update `tags.name`, rewrite all `#name` text in bodies, rename `_tags/name` path. Not free, but bounded.

### Use case D: "Wikilink `[[Apples]]` resolves"

User writes `[[Apples]]` in a note's body. What happens:

1. At write time, vault's wikilink parser scans the body, finds `[[Apples]]`.
2. It searches for a note named `Apples` — by path leaf? By a name field? Today, by path-suffix match (e.g., a note at path `Foods/Apples` would match).
3. If found, a `links` row is created: `(source_id, target_id_of_Apples, 'wikilink', ...)`.
4. If not found, the wikilink is "dangling." Some tools auto-create a stub note; vault's behavior here is worth confirming.

Rename impact:
- If you rename the note at `Foods/Apples` → `Foods/Pears`, the `links` row still points to the same `target_id` (correct — id is stable). But the LITERAL TEXT `[[Apples]]` in the source's body is now misleading — it says "Apples" but resolves to "Pears."
- Obsidian's famous behavior: re-write all `[[Apples]]` → `[[Pears]]` in source bodies on rename. This is a real feature, not free.

### Use case E: "Token scoped to `#health` reads notes"

This is what we just shipped (vault Phase 1 of patterns#24 / #26):

1. Token has `scoped_tags = ["health"]` (root-only).
2. On every read request, vault expands `["health"]` via two mechanisms (per patterns#26 §Storage details):
   - Schema-driven: `getTagDescendants("health")` walks the `_tags/<name>` hierarchy cache → `{health, health/food, health/doctor, ...}` (only tags WITH declared schemas)
   - String-form fallback: for each note tag `t`, if `t.split("/")[0] === "health"`, allow.
3. The note matches if any of its tags is allowed.
4. Out-of-scope notes return 404 (no existence-leak).

Rename impact: if `#health` is renamed to `#wellness` and the cascade (use case C) updates `scoped_tags` from `["health"]` to `["wellness"]`, the token continues to work. Without the cascade, the token sees nothing post-rename.

---

## 4. Open questions / tensions

### Q-IDENTITY: Should tags get a stable ID?

**Today**: `tags(name TEXT PRIMARY KEY)`. Identity = name.

**Alternatives**:
- **A. Add stable `id`, keep name as queried-by surface.** Migration: add `id INTEGER PRIMARY KEY` (or UUID), make `name` UNIQUE. Update `note_tags`, `tag_schemas`, link references to FK by id. Existing JSON in `scoped_tags` either migrates to id (would need parsing on every auth check) OR stays as name (rename cascade still has to update JSON).
- **B. Keep name-as-identity but make rename atomic.** Wrap the multi-step rename in a transaction. Easier migration; harder rename (always touches lots of rows).
- **C. Hybrid: id-as-identity in the data model, name-as-surface for everything user-facing.** Most expensive migration but cleanest long-term.

**My read**: A is the right move when we're ready to invest in it. C is over-engineering until we have a reason to detach name from API surface.

### Q-PATH: Single string vs (folder, name) split?

**Today**: `notes.path TEXT` — single string, optional, unique.

**Aaron's idea**: split into `folder TEXT` + `name TEXT`, unique on the pair.

**Pros of split**:
- Renaming the leaf (note name) without changing folder is one column update
- Folder-level operations become natural (list-by-folder, folder-default schema)
- Clarifies wikilink resolution: links resolve to a `name`, not a path-suffix
- Disentangles "where" from "what's it called"

**Cons of split**:
- Migration: parse 2280 existing path strings, split on last `/`. Existing API takes `path` as a single string — backwards-compat layer needed.
- Wikilink rename auto-follow gets MORE valuable + more complex (renaming the name needs to rewrite `[[name]]` in source bodies)
- Folder-as-permission-boundary becomes tempting — but that's another scope axis on top of tag-scope; consider before adopting

### Q-SCHEMA-LOCATION: Are schemas authored as `_tags/<name>` notes, or in a dedicated schema table?

**Today**: `_tags/<name>` notes. Operator authors a note; vault parses metadata; populates `tag_schemas`. This is the "tags as config notes" pattern Roam/Logseq pioneered.

**Alternative**: dedicated schema authoring surface. Move `_tags/<name>` from "is a note in the path tree" to "is a row in `tag_schemas` with no path coupling." Operator authors via admin UI form, not via note-editing.

**Trade-off**: the current design lets operators version-control schemas via note history, link to schemas like any other note, share schemas via wikilink. The alternative is cleaner separation but loses these affordances.

**My read**: keep schemas as config notes for now; it's a productive conflation. If the (folder, name) split happens, the convention becomes `folder=_tags, name=<tag>` which preserves everything.

### Q-RENAME: When a tag is renamed, what happens?

This was settled per patterns#26 §Lifecycle: cascade. Sub-tags + tokens + notes auto-update. **But the implementation cost depends on Q-IDENTITY.** If tags stay name-as-PK (today), every rename is a multi-table migration. If tags get stable IDs (Q-IDENTITY answer = A), rename is a single column update + body-text rewrite.

### Q-WIKILINK-RESOLUTION: How do `[[X]]` references resolve, and what happens on rename?

**Today (need to confirm)**: probably resolves by path-leaf match; `links` table stores resolved `target_id`. Rename of target: link FK stays valid; literal text in source becomes misleading.

**The Obsidian behavior**: auto-rewrite source bodies on target rename. This requires an event hook + body-text mutation. Not free, but it's a real feature operators expect.

### Q-SCOPE-AXIS: Tags-only, or tags + paths + metadata?

Tag-scope shipped (vault Phase 1). The pattern doc (patterns#24/#26) explicitly defers metadata-scope (patterns#25), multi-vault (deferred), and path-scope (not even filed).

The question: as Parachute evolves, will operators want to scope agents by:
- Tags only? (current design)
- Tags + folders/paths? ("everything in `Work/`")
- Tags + sources? ("everything Prism imported")
- Tags + time? ("only notes from this month")

These are orthogonal axes. patterns#24 chose tags-only because it's the most operator-natural axis. The architecture should not preclude adding more axes.

---

## 5. Paths forward — three coherent shapes

### Shape α: "Stay with what works"

**Keep**: name-as-PK for tags, single-string path for notes, `_tags/<name>` for schemas, current tag-scope as the only scoping axis.

**Acknowledge**: rename-cascade is multi-step and slow; wikilink rename auto-follow needs a background pass; schema author-by-note coupling stays.

**Investment**: implement the rename cascade (vault#240) as a multi-table migration with proper transaction + audit log. ~2-3 day's work. Schema unchanged.

**Why pick this**: minimum disruption. Existing data + APIs unchanged. Future evolution comes through small additions (metadata scope per patterns#25, etc.) layered on top.

### Shape β: "Modest evolution — split path, stabilize tags"

**Change**:
- Add stable `tag_id INTEGER` to `tags`; migrate references to FK by id
- Split `notes.path` into `folder TEXT` + `name TEXT`; unique on the pair
- `_tags/<name>` becomes `(folder='_tags', name='<tag>')`
- Wikilinks resolve by `(name)` first, fall back to `(folder, name)` for disambiguation

**Investment**: substantial migration + API rewrite. ~1-2 weeks if focused.

**Wins**:
- Cheap rename for tags
- Clean folder-level ops (list, permissions, defaults)
- Wikilink resolution clarified
- Backwards-compat layer for path-as-string callers

**Why pick this**: Aaron's instinct is correct; the path namespace conflation IS uncomfortable and grows worse over time. Get ahead of it before the vault grows past 10k notes.

### Shape γ: "Bigger reshape — typed objects with relations"

**Change**: lean toward an Anytype/Tana-style typed-object model. Notes become "objects of type X"; types declare their schema; relations replace ad-hoc links + tags.

**Investment**: this is a major rewrite (~4-6 weeks); affects every API and the SPA admin surface.

**Wins**:
- Cleaner data model long-term
- Better support for future patterns (typed agents, typed permissions, typed-relations)

**Why pick this**: only if Aaron wants Parachute to be more like Anytype than Obsidian. Big bet.

**My recommendation**: not now. Stay with Obsidian-shaped (notes-as-files-with-tags-and-links) until the operator pain demands more.

---

## 6. What I'd recommend

**For the next 1-2 quarters**: Shape α (stay with what works) + targeted improvements:

1. **Implement vault#240 (tag rename cascade)** as a multi-table migration with audit log. Don't restructure the schema first; do the cascade in name-as-PK mode and accept the cost.
2. **Implement wikilink rename auto-follow** if it's not already there. Rename should rewrite source bodies. Vault tentacle to confirm current state and file an issue if it's not implemented.
3. **Defer Shape β until Aaron has a concrete operator-pain scenario** — e.g., a real-world rename storm, or a folder-permission requirement. The (folder, name) split is the right direction but premature without driving force.
4. **Don't pursue Shape γ.** Anytype/Tana shape would be a different product.

**For the architecture-level decisions (Q-IDENTITY, Q-PATH, Q-WIKILINK-RESOLUTION)**: file as design issues for Q4 2026 reviews. Today's data scale (2280 notes, 46 tags) doesn't yet apply real pressure to these.

---

## 7. Open questions for Aaron

1. **Tag identity**: do you want me to file a design exploration for "stable tag IDs" (Q-IDENTITY shape A), or stay with name-as-PK and just implement the cascade?
2. **Path split timing**: vault#238 is filed but has no design doc or PR. Do you want me to draft a design doc for it now, or wait until you have a concrete pain point that pushes for it?
3. **Wikilink rename auto-follow**: I haven't confirmed whether vault implements this today. Want me to check + file an issue if not?
4. **Tag-schema authoring location**: stay with `_tags/<name>` as config notes (current), or move to a dedicated schema-authoring surface? Current convention is productive but couples schema to path.
5. **Schemas without tags?** (Edge case worth deciding.) Today every schema is tag-bound. Do we ever want schemas as standalone things (e.g., a "person" schema that's referenced from multiple tags)?

---

## Companions

- `research/tag-scoped-tokens-survey.md` — industry survey on tag-scoped tokens (already merged)
- `research/knowledge-tool-data-models.md` — broader survey on how Obsidian / Logseq / Notion / Anytype / TiddlyWiki handle paths/tags/schemas/links/permissions (in flight; complementary)
- `patterns/tag-scoped-tokens.md` — canonical token-scope design (just merged)
- `patterns/module-json-extensibility.md` — module protocol
- `patterns/oauth-scopes.md` — OAuth scope shape

---

*Reading guide for Aaron: skim §1 to confirm the current schema matches your mental model. Read §2 carefully — the conceptual layers — and push back if any feels wrong. §4 is the questions; §6 is my lean. §5 is alternatives.*
