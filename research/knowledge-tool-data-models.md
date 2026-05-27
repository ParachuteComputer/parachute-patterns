# Knowledge tool data models — a survey

**Status:** research input for Parachute Vault architecture review
**Date:** 2026-05-02
**Scope:** how mainstream knowledge / note tools structure paths, names, tags, schemas, and links — and what trade-offs each pattern carries for a system like Parachute Vault.

This doc surveys eleven tools, focused on the relationships between **identity, path, tags, schemas, links, and permissions**. Sources are cited inline by URL. Speculation is avoided; where a doc is silent, the doc says "silent".

---

## 1. TL;DR

1. **Two camps on note identity.** File-based tools (Obsidian, TiddlyWiki) use **name-as-key**; database-backed tools (Logseq, Roam, Notion, Anytype, Tana, Capacities) use **stable UUIDs**, with names being mutable display strings on top. Parachute's `id (TEXT pk)` + optional unique `path` puts it in the "stable ID, mutable path" camp — same family as Logseq/Notion/Anytype.
2. **Path is rarely a (folder, name) tuple in successful tools.** Filesystem-bound tools store a single string; graph tools elide path entirely. The (folder, name) split shows up only when the underlying storage is a real filesystem, and even then is usually flattened to a single string for resolution.
3. **Tag identity stability matters most when schemas attach to tags.** Tools that bind schemas to tags (Logseq classes, Tana supertags, Anytype types, Capacities object types) all give tags **stable IDs** with mutable display names. Tools that treat tags as pure pivots/labels (Obsidian, TiddlyWiki, Roam page-as-tag) get away with name-as-identity, but pay for it on rename.
4. **Schema-attached-to-tag is the dominant pattern for typed notes.** Logseq classes, Tana supertags, Anytype types, Capacities object types, and Notion data sources all converge on: *applying a tag/type to a node implies a property schema*. Parachute's `_tags/<name>` config note is a structural cousin — schema-as-data, authored in the same surface as content.
5. **Wikilink rename auto-follow is a *runtime* index, not a stored pointer.** Obsidian rewrites the link text on rename only because the editor is the rename channel; external rename breaks links. Logseq/Roam/Anytype/Notion link via stable ID under the hood, so display name changes don't break anything — display is rendered from the current name, not stored.
6. **Hierarchical tags are nearly always slash-as-string.** Obsidian, Logseq, and Tana all use `parent/child` string conventions. Only Anytype/Capacities/Tana support real type inheritance (parent-pointer in the schema), which is a different feature than display hierarchy.
7. **Permissions land in two patterns.** Page-tree inheritance (Notion: parent grants flow to children, with overrides) or whole-space role membership (Anytype channels, Tana workspaces). Property-driven access (Notion's "page-level access via Person property") is the rarest and most powerful — and it presupposes a typed schema. Tag-scoped tokens (Parachute's Phase 1) are unusual; nothing surveyed scopes by tag root.
8. **"Everything is X" axis splits the field.** Roam/Logseq: blocks. Obsidian: files. Notion: pages-and-databases. Anytype/Tana/Capacities: typed objects. Parachute's "tags-as-config-notes" makes notes the universal substrate, with structure layered as data — closer to TiddlyWiki's "everything is a tiddler" than to any of the typed-object systems.
9. **Schema-as-data scales further than schema-as-code.** Tools that store schemas inside the user's own data (Tana fields-on-supertag, Notion property objects, Anytype JSON-bundled types, Logseq class properties) let users evolve schemas without touching code. Schema-in-code (TiddlyWiki, raw Obsidian) leaves users to convention; Dataview-style indexing emerges to fill the gap.
10. **The rename-vs-stable tension is the deepest split.** Tools that treat name as identity (Obsidian, TiddlyWiki) get filesystem interop and human readability. Tools that decouple name from identity (everyone else surveyed) get rename safety and richer relations. You can't have both without paying for an indirection layer — and the indirection layer is exactly what Parachute's `links` and `note_tags` tables are.

---

## 2. Per-tool survey

### 2.1 Obsidian

