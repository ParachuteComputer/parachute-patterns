# Tag data model

> One-line summary: a tag is a single SQL row carrying its identity, description, indexed fields, declared typed relationships, and parent-tag pointers. No notes-as-config for tag concerns. Vault is SQLite; tags belong in tables.

## Convention

The vault `tags` table holds everything about a tag in one row:

```sql
CREATE TABLE tags (
  name TEXT PRIMARY KEY,
  description TEXT,                  -- markdown blurb describing the tag
  fields TEXT,                       -- JSON: indexed metadata fields per `query-operators.md`
  relationships TEXT,                -- JSON: typed-link declarations per §Typed relationships below
  parent_names TEXT,                 -- JSON array of parent tag names (hierarchy)
  created_at TEXT NOT NULL,
  updated_at TEXT
);
```

**One tag = one row.** No sidecar table for fields. No config notes for hierarchy parents. Authoring is via direct API (`update-tag` MCP tool / vault admin SPA).

The legacy `tag_schemas` sidecar table and `_tags/<name>` config-note pattern (and the parallel `_schemas/*` pattern for note-validation defaults) are retired in favor of in-table state.

## Why

**Notes are content; system configuration is in tables.** Vault is a SQLite-backed agent-native knowledge graph, not a markdown-files-on-disk system. Configuration-as-data via "edit a `_tags/<name>` note" was historical accretion — it predates having a SQL identity for tags at all. Now that tags are first-class rows, the schema-on-tag and hierarchy-on-tag concerns belong as columns on that row, not as parsed JSON in another note's metadata.

The conflation between "this is a note" and "this is system configuration" was creating real confusion (see `parachute-patterns/research/parachute-data-model-shape.md`). Drawing the line cleanly: notes carry user content. Anything else is a SQL table or a column.

## Typed relationships

A tag declares the **expected** typed-link shapes for notes carrying that tag. The declaration is informational — used by agents to understand what links a typed note "should" have, and used by the UI to surface affordances. It is **not enforced** at write time (Phase 1 — see §Future evolution).

Schema shape (stored as JSON in `tags.relationships`):

```json
{
  "author": {
    "target_tag": "person",
    "cardinality": "one",
    "description": "the book's author"
  },
  "genre": {
    "target_tag": "genre",
    "cardinality": "many",
    "description": "thematic category"
  },
  "publisher": {
    "target_tag": "publisher",
    "cardinality": "optional",
    "description": "publishing house"
  }
}
```

### Cardinality vocabulary

Four named values, chosen for AI legibility (LLMs parse named cardinalities more reliably than `"1..*"` style numerics):

| Value | Meaning |
|---|---|
| `"one"` | Exactly one link of this relationship is expected (1) |
| `"optional"` | Zero or one (0..1) |
| `"many"` | Zero or more (0..*) |
| `"many-required"` | One or more (1..*) |

Stored verbatim as the JSON string. Agents reading the schema understand intent without parsing UML notation.

### Relationships compose with the existing `links` table

