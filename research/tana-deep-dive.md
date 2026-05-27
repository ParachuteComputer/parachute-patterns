# Tana — deep dive

**Status:** research input for Parachute Vault architecture review
**Date:** 2026-05-02
**Companion to:** `research/knowledge-tool-data-models.md` (Tana entry §2.7), `research/parachute-data-model-shape.md`
**Brief:** Aaron flagged Tana as the design reference for "tags-as-type" semantics, in contrast to Obsidian's "tags-as-category." This dives in: data model, supertag UX, AI integration, and what Parachute could borrow vs reject.

Sources are cited inline by URL. Where public docs are silent or contradictory, that is called out in-line.

---

## 1. TL;DR

1. **The supertag is the load-bearing primitive.** Everything in Tana is a node ([Tana — Nodes & references](https://outliner.tana.inc/docs/nodes-and-references)); a supertag is a *node that defines a type* — apply it and the target node gains the supertag's fields and child-node template. The phrase the docs return to: "*when you tag something, the content **is** the tag.*" Use the "is a" test ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)).
2. **Fields are universal in identity, scoped by display.** A field is created inside a supertag template by default, but "discoverable" promotes the definition into Schema where it can be reused across many supertags ([Tana — Fields](https://outliner.tana.inc/docs/fields)). The same `Status` field can sit on `#task`, `#project`, and `#post` and mean the same thing.
3. **Supertags inherit via `Extends`.** A `#design-task` extends `#task` and gets `#task`'s fields automatically; queries on `#task` return all descendants ([Cortex Futura — Supertag basics](https://www.cortexfutura.com/supertag-basics-tana-fundamentals/)). This is real type inheritance, not slash-string convention.
4. **Search nodes are the materialised view.** Clicking a supertag navigates to its Supertag Page — a default table of every node carrying that supertag, customisable as cards, calendar, or kanban. Queries pivot on supertag + field predicates ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)).
5. **AI is schema-aware, not schema-agnostic.** Tana AI's pitch is exactly: "add information to help AI understand what content means and how it's connected, through Supertags and fields" ([Tana — Tana AI](https://outliner.tana.inc/docs/tana-ai)). Voice-memo + supertag triggers automatic field population; AI commands like Autotag receive a curated set of supertag candidates and pick which to apply.
6. **AI fields and command nodes are the agent surface.** AI-enhanced fields auto-fill from node context. Command nodes (Autotag, Autofill, Text processing agent, custom Ask-AI) are configured with prompt templates and parameter slots, triggered manually or by supertag events ("on added") ([Tana — AI Command Nodes](https://outliner.tana.inc/docs/ai-command-nodes)). This is how Tana makes "agents" without code.
7. **Top-down supertag creation is dominant; bottom-up promotion exists.** You can `#newname` to create a supertag inline, or `Convert to supertag` lifts an existing node-with-children into a definition ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)). New supertags auto-register in Schema.
8. **Power users converge on small supertag counts with deep `Extends` chains.** Bri Ballard's published structure is **6 base supertags with extensions**, organised as input/task/objective trees ([Bri Ballard — Tana supertag structure](https://medium.com/@bri-ballard/my-tana-super-tag-structure-for-task-management-objective-centered-productivity-c893abc68090)). The recurring counsel is "few base tags, lean on Extends," not "one supertag per concept."
9. **The pain points are real and consistent.** Reviews land on three: steep learning curve, no offline / no end-to-end encryption, and outliner-shape unfit for long-form prose ([XDA — Tana supertags review](https://www.xda-developers.com/tana-supertags-review/), [Mark McElroy — honest impressions](https://markmcelroy.com/tana-my-honest-initial-impressions/), [fourhourfreedom — left Tana for Obsidian](https://fourhourfreedom.substack.com/p/i-left-tana-for-obsidian-after-recent)). Not "supertag-explosion"; the dominant complexity story is *getting started*, not *scaling out*.
10. **For Parachute: the Supertag-as-typed-node model is the closest peer to `_tags/<name>` config notes**, but Tana's tighter coupling of search, view, AI, and schema buys ergonomics that Parachute's MCP-first surface can replicate without copying the outliner shape.

---

## 2. Tana's data model

### 2.1 Node — the universal primitive

Every piece of structure in Tana is a node: bullets, fields, views, commands, settings, workspaces, daily pages — *everything* ([Tana — Intro](https://outliner.tana.inc/articles/intro-to-nodes-fields-and-supertags)). The block-vs-page distinction is intentionally absent; *"Tana sets these metaphors aside in favor of the node"*.

**Identity.** Every node receives a unique nodeID on creation; IDs appear in URLs as `nodeid=XXX`. Two nodes can share text but be different entities. Renaming changes content; identity and references survive.

**Hierarchy.** A node has **one owner** (canonical parent in the outline) and **any number of parents** (display contexts via references — "mirror copies"). Editing any reference updates the original and all mirrors. Structure is graph-with-canonical-spine; no path string.

**No path, no folder.** Location is "where in the outline tree (owner chain), plus which other nodes reference it." Sharp departure from Obsidian's filesystem-bound model and from Logseq's flat title namespace.

### 2.2 Supertag — a node that types other nodes

A supertag is a node whose function is to attach a type to other nodes. The supertag *itself* lives somewhere — typically under Schema — and stores: a name, a list of fields, a template of default child nodes, AI configuration, view configuration, and (optionally) an Extends pointer to a parent supertag.

Applying a supertag does three things:

1. **Records membership** — the target node now `#has` this supertag and shows up in queries.
2. **Instantiates the field template** — every field defined on the supertag appears under the target node, pre-populated with defaults if configured.
3. **Instantiates the child-node template** — any child nodes declared in the supertag's template (e.g. a `Summary` heading, a `Quotes` section) get inserted under the target node ([Cortex Futura — Supertag basics](https://www.cortexfutura.com/supertag-basics-tana-fundamentals/)).

Multiple supertags can apply to one node — *"a node can appear in different databases at the same time"* ([Unlock Tana — supertags vs tags](https://www.unlocktana.com/blog/supertags-vs-tags)).

Tana also supports **base types** — 13 predefined object types (Meeting, Task, Organization, Person, Location, Project, Topic, Event, Article, Memo, Reflection, Day, Week) that a custom supertag can claim. Claiming a base type unlocks platform-specific behaviour: meeting transcription, calendar sync, etc. ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)).

### 2.3 Field — typed metadata, "has a"

The conceptual frame: a node *has a* field. A book *has an* author. A task *has a* due date. ([Tana — Intro](https://outliner.tana.inc/articles/intro-to-nodes-fields-and-supertags))

**Field types** ([Tana — Fields](https://outliner.tana.inc/docs/fields)): **Plain** (freeform), **Options** (hand-authored dropdown), **Options from supertag** (formerly "Instance" — dropdown of all nodes with a chosen supertag, e.g. Owner field of `#person` nodes), **Date**, **Number**, **Tana user**, **URL**, **Email**, **Checkbox**.

**Scope: universal in identity, local in declaration.** The first place a field is created becomes its "primary instance" carrying the definition. Marking it **discoverable** (formerly "Move to Schema") lifts the definition into Schema for reuse — *"field definitions owned by the schema have priority"*. A discoverable `Status` is the same field on `#task`, `#project`, `#post`.

**Auto-initialisation.** A field can derive its initial value from: same-named field on an ancestor, current date or ancestor day's date, current user, a random/ancestor node carrying a chosen supertag. Caveat: *"Initialization expressions are convenience functions, but are not live updating."*

**AI-enhanced field.** Toggle on the config; AI fills the field from *"the name, description and contents of the parent node"* — i.e. local context, not global graph.

**Pinned / required / optional.** Pinned shows prominently in views and queries; required is visual-only (warns, doesn't block); optional is surfaced via slash-command rather than instantiated by default.

### 2.4 Relations — references, not link-strings

Wikilink-style references in Tana are **stable-ID pointers**. The display text follows the current node title; renames are free. References are first-class — *"a node cannot be referenced more than once as a child within the same list"* ([Tana — Nodes & references](https://outliner.tana.inc/docs/nodes-and-references)). The "Options from supertag" field type creates a typed pointer: a field on `#meeting` of type "Options from supertag #person" returns a typed list of person references.

There is no analog of Obsidian's `[[X]]` resolution-by-shortest-name. References are by ID at write time.

### 2.5 Path / hierarchy — graph-shaped, with one canonical spine

There is no folder, no file, no path string. Each node has one owner (canonical parent) and any number of reference parents (display contexts). Schema sits as a top-level outliner node where supertags and discoverable fields live as children — but Schema-as-location is a convention, not a structural requirement; the docs note *"the schema node ... is a bit of a legacy node at this point, and the conventions for how to use this are currently in flux"* (per the schema-overhaul search results).

---

## 3. The supertag UX

### 3.1 Creating a supertag — top-down or bottom-up

**Top-down (declare type up front).** Type `#` on any node, then a name that doesn't exist. The new supertag appears as the top option in the menu and is auto-registered to Schema ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)). Configure fields, template children, AI behaviour, and views via the supertag's config node.

**Bottom-up (promote a node to a type).** Use the Command Line (Cmd/Ctrl+K), select **Convert to supertag**. The node's children become the template; fields detected on the node become the supertag's fields. The original node is now a supertag definition.

### 3.2 Applying a supertag

In the editor, type `#` and the supertag name in any node, hit Enter. The supertag attaches to the **whole node**, not partial content. The UI immediately:

- Inserts the field template under the node (filled where defaults / auto-init expressions resolve)
- Inserts any template child nodes
- Adds the node to the supertag's Search Node (the materialised query)
- Triggers any "on added" AI commands configured on that supertag

**Bulk apply.** Select multiple nodes; type `#` or use **Add tag**; supertag applies to all simultaneously. Same flow for **Remove tag** ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)).

The XDA review describes the practical experience: *"During client calls, typing naturally, then tagging nodes with #client causes relevant fields to appear automatically"* ([XDA — Tana supertags review](https://www.xda-developers.com/tana-supertags-review/)). The structure-vs-spontaneity divide that motivates supertags: *"Tana let information exist as both simultaneously"* — the same thought is freeform note **and** structured row, not duplicated.

### 3.3 Supertag inheritance (`Extends`)

A supertag can extend another. The extending tag inherits the parent's full template and is treated by queries as "is-a" the parent.

Concretely (from [Cortex Futura](https://www.cortexfutura.com/supertag-basics-tana-fundamentals/) and [Tana — Supertags](https://outliner.tana.inc/docs/supertags)):

- `#design-task` extends `#task` → inherits `Due Date`, `Project` fields; can add `>Reno team` field
- Inherited content cannot be deleted/moved on the child; defaults can be overridden
- Searching `#task` returns `#task` plus all descendants (`#design-task`, `#dev-task`, ...)

This is genuine type inheritance with covariant query semantics, not slash-prefix display hierarchy. **Important distinction from Logseq/Obsidian:** those tools have hierarchical tag display (`#health/food` is "under" `#health` for UI purposes only); Tana's `Extends` is structural — the child supertag actually carries the parent's schema.

### 3.4 Querying — search nodes are the central UI

Every supertag has an associated Supertag Page that shows a default Search Node returning all nodes with that supertag. The page is customisable: tabs view, table / cards / calendar / kanban / list, filter and sort by any field, group by any field, scoped to subtrees.

Search nodes themselves are nodes. They can be embedded anywhere (e.g. inside a `#project` template, a search node that returns "all `#task` whose Project field equals this project" — a per-instance contextual query). The search-node language uses supertag predicates and field comparisons; Tana provides a builder UI rather than requiring users to write a query DSL ([Unlock Tana — vs Logseq](https://www.unlocktana.com/blog/tana-vs-logseq)).

There is also full-text freeform search across the graph; supertag-filtered search is the default workflow for typed retrieval.

### 3.5 Title expressions — derived display

A supertag can declare a **title expression** that builds the node's displayed title from its field values: `${meeting-with} - ${date|10}`. System fields (`${sys:owner}`, `${sys:doneTime}`, `${sys:nodeId}`) are available ([Tana — Supertags](https://outliner.tana.inc/docs/supertags)).

This is a clean inversion of the Obsidian/Notion pattern where title is hand-written; Tana lets the schema *generate* the title.

---

## 4. AI integration

This is the most consequential section for Parachute. Tana's AI strategy is built around the typed model — AI is not a freeform chatbot bolted onto a freeform graph, it is a set of *commands* and *fields* whose context is the supertag schema.

### 4.1 Two surfaces: AI-enhanced fields + Command Nodes

**AI-enhanced fields** — a toggle on a field config. When enabled, the field auto-fills from the parent node's context (children, other fields, description). The system bundles that context into a prompt with the task "Decide a value for the field" and writes the response back ([Tana — Fields](https://outliner.tana.inc/docs/fields)).

**Command Nodes** — a node-type defining an AI command (or chain). Parameters: prompt template, model, temperature, target node, output strategy, node filter, batch context, field dependencies. Triggered by manual invocation, button on a node, keyboard shortcut, or **supertag event** ("on added" / "on removed") ([Tana — AI Command Nodes](https://outliner.tana.inc/docs/ai-command-nodes)).

### 4.2 Named commands

Canonical, with custom variants composed in the Prompt Workbench:

- **Autotag** — given candidates, AI picks which supertags apply
- **Autofill** / **Run AI fields** — fills/re-evaluates AI-enhanced fields
- **Ask AI** (streaming and non-) — freeform prompt → target
- **Transcribe audio** — Whisper
- **Text processing agent** — extracts summary, action items, entities from text; routes each output to a configured supertag + target (e.g. action items → `#task` → inbox)
- **Make API request** — outbound HTTP
- **Generate image(s)** — Gemini Nano / DALL-E
- **Add meeting bot** / **AI meeting notetaker**

### 4.3 Schema-aware prompt expressions

Prompt variables resolve against the typed graph at run time:

- `${name}` — node title
- `${field label}` — specific field value
- `${sys:context}` — full node context (fields, children, description, supertags)
- `${sys:tags}` — supertags on the node
- `${sys:content}` — children only
- `${sys:nodeId}`, `${sys:nodeURL}`, `${sys:currentDate}`, etc.

The AI's context is a **structured projection of the typed graph**, not raw text. When Autotag runs on `${sys:context}`, the prompt the model sees already includes the node's existing fields and supertags. Schema-awareness manifests at the prompt layer because variable substitution puts it there.

Sharp limitation: *"Prompt variables only resolve in plain nodes, not within references"* — agents must operate on canonical owner-chain nodes, not mirrors.

### 4.4 Does AI create or only apply?

Published behaviour is **only-apply**:

- Autotag takes a `Tag candidates` parameter — a curated supertag list
- AI selects from the list; it does not invent supertags
- Supertag creation is a human action (`#newname` or Convert to supertag)

XDA, Cortex Futura, and Tana's own docs are consistent. AI-enhanced fields auto-fill values, but the field definition must already exist — AI is a value-decider, not a schema-author.

The nearest AI-schema-authoring signal: *"If you use AI in Tana, fields will be automagically suggested for any new supertag you create."* That's a suggestion at supertag-creation time; the human accepts or edits.

### 4.5 Curation, scoping, and what's missing

**No explicit confirmation gate.** Autotag/Autofill execute and write. Mitigations: 60-second loop-detection that disables the event system on rapid recursion; Status-field gating for downstream commands; prompt preview during authoring (not on every execution). Reasonable for solo-operator-supervises-own-graph; thinner for multi-tenant agent settings.

**Supertag-scoped agents.** Two documented patterns:

1. Command node with **Node filter:** `>has tag #person`
2. Command on the supertag itself with **trigger:** "On added"

The Text Processing Agent's parameters include "Tags to use for entities" and "Tags to use for action items" — making it a **typed router** that maps extracted content to supertags.

**What public docs don't answer.** Whether Tana AI Chat sees the *full* schema at reasoning time or only local context (docs only specify local bundling for AI-enhanced fields). Whether agents can author new supertags (almost certainly no, but not stated). Internal model selection and how tokens scale with schema size.

---

## 5. Tana vs Obsidian — the two "what's a tag for" paradigms

| Dimension | Obsidian | Tana |
|---|---|---|
| Tag identity | String. No ID. | Stable-ID node; name is mutable display. |
| Schema | None native; YAML frontmatter is per-file; Dataview indexes; Bases plugin (v1.9.0) narrows the gap. | First-class — supertag *is* a schema container. |
| Hierarchy | Slash-as-string display convention only. | `Extends` — real inheritance, covariant queries. |
| Apply operation | Inline `#tag` or YAML. No structural side-effect. | Inserts field + child template, triggers events, joins search node. |
| AI relationship | None native; plugin-driven. | Schema-aware via `${sys:tags}`/`${sys:context}`; commands take supertag candidates. |
| Rename safety | Vault-wide find-and-replace. | ID-stable; rename changes display only. |
| Storage | Plain markdown on disk. | Proprietary cloud; no offline, no E2EE ([Mark McElroy](https://markmcelroy.com/tana-my-honest-initial-impressions/)). |
| Long-form prose | First-class. | Outliner-shaped; *"unsuitable for prose composition"* ([Bri Ballard](https://medium.com/@bri-ballard/from-an-avid-obsidian-user-why-i-came-to-love-tana-45ee9edf5ec8)). |

The recurring summary: Obsidian is the better app for *writing and thinking*, Tana is the better tool for *organising and operating* ([Yalcin Arsan](https://medium.com/personal-knowledge-management-deep-dive/obsidian-vs-tana-how-they-compare-c5086127bcad)).

---

## 6. Tana vs Roam vs Logseq — block-graph variants

All three are stable-ID block-based outliners with bidirectional links. The fork is on what schema gets.

| | Roam | Logseq | Tana |
|---|---|---|---|
| Storage | Datomic, cloud | Datascript, local-first (markdown/org files; DB mode) | Proprietary cloud |
| Page = block | Yes | Yes | Yes — *"everything is a node"* |
| Tag = page | `#foo` ≡ `[[foo]]` edge | Same in classic; DB mode adds class entities via `:block/tags` | Supertag links target to a typed node |
| Schema | None; `Status::` attributes by convention | DB v1+ classes with Malli-validated property schemas ([DeepWiki](https://deepwiki.com/logseq/logseq/3.2-property-management)) | Supertags carry fields + child template + AI config + view config |
| Type inheritance | None | Class inheritance (DB mode) | `Extends` — first-class |
| Materialised view per type | Hand-built queries | Hand-built queries; class page lists members | Auto-generated, customisable Supertag Page |
| AI integration | Plugins | Plugins | Native, schema-aware Command Nodes + AI-enhanced fields |
| Portability | Closed | Open source, markdown-portable | Closed, no typed export |

Tana's structural delta is two-pointed: **schema is a node, edited in the same surface as content**, and **the AI layer is wired to that schema** rather than to raw text. Logseq DB v1 is the closest peer; its AI story is plugin-driven rather than built-in. The Logseq forum's own framing: *"Tana is basically a Relational Database visualized in different ways like Notion"* — think Notion-with-outliner more than Roam-with-types ([Logseq forum](https://discuss.logseq.com/t/what-are-the-biggest-differences-between-tana-and-logeq/13579)).

---

## 7. Pain points + critique

**Learning curve is the dominant complaint.** The cultural moment is the *"Tana makes me feel dumb"* phase ([Tana](https://outliner.tana.inc/articles/tana-makes-me-feel-dumb)) — Tana's own response was hundreds of one-on-one onboarding sessions and simplified terminology. The narrative pattern: *"Many users download Tana, spend hours watching tutorials about Supertags and schema design, build an elaborate system they don't understand, and then abandon it within a week."*

**Storage, privacy, offline.** Cloud-only, no offline mode, no end-to-end encryption ([Mark McElroy](https://markmcelroy.com/tana-my-honest-initial-impressions/), [fourhourfreedom](https://fourhourfreedom.substack.com/p/i-left-tana-for-obsidian-after-recent)). Hard differentiator from Logseq (markdown files), Obsidian (filesystem + community E2EE), Anytype (encrypted spaces).

**Outliner shape unfit for prose.** Universal across reviews. Migration pattern is **hybrid** — Obsidian for writing, Tana for organising.

**Supertag-explosion is *not* the dominant pain.** Searches for "supertag explosion" return few results. Power-user testimony runs the other way: Bri Ballard's published structure is **6 base supertags + extensions**, organised as input/task/objective trees ([Bri Ballard](https://medium.com/@bri-ballard/my-tana-super-tag-structure-for-task-management-objective-centered-productivity-c893abc68090)). Cultural counsel is *"few base tags, lean on Extends"*. Schema-rigidity is rarely complained about because schema is mutable in-place — adding a field propagates to every existing instance.

**Schema is "in flux."** Tana's own docs admit *"the schema node ... is a bit of a legacy node at this point, and the conventions for how to use this are currently in flux."* The Instance field type was renamed to "Options from Supertag" in Feb 2024. The right shape for schema-as-data is not yet settled even in the system that pioneered it.

**AI loops and cost.** The AI Command Nodes doc names recursion as a real concern; a safety mechanism disables the event system if similar events trigger within 60 seconds. Paid plans gate AI commands; the Prompt Workbench's credit monitor exists because users *do* burn credits on prompt iteration.

**Schema design is a separate skill.** Even Tana's own positioning concedes the load — there's an XDA piece on "*organize your life in Tana without touching supertags*" ([XDA](https://www.xda-developers.com/tana-no-supertags/)). Casual users want the outliner without the type system.

---

## 8. What Parachute could borrow vs reject

Mapped against Parachute's current state ([`parachute-data-model-shape.md`](./parachute-data-model-shape.md)): notes have `id` PKs and optional unique paths; tags use `name TEXT PRIMARY KEY` (name *is* identity); `tag_schemas` carries optional fields-JSON; conventions are the `_tags/<name>` config-note and slash-prefix hierarchy.

### 8.1 Borrow

**(a) `Extends` for tag inheritance.** Structural inheritance with covariant query semantics — strictly better than slash-prefix display convention. A `parent_tag_id` column (post-stable-ID) gets it; querying `health` returns descendants. Small fix once tags have IDs.

**(b) Discoverable fields shared across tags.** A field is defined under a supertag, then promoted to Schema for reuse across many. Avoids declare-every-field-globally and avoids every-field-private. Implementation: a `field_defs` table; `tag_schemas.fields` references field-def rows by ID; multiple tag schemas reference the same field-def.

**(c) Auto-init expressions on fields.** "Current date," "current operator," "value from ancestor tag" patterns ship a lot of value with little code. Reduces friction when a tag is applied via MCP.

**(d) Title expressions.** A `tag_schemas.title_template` with `${field}` substitution lets clients render display titles for nodes whose identity *is* their field values (meeting, reflection, recipe). Big UX, small machinery. Opt-in per tag.

**(e) Persisted named queries (search nodes).** Tana's Supertag Page is a query that lives in the graph. Parachute's `query-notes` MCP tool returns ad-hoc results; the missing primitive is a *named query node* — a view that an agent can call by name. Map onto a `_views/<name>` config-note convention paralleling `_tags/<name>`.

**(f) AI Command Nodes as configurable surface.** The deepest borrow. A command is: prompt template + parameter slots + node filter + trigger + output strategy, stored as data. Maps onto a `_commands/<name>` config-note convention. Operator authors; MCP exposes; agents trigger. Supertag's "on added" event maps to a tag-application hook.

**(g) Schema-aware prompt expressions.** `${sys:context}` / `${sys:tags}` / `${field name}` substitution is the right primitive for handing an agent a typed projection of a note rather than a markdown blob. Lean in.

### 8.2 Reject

**(a) Outliner-only edit surface.** Tana's everything-as-node-in-outline forecloses long-form prose. Parachute keeps markdown notes primary; layers typed metadata on top.

**(b) Cloud-only, no-export storage.** Tana's biggest community wound. Parachute's SQLite + readable markdown bodies are not worth trading away.

**(c) "Everything is a node, including schema definitions."** Elegant but produces the "feel-dumb" phase because every primitive is in front of every user. Parachute's `_tags/<name>` *path-prefix convention* keeps schema opt-in rather than structurally adjacent to content.

**(d) Reference-as-mirror semantics.** "Edit any reference, all update" is powerful but heavy. Parachute's links as typed pointers (source_id → target_id, not mirrors) is the right shape.

**(e) Tag applies to whole node, all-or-nothing.** Markdown notes have regions (frontmatter, body, headings); inline tag mentions inside content shouldn't be forced to apply note-wide. Keep note-level tags canonical and allow inline mentions.

**(f) AI fields that auto-write without confirmation.** Tana's fire-and-forget writeback fits solo-operator-supervising-their-own-graph. Parachute's MCP surface (Claude, third-party models, external services) needs propose-then-confirm via tool-calls.

**(g) Title-template as the *only* title.** Useful when opt-in; bad when forced. Manual titles primary, templates per-tag opt-in.

### 8.3 Open questions

Public Tana docs do not answer these; Parachute should decide explicitly:

1. **Does AI see full schema or only local context?** Tana docs only specify local-context bundling. Cost implications either way.
2. **Is tag-creation an AI-permitted action?** Tana keeps it human-only. Parachute should default to the same; opt-in for tag-creation MCP tools.
3. **Where does schema live structurally?** Top-level Schema-folder (Tana), `_tags/<name>` config notes (current Parachute), or a separate non-note table? Tana's "in flux" admission is a warning the right shape isn't industry-settled.
4. **Do tags get stable IDs?** Tana answered yes. Parachute's `name TEXT PRIMARY KEY` is the load-bearing decision; Tana's experience is one vote toward stable IDs.

---

## Sources

Official Tana docs (all on `outliner.tana.inc`, the canonical content host):
- [Tana — Supertags](https://outliner.tana.inc/docs/supertags)
- [Tana — Fields](https://outliner.tana.inc/docs/fields)
- [Tana — Nodes and references](https://outliner.tana.inc/docs/nodes-and-references)
- [Tana — Tana AI](https://outliner.tana.inc/docs/tana-ai)
- [Tana — AI Command Nodes](https://outliner.tana.inc/docs/ai-command-nodes)
- [Tana — AI for Builders](https://outliner.tana.inc/docs/ai-for-builders)
- [Tana — Intro to nodes, fields, and supertags](https://outliner.tana.inc/articles/intro-to-nodes-fields-and-supertags)
- [Tana — Learn Live: Supertags and Fields](https://outliner.tana.inc/articles/tana-learn-live-supertags-and-fields)
- [Tana — Tana makes me feel dumb](https://outliner.tana.inc/articles/tana-makes-me-feel-dumb)
- [Tana — Schema structure for Tana (David Delgado Vendrell template)](https://outliner.tana.inc/articles/tana-template-schema-structure-for-tana-by-david-delgado-vendrell)
- [Tana — Supertags landing page](https://tana.inc/supertags)

Community / reviews / power-user writeups:
- [Cortex Futura — Supertag basics in Tana](https://www.cortexfutura.com/supertag-basics-tana-fundamentals/)
- [Unlock Tana — Supertags vs Tags Explained](https://www.unlocktana.com/blog/supertags-vs-tags)
- [Unlock Tana — Tana vs Logseq](https://www.unlocktana.com/blog/tana-vs-logseq)
- [Bri Ballard (Medium) — My Tana Super Tag Structure for Productivity](https://medium.com/@bri-ballard/my-tana-super-tag-structure-for-task-management-objective-centered-productivity-c893abc68090)
- [Bri Ballard (Medium) — From an Avid Obsidian User: Why I Came to Love Tana](https://medium.com/@bri-ballard/from-an-avid-obsidian-user-why-i-came-to-love-tana-45ee9edf5ec8)
- [XDA — I tested Tana's supertags](https://www.xda-developers.com/tana-supertags-review/)
- [XDA — Tested a no-overwhelm way to organize without supertags](https://www.xda-developers.com/tana-no-supertags/)
- [Mark McElroy — Tana, my honest initial impressions](https://markmcelroy.com/tana-my-honest-initial-impressions/)
- [fourhourfreedom — Tana Is Starting to Feel Like the Future Again](https://fourhourfreedom.substack.com/p/i-left-tana-for-obsidian-after-recent)
- [Yalcin Arsan (Medium) — Obsidian vs. Tana](https://medium.com/personal-knowledge-management-deep-dive/obsidian-vs-tana-how-they-compare-c5086127bcad)
- [AI:PRODUCTIVITY — Tana Supertags Guide](https://aiproductivity.ai/guides/tana-supertags-guide/)
- [Bah (Medium) — Supertags in Tana](https://medium.com/@bah.lindt/supertags-in-tana-940a10e5a977)
- [André Foeken on X — Auto-tagging entities in Tana with GPT-4o](https://x.com/dreetje/status/1792119695400710366)
- [Logseq forum — Differences between Tana and Logseq](https://discuss.logseq.com/t/what-are-the-biggest-differences-between-tana-and-logeq/13579)

Cross-tool / context:
- [DeepWiki — Logseq Property Management](https://deepwiki.com/logseq/logseq/3.2-property-management)
- [alfred — Best Roam Research alternatives](https://get-alfred.ai/blog/best-roam-research-alternatives)
- [Jens-Christian Fischer — supertag-cli](https://github.com/jcfischer/supertag-cli)