**Identity / path.** A note is a file on disk. The stable identifier is its **path** (vault-relative, including the `.md` extension). Obsidian has no UUID layer; the path *is* the identity. Folder structure is the path string — not a (folder, name) tuple. Properties (formerly "frontmatter") are YAML at the top of the file with typed values: text, list, number, checkbox, date, datetime ([Obsidian Help — Properties](https://help.obsidian.md/properties)). There is no per-note schema; users define a global "Properties view" that knows about field names and assumes types, but enforcement is best-effort and global.

**Tags / schemas.** Tags are **strings**, not entities. They appear inline as `#foo/bar` or in YAML `tags: [foo/bar]`. Hierarchy is by slash convention only — `#animals/dogs` is conceptually under `#animals` but there is no parent pointer; the tag pane parses the slashes at display time ([Obsidian Help — Tags](https://help.obsidian.md/tags)). There is no tag identity: rename is a vault-wide find-and-replace, not a referential update. There is no per-tag schema; the property system is global. Plugins like Dataview fill the schema-query gap by indexing frontmatter at runtime.

**Links / permissions.** Wikilinks `[[X]]` resolve by **shortest unique filename**. If `Math.md` exists once in the vault, `[[Math]]` works; if it exists twice, you must write `[[Folder/Math]]`. The resolution order is exact filename → normalized (spaces/hyphens/underscores collapsed) → path ([Obsidian forum — Settings: New Link Format](https://forum.obsidian.md/t/settings-new-link-format-what-is-shortest-path-when-possible/6748), [obsidian_wikilink_rules](https://gist.github.com/dhpwd/9bb86c53b69cb63e09ccca42e3bf924c)). Rename auto-follow is a *rewrite* operation: when you rename inside Obsidian, every `[[old]]` is rewritten to `[[new]]`. External renames break every link ([Desktop Commander — Bulk Rename](https://desktopcommander.app/blog/obsidian-bulk-rename-files/)). Section-link renames (`[[file#section]]`) are not auto-updated, and Dataview-embedded wikilinks aren't either ([Obsidian forum — Wikilinks not updated...](https://forum.obsidian.md/t/wikilinks-not-updated-on-file-rename-when-part-of-a-dataview-query/70043)). Obsidian is single-user; sync/sharing is filesystem-level. No native permission model.

### 2.2 Logseq

**Identity / path.** Every block has a **stable UUID** (`:block/uuid`). Pages are blocks-with-`:node/title`. Path is essentially absent from the data model — pages live in a flat namespace (file-graph mode keeps `pages/` and `journals/` directories on disk, but the database treats them as a flat keyed-by-title space) ([Logseq Database Schema](https://deepwiki.com/logseq/logseq/4.2-database-schema-and-validation)). Content is stored as a Datascript graph. Renaming a page changes `:node/title` but `:block/uuid` is unchanged, so block references survive.

**Tags / schemas.** Tags and pages are the **same thing** — `#foo` is shorthand for `[[foo]]` ([Logseq forum — page links, tags, and properties](https://discuss.logseq.com/t/the-difference-between-page-links-tags-and-properties/8393)). Logseq DB v1+ introduced **classes**: a class is a tag with an attached property schema. When a block has `:block/tags` pointing to a class entity, the schema declares which properties are required/recommended, with type validation via Malli ([DeepWiki — Property Management](https://deepwiki.com/logseq/logseq/3.2-property-management)). Property values flow through `:db.cardinality/one` or `:many`. Schema is authored in the UI, stored as data in the same Datascript DB. This is the closest analog to Parachute's `_tags/<name>` config note model — schema-as-first-class-data, edited in the same surface as content.

**Links / permissions.** Page links `[[X]]` resolve by **title string**. Block references `((uuid))` resolve by UUID and are immune to renames. When you rename a page, `[[X]]` strings in block content get rewritten — display and storage are the same here. Logseq is local-first; multi-user comes via external sync (Git, iCloud, Logseq Sync). No native permission model beyond filesystem.

### 2.3 Roam Research

**Identity / path.** Roam is a **Datomic graph**. Every block is a datom-set keyed by a 9-character `:block/uid` (e.g. `((GGv3cyL6Y))`) plus an internal entity ID. Pages are blocks distinguished by `:node/title`; paragraphs have `:block/string` ([Zsolt — Roam Data Structure](https://www.zsolt.blog/2021/01/Roam-Data-Structure-Query.html)). There is no path — only a hierarchical `:block/parents`/`:block/children` tree per page, and a flat page namespace.

**Tags / schemas.** Tags are page references — `#foo` and `[[foo]]` both create an edge to the page named "foo". Roam has **attributes** as a third primitive: a block whose string is `Status:: Active` writes a triple `(parent-block, Status, Active)`. Attributes are name-based (the attribute "Status" is just a page named Status). Roam has no schema layer — the convention is that you write `Status::` as the first child of any block of a certain "type", and queries pivot on that. Templates emulate schema; the system itself is schema-less ([Ness Labs — pages, tags, attributes](https://nesslabs.com/pages-tags-attributes-roam-research)).

**Links / permissions.** Page links resolve by title; block refs by 9-char UID. Renaming a page rewrites `[[old]]` to `[[new]]` everywhere because the underlying ref points to the entity, and the markdown is regenerated from the current title. Roam supports multi-user via graph sharing; permissions are graph-level (read/write per user on a graph). No per-page permissions.

### 2.4 Notion

**Identity / path.** Pages and databases (now called **data sources**) have **stable UUIDs** ([Notion Property Object](https://developers.notion.com/reference/property-object)). Pages live in a tree (parent → child), so "path" is implicit through the parent chain rather than a string. A database is a typed container; rows are pages with property values conforming to the database's schema. Since the September 2025 API change, one *database* can hold multiple *data sources* — the data source is the schema-bearing unit, the database is the UI grouping ([Notion Databases Explained](https://www.simonesmerilli.com/life/notion-database-data-source)).

**Tags / schemas.** Notion has no global tag concept. The equivalent is a **select / multi-select property** on a database — its values are the "tags" for that database, with their own option IDs and colors. Schema is per-database: the database's `properties` object defines columns with 21 supported types (rich_text, number, date, select, multi_select, status, relation, rollup, formula, files, people, etc.) ([Notion Property Object](https://developers.notion.com/reference/property-object)). Schema lives **as metadata on the database object**, not as user-authored content. Schema size is capped at 50KB.

**Links / permissions.** In-text mentions resolve by page UUID; the display title is rendered from the current page name, so renames are free. Database **relations** are first-class typed properties with a `data_source_id` pointing to the target schema; bidirectional relations create a synced inverse property ([Notion Help — Relations and Rollups](https://www.notion.com/help/relations-and-rollups)). Permissions are page-tree based: parent permissions inherit to children with overrides, with four levels (Full Access / Can Edit / Can Comment / Can View). Databases add "Can edit content" (edit rows but not schema) ([Notion Help — Sharing & Permissions](https://www.notion.com/help/sharing-and-permissions)). On Business/Enterprise, **page-level access rules** can grant access by a property value — e.g. "users in the `Owner` person property can edit". This is the rarest and most powerful pattern surveyed: ABAC via the schema itself.

### 2.5 TiddlyWiki

**Identity / path.** A tiddler is a **JS object keyed by `title`** in an in-memory map ([TiddlyWiki Datamodel](https://tiddlywiki.com/dev/static/Datamodel.html)). Title *is* the identity — there is no UUID, no path. Folders don't exist; the tiddler space is flat. Every tiddler has a `text` field plus arbitrary user fields (name:value). The fields system is open: any tiddler can have any field ([TiddlerFields](https://tiddlywiki.com/static/TiddlerFields.html)).

**Tags / schemas.** Tags are a **`tags` array field** on each tiddler — values are strings that happen to be other tiddler titles. A tag with a tiddler of the same name doubles as a "category page" with rendering rules ([TiddlyWiki Tagging](https://tiddlywiki.com/static/Tagging.html)). There is no schema layer; the closest is a *system tag* (e.g. `$:/tags/Stylesheet`) that triggers TiddlyWiki to treat the tagged tiddler as part of a system function. Field names are conventions; types are inferred at filter time. Hierarchy via tags is by string convention plus the special `list-after`/`list-before` fields for ordering siblings.

**Links / permissions.** Wiki links `[[X]]` resolve by tiddler title — no path, no ID. Rename rewrites links across the wiki via the editor's rename action; external edits to the underlying file (when persisted via plugin) break things. TiddlyWiki has no native permission model — it's a single HTML file or single-user node-server. Multi-user TiddlyWiki ships via plugins (Bob, NodeJS edition with users.csv) and grants are tiddler-pattern based.

### 2.6 Anytype

**Identity / path.** Every object — including types and relations themselves — has a **unique key** and lives inside a **space** (formerly called channel) ([DeepWiki — Object Types and Relations](https://deepwiki.com/anyproto/anytype-heart/3.1-object-types-and-relations)). There is no path; the data model is a graph. Object Types (Page, Task, Person, custom types) and Relations (name, due-date, status, ...) are themselves objects, declared in JSON bundles for system types and as user objects for custom ones.

**Tags / schemas.** Schema is **tied to types** — every object has a type, and the type declares which relations apply. A relation can be Text, Number, Date, Select, Multi-select, Email/Phone/URL, Checkbox, File, or Object (a typed reference) ([Anytype Docs — Properties](https://doc.anytype.io/anytype-docs/getting-started/types/relations)). Tags-as-strings live as multi-select relation values. Types can inherit (sub-types) — so the "schema graph" is itself a graph, not a flat list. This is the cleanest typed-object model surveyed: types are first-class, schemas live with types, and types are shareable across spaces.

**Links / permissions.** Object references are by stable key; display name is rendered from the current state. Spaces are encrypted containers with **per-space roles**: Owner, Editor, Viewer ([Anytype Docs — Channels](https://doc.anytype.io/anytype-docs/getting-started/vault-and-key/space)). There is no per-object access control yet (active feature request); permission is whole-space. Compare to Notion's per-page tree model — Anytype trades granularity for cryptographic space isolation.

### 2.7 Tana

A node has a stable internal ID; Tana inherits the Roam-like outliner shape ([Tana — Intro to nodes, fields, supertags](https://tana.inc/articles/intro-to-nodes-fields-and-supertags)). No path concept. **Supertags** are tags-with-schema: applying one attaches a template of fields and child nodes. Fields have types (Plain, Options, Instance, Date, ...) and a *discoverable* flag that lifts their definition into the global schema for reuse ([Tana — Fields](https://tana.inc/docs/fields)). Supertags can inherit (a `Sub-task` from `Task`). Schema is authored in the same outliner where content lives — supertag config nodes *are* Tana nodes. This is the strongest direct analog to Parachute's `_tags/<name>` pattern: schema-bearing nodes that look identical to content nodes, with supertags providing the type relation. Links use stable IDs; display follows the current name. Permissions are workspace-level.

### 2.8 Capacities

An object has a stable ID and **always has a type**; there is no untyped object ([Capacities — Object Types](https://docs.capacities.io/reference/content-types)). Types include built-in basics (Page, Tag, Image, Weblink, File, Tweet, AI Chat, Query, Table) and user-defined Custom Object Types. Tags are themselves *a basic object type* — a Tag is an object you can apply to other objects, and it can carry its own properties. Schema is per-type: properties have name, description, icon, and type ([Capacities — Properties](https://docs.capacities.io/reference/properties)). Object-typed properties allow typed cross-references with optional bidirectional sync. Custom types and properties propagate to all instances; you can't have one-off properties on a single object without defining them on the type first. No documented fine-grained permission model; primarily single-user with cloud sync.

### 2.9 Reflect

Daily-note centric — opening Reflect drops into today's note, with notes scrolling as a chronology ([Reflect Academy — Using backlinks and tags](https://reflect.academy/using-backlinks-and-tags)). Two organizational primitives: backlinks `[[X]]` (associations) and tags (flat-string categorization). No schema/property layer; the explicit design choice is "no hierarchy, only association". AI is the structuring layer instead. Single-user. The useful lesson is the *deliberate absence* of schema — Reflect bets AI-over-flat-text beats user-authored schema for personal knowledge.

### 2.10 Athens (archived)

Open-source Roam clone on Datascript ([Athens GitHub](https://github.com/athensresearch/athens)). Block-based, UUID-keyed, attributes-by-convention — same shape as Roam. Archived 2022. Community lessons: building a Datascript-backed graph is a heavy engine investment; the schemaless graph is hard to make legible to new users; collaborative editing on a graph DB is a research problem ([HN — Athens Launch thread](https://news.ycombinator.com/item?id=26316793)). Supports the broader pattern: schema-less graphs are pure but ergonomically punishing without a typing layer on top.

### 2.11 schema.org

Not a tool but the canonical "things have types and types have properties" web vocabulary. Three primitives: Types, Properties, Enumerated Values. Types form a multi-inheritance hierarchy; properties have `domainIncludes` and `rangeIncludes` — both fuzzy ("expected", not enforced) ([Schema.org Data Model](https://schema.org/docs/datamodel.html)). The flexibility doctrine is explicit: "Schema.org is based on a very flexible datamodel, and takes a pragmatic view of conformance." Relevance for Parachute: schema.org is the deep-time argument that **types-with-properties-with-fuzzy-conformance** is the right shape for heterogeneous knowledge. The "expected, not enforced" stance is the model Parachute should consider for `_tags/<name>` — declare what's indexed/queryable without rejecting notes that don't match.

---

## 3. Cross-cutting comparison

| Tool | Note ID | Path/location | Tag identity | Tag hierarchy | Schema location | Link resolution | Rename auto-follow | Permissions |
|---|---|---|---|---|---|---|---|---|
| **Obsidian** | path string | single string (vault-relative) | string only | slash convention | global property names; per-tag schema absent | shortest unique filename | yes (in-app rename); no (external) | filesystem only |
| **Logseq** | block UUID | flat title space | class entity (UUID) | slash + class inheritance | classes (data) | title for `[[]]`, UUID for `(())` | yes (UUID-backed) | filesystem / sync |
| **Roam** | 9-char UID | flat title space | page reference (entity) | slash convention | none (attributes by convention) | title for `[[]]`, UID for `(())` | yes | per-graph |
| **Notion** | UUID | parent-tree (implicit) | select option ID per database | none (per-database options) | per-database `properties` (metadata) | UUID, title rendered live | yes (free) | page-tree inheritance + property-driven (Biz+) |
| **TiddlyWiki** | title string | flat space | string in `tags` field | string + list-after/before | none (field name convention) | title | yes (in-app rename) | plugin-dependent |
| **Anytype** | object key | none (graph) | type entity (key) | sub-types (parent pointer) | type bundles (JSON for system; objects for user) | key, title rendered live | yes (free) | per-space role (Owner/Editor/Viewer) |
| **Tana** | node ID | none (outline) | supertag entity | supertag inheritance | supertag config nodes (data) | ID, title rendered live | yes | workspace |
| **Capacities** | object ID | none | tag is a basic type | none documented | per-type schema | ID | yes | single-user / cloud sync |
| **Reflect** | UUID (inferred) | flat | string | none | none (no schema) | name | yes | single-user |
| **Athens (archived)** | block UID | flat title space | page entity | slash convention | none (attributes) | title for `[[]]` | yes | per-graph |
| **schema.org** | IRI | none (web) | type IRI | multi-inheritance | type definition (RDF) | IRI | n/a | n/a |
| **Parachute Vault** | TEXT pk | optional unique TEXT | tag entity (id) + name | name-prefix `/` + `_tags/<name>` | `_tags/<name>` config notes (data) | name (with path fallback?) | via `links` table | tag-scoped tokens (Phase 1) |

---

## 4. Patterns Parachute could adopt vs reject

### Adopt

- **Stable tag IDs with mutable names — already in.** Parachute's `tags.id` decoupled from `tags.name` puts it in the typed-object camp (Logseq class, Anytype type, Tana supertag, Capacities type). Rename a tag → all `note_tags` rows still resolve. This is non-negotiable once schemas attach to tags; without it, schema-rename becomes a vault-wide rewrite.
- **Schema-as-data via `_tags/<name>`.** Validated by Tana (supertag config nodes) and Logseq (class properties stored in Datascript). The pattern survives: schemas evolve as fast as content because they live in the same surface. The user authoring tools that work for notes work for schemas. Parachute should keep this and double down — explicitly version `_tags/<name>` notes the same way other notes are versioned.
- **Wikilink resolution by tag/name with fallback to path.** Matches Obsidian's "shortest unique" plus a path disambiguator. The `links` table acts as the *index* that makes rename auto-follow possible without rewriting note content. (Obsidian rewrites; Parachute can re-resolve at read time. Re-resolution at read is more flexible.)
- **Hierarchical tags via name-prefix.** All the convergent evidence (Obsidian, Logseq, Tana) says the slash-string convention works fine for *display* hierarchy. Reserve actual parent-pointer trees for sub-typing if/when Parachute introduces tag-of-tag inheritance.
- **Property-driven access for the Cloud tier (eventually).** Notion's "page-level access by Person property" is the most powerful pattern surveyed and the one cloud-multi-user Parachute will eventually want. It composes naturally with `_tags/<name>` schemas: a tag schema field with type "person" can drive ACLs, no separate ACL system needed.

### Reject (or defer)

- **(folder, name) tuple as the storage shape.** No surveyed tool benefits from the split at the data-model layer; even file-based tools store path as a single string and let the filesystem handle the slash. Parachute's `path` column being a single TEXT is the right call — keep it that way.
- **Wikilink rewrite on rename.** Obsidian rewrites note content because it has no link index. Parachute *has* a `links` table — re-resolve at read time, don't rewrite content. This avoids the Dataview-edge-case class of bugs Obsidian has lived with.
- **Schema-by-database (Notion).** Tying schemas to containers (databases) over types (tags) is what forces Notion's "one type per database" awkwardness. Parachute's tag-as-schema-carrier is more flexible: a note can have multiple tags, hence multiple schemas overlaid. Notion can't — a row belongs to one database.
- **Block-as-first-class (Roam, Logseq, Athens).** The block-graph model is technically pure but ergonomically heavy and has crushed multiple companies (Athens). Note-as-first-class with tags-as-config-notes covers ~95% of block-graph use cases without the engine cost.
- **Tag-name root-level token scoping as the long-term answer.** Parachute Phase 1 ships `scoped_tags` as an allowlist on tokens. Nothing else surveyed scopes by tag root — Notion does it by page tree, Anytype by space, the rest don't have multi-user. Tag-root scoping is a fine MVP but the long-term shape is more likely property-driven (a `viewable_by:` field on tag schemas) once the cloud tier needs real multi-tenancy.

---

## 5. Open questions / edge cases

1. **Wikilink ambiguity policy.** Obsidian's "shortest unique path" requires the user to know what's unique. Parachute's `[[X]]` resolved by name needs a clear rule when two notes share a name. Options: (a) error / warn, (b) most-recently-updated wins, (c) require path on ambiguity. What does Parachute do today, and is it documented?
2. **Tag-rename history.** With stable tag IDs, rename is a metadata-only operation — but downstream consumers (search indexes, exports, MCP tool returns) may have cached the old name. Is there a tag-name-history table, or does the system trust "rename is rare"?
3. **Schema validation strictness.** Tana, Logseq, Anytype all enforce typed properties with validation. Parachute's `_tags/<name>` declares fields — does it *enforce* that notes with tag X carry the declared fields? Or is it schema.org-style "expected, not required"? Both are defensible; pick one and document it.
4. **Path uniqueness vs reuse.** `path TEXT optional unique` — is path required for some kinds of notes (e.g. anything in `_tags/`)? Or is path purely cosmetic? If `_tags/<name>` is a path, what happens when a tag with no `_tags/` config note is referenced? Implicit-schema-from-usage vs explicit-schema-required-for-tag.
5. **Bidirectional links.** Parachute's `links` table is graph edges. Are they directional (note A → note B) or bidirectional? Notion and Capacities make this a per-relation choice; Anytype defaults bidirectional; Obsidian's backlinks panel is computed at read time. If Parachute's links are stored directionally, the inverse query is a simple SELECT — no need to materialize bidirectionality.
6. **Block-level granularity.** None of the database-graph tools (Roam, Logseq, Anytype) regret making blocks first-class for outlining; the regret is the engine cost. If Parachute ever wants block-level tags or block-level links, the cleanest path is a `blocks` table that mirrors the `notes` shape — not retrofitting `notes.metadata`.
7. **Multi-vault link resolution.** Parachute is one vault per user (today). If/when cross-vault links are a thing (e.g. shared `_tags/` registries across an org), the link resolver needs a vault-qualified namespace. Notion handles this with workspace-scoped UUIDs; Anytype with cross-space type sharing.
8. **External-edit safety.** Obsidian breaks links when files are renamed outside the app. Parachute's `links` table re-resolved at read time is robust to direct-DB edits *if* renames go through the API. What's the contract for direct SQL writes? (Not a hypothetical — automation bots and export pipelines will hit the DB directly.)
9. **Permission composition.** Phase 1 tag-root-scoped tokens + (eventual) per-note ACLs + (eventual) field-driven ACLs need a composition story. Notion settled on inheritance-with-overrides — child overrides parent, explicit wins over implicit. Parachute should pick its rule before building the second permission dimension.
10. **The `_tags/` reserved prefix.** Multiple tools have a special prefix (`_` in Anytype, `$:/` in TiddlyWiki, `:`-prefix attrs in Datascript). The reserved prefix is fine, but its discoverability matters: how does a user find `_tags/<name>` to edit a schema? Is there a UI surface, or is it documentation-only?

---

## Sources

- [Obsidian Help — Properties](https://help.obsidian.md/properties)
- [Obsidian Help — Tags](https://help.obsidian.md/tags)
- [Obsidian forum — Settings: New Link Format: What is "Shortest path when possible"?](https://forum.obsidian.md/t/settings-new-link-format-what-is-shortest-path-when-possible/6748)
- [obsidian_wikilink_rules.md (gist)](https://gist.github.com/dhpwd/9bb86c53b69cb63e09ccca42e3bf924c)
- [Obsidian forum — Wikilinks not updated on file rename when part of a Dataview query](https://forum.obsidian.md/t/wikilinks-not-updated-on-file-rename-when-part-of-a-dataview-query/70043)
- [Desktop Commander Blog — How to Bulk Rename Obsidian Files Without Breaking Every Link](https://desktopcommander.app/blog/obsidian-bulk-rename-files/)
- [Logseq DeepWiki — Property Management](https://deepwiki.com/logseq/logseq/3.2-property-management)
- [Logseq DeepWiki — Database Schema and Validation](https://deepwiki.com/logseq/logseq/4.2-database-schema-and-validation)
- [Logseq forum — The difference between page links, tags, and properties](https://discuss.logseq.com/t/the-difference-between-page-links-tags-and-properties/8393)
- [Zsolt Blog — Deep Dive into Roam's Data Structure](https://www.zsolt.blog/2021/01/Roam-Data-Structure-Query.html)
- [Ness Labs — When to use pages, tags, or attributes in Roam Research?](https://nesslabs.com/pages-tags-attributes-roam-research)
- [Notion — Property Object reference](https://developers.notion.com/reference/property-object)
- [Notion Help — Relations & rollups](https://www.notion.com/help/relations-and-rollups)
- [Notion Help — Sharing & permissions](https://www.notion.com/help/sharing-and-permissions)
- [Notion Databases Explained + API Changes](https://www.simonesmerilli.com/life/notion-database-data-source)
- [TiddlyWiki — Datamodel](https://tiddlywiki.com/dev/static/Datamodel.html)
- [TiddlyWiki — Tagging](https://tiddlywiki.com/static/Tagging.html)
- [TiddlyWiki — TiddlerFields](https://tiddlywiki.com/static/TiddlerFields.html)
- [Anytype DeepWiki — Object Types and Relations](https://deepwiki.com/anyproto/anytype-heart/3.1-object-types-and-relations)
- [Anytype Docs — Properties](https://doc.anytype.io/anytype-docs/getting-started/types/relations)
- [Anytype Docs — Channels (Spaces)](https://doc.anytype.io/anytype-docs/getting-started/vault-and-key/space)
- [Tana — Intro to nodes, fields, supertags](https://tana.inc/articles/intro-to-nodes-fields-and-supertags)
- [Tana — Fields](https://tana.inc/docs/fields)
- [Tana — Supertags](https://tana.inc/docs/supertags)
- [Capacities — Object Types](https://docs.capacities.io/reference/content-types)
- [Capacities — Properties](https://docs.capacities.io/reference/properties)
- [Reflect Academy — Using backlinks and tags](https://reflect.academy/using-backlinks-and-tags)
- [Athens Research GitHub (archived)](https://github.com/athensresearch/athens)
- [HN — Launch HN: Athens Research](https://news.ycombinator.com/item?id=26316793)
- [Schema.org — Data Model](https://schema.org/docs/datamodel.html)
- [Schema.org — Schemas](https://schema.org/docs/schemas.html)