The vault `links` table already stores edges as `(source_id, target_id, relationship)`. The tag's declared relationships are the **expected shape**; actual links live in the `links` table. The schema declaration:
- Tells agents what to look for ("this `#book` should have an `author` link to a `#person`")
- Tells the UI what affordances to surface (an "Add author" button on a `#book` note's edit view)
- Stays informational — doesn't reject writes if a `#book` note has no author

Future enforcement (Phase 2 — see §Future evolution) layers validation on top.

## Hierarchy via `parent_names`

Tag hierarchy moves from `_tags/<name>` config notes to a column on the tag row.

```sql
-- example data:
INSERT INTO tags (name, parent_names) VALUES
  ('voice',        '["manual", "note"]'),     -- voice descends from manual + note
  ('manual',       '["note"]'),                -- manual descends from note
  ('note',         '[]'),                      -- root
  ('health/food',  '[]');                      -- string-form sub-tag has no explicit parent
```

The `getTagDescendants` resolver walks the `parent_names` graph backwards (build child→parent index, invert to parent→children, transitive closure). Functionally equivalent to today's `_tags/*` scanner; mechanically simpler.

The string-form sub-tag fallback (per `patterns/tag-scoped-tokens.md` §Storage details) STILL applies — `health/food` matches a `[health]`-allowlisted token via `rootOf("health/food") = "health"`, regardless of whether `parent_names` is set. The two mechanisms (parent_names-driven hierarchy + string-form fallback) coexist.

## Authoring surface

```
MCP tool: update-tag
HTTP:     PUT /vault/<name>/api/tags/<tag>
SPA:      vault admin tag editor
```

All three write to the same `tags` row. `update-tag` accepts `{ description, fields, relationships, parent_names }` and upserts.

There is no path that authors tag state by editing a markdown note. The `_tags/<name>` and `_schemas/*` config-note conventions are retired.

## Migration path

For a vault on the pre-existing model:

1. **Add new columns** to `tags`: `description`, `fields`, `relationships`, `parent_names`, `created_at`, `updated_at`. (Schema migration v13 → v14.)
2. **Populate from sidecar table**: copy each `tag_schemas(tag_name, description, fields)` row into the new tag row's columns.
3. **Populate parents**: for each note at `_tags/<name>`, parse `metadata.parents` and write to `tags.parent_names`.
4. **Verify**: confirm all schemas + parents migrated; provide a one-shot diff tool.
5. **Drop the sidecar**: `DROP TABLE tag_schemas`.
6. **Leave `_tags/<name>` notes in place** post-migration as historical record — they're harmless once the resolver reads from the new column. Operator can delete them via the admin UI when ready.
7. **Same for `_schemas/*` notes**: data lifts into a new `note_schemas` table (or a `tags.relationships`-style column on whatever surfaces it; out-of-scope for this doc).

The migration is one-way — Phase 1 doesn't preserve the option to revert to config-as-note. Aaron approved this 2026-05-03; the cleaner break is worth the irreversibility.

## Why retire config-as-note for these concerns

Three reasons:

1. **Conflates note vs configuration.** Operators look at the file tree and see `_tags/health` as a "note" — but it's not user content; it's system config. The leading underscore is a cargo-culted convention from filesystem-shaped systems (Obsidian, where a leading underscore is just a sort-prefix). In a SQLite-backed system, the convention earns its complexity poorly.

2. **The "edit your config in your note editor" affordance assumes a markdown-file-on-disk model.** Vault is SQLite. Operators interact with the vault via the admin SPA + MCP, not by opening a folder of files. The config-as-note pattern was solving a problem that doesn't exist in this architecture.

3. **The "vault export carries the config" argument** (cited in current `core/src/tag-hierarchy.ts` comments) collapses with this same realization. Export is its own surface (markdown export, JSON export). The export logic can serialize tag state from `tags` table → markdown frontmatter for Obsidian-shaped consumers, OR a dedicated `tags.json` for tooling consumers. Either way: the SOURCE of truth is the SQL row; the export is derived.

## Adoption

| Module | Action |
| --- | --- |
| **vault** | Phase 1 implementation: schema migration v14, `update-tag` API gains `relationships` + `parent_names`, `getTagDescendants` resolver swap, retire `tag_schemas` sidecar, leave `_tags/<name>` notes in place post-migration as harmless historical record. Same for `_schemas/*` retirement. Single PR on `ag-unforced-dev`. |
| **paraclaw** | No change — paraclaw doesn't touch tag schema state |
| **hub** | No change |
| **notes** | The Notes UI may surface tag schemas (declared fields + relationships) in note-edit views; tracked separately |

## Future evolution

| Extension | Sketch | When to revisit |
| --- | --- | --- |
| **Relationship enforcement** | Validate at write time that a `#book` note has an `author` link with cardinality `one`. Returns 400 on missing required relationship. | When operator pain emerges from notes lacking expected relationships |
| **Reverse-relationship inference** | `#book` declares `author → person`. Vault auto-infers `person → book` reverse with relationship `wrote`. | Phase 2 if helpful for query semantics |
| **Schema-defaults for note validation** (current `_schemas/*` pattern) | Move to a `note_schemas` table mirroring this design | Same arc; same sprint |
| **Schema versioning** | Optional `schema_version` field on tag rows; track migrations across schema changes | When a real schema-evolution incident happens |
| **Relationship typing per-link** (multiple authors with different roles) | Extend `links.metadata` JSON with `{ role: "primary-author" }` shape | When use-case appears |

## Adoption notes

- Aaron approved this design 2026-05-03 in the architecture-review thread.
- The retirement of config-as-note for tag concerns is a real simplification, not just refactor — the conceptual layer "what is a note" gets clearer.
- This unlocks `vault#240` (tag-rename cascade) — the cascade now touches one row + the body-text-rewrite, not three places + a config-note pipeline.
- Companion docs: `research/parachute-data-model-shape.md` (architectural reflection), `research/tana-deep-dive.md` (typed-graph context), `patterns/tag-scoped-tokens.md` (token-scope concerns layered on this model).
