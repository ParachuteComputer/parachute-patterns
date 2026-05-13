# Migration notes

Running log of pattern changes and the repos that need to follow. Newest
entries on top. Each entry: date, change, affected repos, status.

---

## 2026-05-13 — governance.md gains Rule 4 (PR cadence)

**Change:** [`governance.md`](../patterns/governance.md) extended from
three rules to four. New **Rule 4 — PR cadence: bundle by session/theme,
not by issue.** The unit of review is the PR; the unit of change is the
commit. One PR per coherent session of work; multiple commits inside it;
reviewer reads commit-by-commit. Bundle when changes share a theme or
touch overlapping files; split only on genuinely independent surfaces,
urgent-ship-needed-while-sibling-in-design, or ~800-1000 LOC ceiling.

**Why now.** Overnight 2026-05-13 cron loop cost Aaron 6 merge-clicks
across 4 repos when 3-4 would have sufficed — repeated PRs in the same
repo on the same theme that could have stacked as commits in one bundle.
Earlier shipping practice had drifted toward one-PR-per-issue as a
mistaken corollary of the `feedback_serial_pr_flow` memory; that memory
is about *parallelism* (don't open N PRs against shared files
concurrently), not about *granularity*. Rule 4 names the distinction
explicitly so future readers don't conflate them.

Header bumped from "Three rules" to "Four rules." Existing rules
(no-auto-merge / RC versioning / patterns check) are unchanged.

**Affected:**

- `parachute-patterns` — rule landed (this PR).
- All Parachute repos with shipping tentacles (`parachute-hub`,
  `parachute-vault`, `parachute-notes`, `parachute-scribe`,
  `parachute-agent`, `parachute.computer`) — adopt the bundle-by-session
  default on next session of work. No code-side change required; the
  shift is in tentacle briefing + reviewer dispatch shape (one PR per
  session theme, commits-as-narrative inside).
- Tentacle briefs should reflect the new default: when a session has
  multiple related issues to address, dispatch one bundle PR with the
  set of issues named in body + closed-by lines, rather than one PR per
  issue.

**Status:** doc-only refresh. No code-side behavior change; the shift
is in how team-lead briefs tentacles and dispatches PRs going forward.

---

## 2026-05-12 — `guides/building-a-surface.md` lands (patterns#58)

**Change:** new guide
[`building-a-surface.md`](../guides/building-a-surface.md) — the
builder-facing companion to
[`multi-writer-workspace.md`](../guides/multi-writer-workspace.md).
Captures parachute-notes' implementation patterns so the next surface
builder doesn't reinvent: OAuth code-flow with PKCE + DCR + refresh
rotation, vault discovery via `/.well-known/parachute.json`, the
services catalog on the token, REST + MCP query operators + cost knobs,
optimistic concurrency on writes (`if_updated_at` + 409/428), atomic
`append` / `prepend` / `content_edit`, batch transactions, the
surface-declares-schema pattern (cross-link [`patterns#57`](https://github.com/ParachuteComputer/parachute-patterns/issues/57)),
and the cross-cutting concerns Notes worked out from scratch
(reachability three-state machine, retry-with-backoff configured against
real error classes, auth-halt as a distinct axis from reachability,
offline-first with `force: true` on stale drains, cross-tab sync,
specific error UX).

Heavy on runnable code snippets adapted from
`parachute-notes/src/lib/vault/` (the working prototype). Five worked
examples: minimal read-only dashboard, write-flow with OC + autosave,
schema-ensure on connect, offline-queued capture, the page-load
discovery + auth + first-fetch sequence.

Cross-linked bidirectionally with
`guides/multi-writer-workspace.md` so a reader landing on either guide
finds the other in the Cross-links section.

**Affected:**

- `parachute-patterns` — guide landed (this PR). No code-side changes.
- `parachute.computer` — link to the guide from "for developers" /
  "how do I build on parachute" pages once they exist. Nice-to-have, not
  a required follow-up.
- `parachute-notes` — implicit prototype reference throughout. If notes'
  `src/lib/vault/` API shifts substantially, this guide's code snippets
  should be re-synced. Tracked here for visibility.
- `parachute-hub`, `parachute-vault`, `parachute-scribe`,
  `parachute-agent` — no immediate change. Linking from per-repo
  READMEs to the guide is welcome but optional.

**Status:** doc-only. No vault / hub / surface behavior changed; the
guide tracks shipped reality and explicitly flags what's not yet
supported (abstract surface SDK is research; HTTP_API.md doc refresh
pending in vault#315; `validation_status` REST/MCP parity gap at
vault#287; cross-origin DCR auto-approve at hub#201).

Tracking issue [`patterns#58`](https://github.com/ParachuteComputer/parachute-patterns/issues/58)
can close on merge.

---

## 2026-05-12 — `tag-scoped-tokens.md` refresh (patterns#17)

**Change:** [`tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md)
reframed from proposal-flavored prose to shipped-reality documentation.
Concrete edits:

- Top-line "Status: shipped" banner with the canonical vault implementation
  link ([`src/tag-scope.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/tag-scope.ts))
  and the vault#241 / rc.30 (2026-05-03) landing reference.
- Convention section reframed: the two axes (OAuth `vault:<name>:<verb>`
  scope claim + `scoped_tags` per-token attribute) are separate by design.
  The colon-syntax shape proposed in patterns#17's title was rejected;
  rationale in §"Why not extend the OAuth scope string."
- Auth-check pseudocode aligned to the real `scoped_tags` field name
  (was `tagAllowlist`) and routed through the actual function names
  (`expandTokenTagScope`, `noteWithinTagScope`).
- §"Hierarchy match semantics" cites the full resolver chain with file:line
  refs (`expandTokenTagScope` → `Store.expandTagsWithDescendants` →
  `getTagDescendants`).
- §Lifecycle updated: tag-rename cascade is the shipped reality (`vault#275`,
  merged 2026-05-09 inside the bundled vault sprint — documented in this
  file's 2026-05-09 entry, item 4), replacing the originally-specced
  fail-closed 409 design that was carried in `vault#240`. Tag-delete still
  fails closed; the doc now distinguishes rename (cascade — identity-as-meaning
  preserved) from delete/merge (fail-closed — destructive op, dependency
  must be acknowledged).
- §"How it composes" dropped reference to retired tools
  (`update-note-schema`, `set-schema-mapping` — retired in vault#269).
- §Adoption table converted from "Phase 1" framing to status-of-each-module,
  with the rename-cascade row added.
- New cross-link to [`guides/multi-writer-workspace.md`](../guides/multi-writer-workspace.md)
  §2 (operator-facing worked example).
- Removed the standalone two-line "Storage" stub that duplicated
  §"Storage details" further down.

**Affected:**

- `parachute-patterns` — doc refreshed (this PR). No code-side changes.
- `parachute-vault`, `parachute-hub`, `parachute-notes`, `parachute-agent`
  — no follow-up required. Doc tracks reality; reality is already shipped.
- Tracking issue [`patterns#17`](https://github.com/ParachuteComputer/parachute-patterns/issues/17)
  can close on merge — the doc now answers the issue.

**Status:** doc-only refresh. No `tag-scoped-tokens` behavior changed; the
edits track the as-shipped surface vault has carried since 2026-05-03.

---

## 2026-05-12 — `guides/multi-writer-workspace.md` lands

**Change:** new `guides/` directory + first guide
[`multi-writer-workspace.md`](../guides/multi-writer-workspace.md). The
canonical "how do we build a team knowledge graph on parachute-vault?"
reference. Covers the mental model (workspace atop journal; parachute's
grain), the multi-writer foundation (hub-as-AS, per-vault scopes,
`scoped_tags`, optimistic concurrency, atomic append/prepend), tag-schema
declaration via `update-tag`, writing patterns (`create-note`,
`update-note` with path-as-id, batch, the sync-from-external-source
options), querying + traversal, bidirectional Obsidian sync, voice +
attachments via scribe, agent-as-writer patterns, the trigger framework,
the template convention, public projection (single-note today; surface
direction for richer), what's coming, and an end-to-end worked example
of a 3-human + 1-agent content team setup.

Establishes `guides/` as a new directory for long-form reference docs
that explain *how to use* the patterns together — distinct from
`patterns/` (single-concept conventions) and `research/` (in-flight
design notes).

**Affected:**

- `parachute-patterns` — guide landed (this PR). New `guides/` directory.
  README mentions the new directory.
- `parachute.computer` — link to the guide from any "for developers"
  / "how do I build on parachute" page once it exists. No immediate
  change required.
- `parachute-vault`, `parachute-hub`, `parachute-scribe`,
  `parachute-agent` — README links to the guide where the repo's own
  docs reference multi-writer concerns. Low priority; nice-to-have, not
  a required follow-up.

**Status:** doc-only; no pattern conformance changes required of
downstream repos. The guide is the canonical reference when its content
conflicts with older partial answers in individual pattern docs.

---

## 2026-05-10 — `module.json` gains `uiUrl` for dynamic discovery rendering

**Change:** new pattern doc
[`module-ui-declaration.md`](../patterns/module-ui-declaration.md). One
optional top-level `module.json` field — `uiUrl?: string` — declares
where a module's user-facing UI lives. Hub's discovery page reads it
(via `/.well-known/parachute.json`) and renders one tile per declaring
service, picking up `displayName` + `tagline` for the copy. Modules
without `uiUrl` are still registered and routable; they just don't
render a clickable card.

Resolution: path form (`"/notes"`) is a path on **hub's origin** and
hub renders the link as `<hub-origin>${uiUrl}` regardless of where the
module itself is hosted — distinct from `managementUrl`'s relative
form, which resolves against the module's own well-known origin.
Absolute URL is used verbatim; omitted = no tile rendered.

Today the hub's discovery page hardcodes `SERVICE_LABELS` + `SERVICE_ORDER`
+ a vault-name filter at the top of
[`parachute-hub/src/hub.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/hub.ts);
which-services-have-UIs and what-they're-called are baked in, and only
the mount path comes from `services.json`. With `uiUrl` in `module.json`,
that hardcoding retires.

`uiUrl` is the discovery-side peer of `managementUrl` (added 2026-05-02
for hub admin pages' "Manage `<name>`" link rendering). They serve
different surfaces — discovery vs. hub admin pages — and a service may
declare both, one, or neither.

The first cut at the discovery section split tiles into "Use" vs
"Admin"; that broke down because real service UIs combine use, config,
and admin in one surface. Aaron's call: services declare what their UI
*is*; hub renders one link per service.

**Affected:**

- `parachute-patterns` — pattern doc landed (this PR). No code change.
- `parachute-notes` — declare `uiUrl: "/notes"` in
  `.parachute/module.json`. One PR.
- `parachute-agent` — declare `uiUrl: "/agent"` in
  `.parachute/module.json`. One PR.
- `parachute-vault`, `parachute-scribe` — no immediate change. Vault
  intentionally omits `uiUrl` (vault content is browsed via Notes;
  vault keeps its per-instance `managementUrl: "/admin"` for the
  hub's vault-list page). Scribe omits today (CLI/API only) and adds
  the field whenever a UI ships.
- `parachute-hub` — read `uiUrl` from each module's well-known entry
  and render the discovery section dynamically. Retire the hardcoded
  `SERVICE_LABELS` map + `SERVICE_ORDER` array + `isVaultName` filter
  in `src/hub.ts`. Retire the `module-manifest.ts` parser's
  silent-ignore of unknown top-level fields for `uiUrl` (read it
  through `composeServiceSpec` so it lands in `services.json` and
  flows to `/.well-known/parachute.json`). One PR.

Backwards-compatible with both directions: hub before its consumer
update silently ignores the new field; modules before their `module.json`
updates simply don't render tiles (same as today's hardcoded omission).
The two sides can land in either order.

**Status:** pattern doc landed (this PR). Module + hub PRs pending.

---

## 2026-05-09 — Tag schema inheritance, `_default`, rename cascade, MCP discovery (vault)

**Change:** [`tag-data-model.md`](../patterns/tag-data-model.md) refreshed
top-to-bottom and [`vault-mcp-discovery.md`](../patterns/vault-mcp-discovery.md)
added, reflecting four vault PRs that landed today against vault 0.4.1-rc.4:

1. [`vault#269`](https://github.com/ParachuteComputer/parachute-vault/pull/269) (`f7c47f1`) — audit-driven cleanup. Ripped `note_schemas` + `schema_mappings` tables and the six MCP tools that authored them (`update-note-schema`, `delete-note-schema`, `list-note-schemas`, `set-schema-mapping`, `delete-schema-mapping`, `synthesize-notes`). MCP tool count: 16 → 9. Schema migration v16 → v17. The 2026-05-03 `_schemas/*` retirement entry below is now superseded — that subsystem existed for ~6 days before being consolidated back onto `tags.fields`.
2. [`vault#272`](https://github.com/ParachuteComputer/parachute-vault/pull/272) (`fc8db55`) — multi-inheritance via `tags.parent_names`. A child tag inherits all ancestors' `fields` recursively (cycle-safe). `_default` is the implicit universal parent: when a `_default` row exists, its `fields` apply to every note as a low-precedence fallback (appended last in the resolver walk; never auto-written into any `parent_names` array). Conflict resolution: first-in-walk wins; the loser surfaces as a `schema_conflict` warning on `validation_status.warnings` (joins `type_mismatch` and `enum_mismatch`). `getTagDescendants("_default")` returns every tag, so `query-notes { tag: "_default" }` means "every note."
3. [`vault#273`](https://github.com/ParachuteComputer/parachute-vault/pull/273) (`4ca781f`) — `vault-info` expanded with full schema projection (`tags`, `effective_parents`, `effective_fields`, `relationships`, `indexed_fields`, `query_hints`, optional `stats`). MCP `getServerInstruction` rewritten to render the same projection as a markdown brief at session `initialize`. Both surfaces tag-scope-filtered (symmetric — neither leaks out-of-scope tags). Single source: `core/src/vault-projection.ts::buildVaultProjection`.
4. [`vault#275`](https://github.com/ParachuteComputer/parachute-vault/pull/275) (`5a278cc`) — full transactional tag-rename cascade. Single `BEGIN IMMEDIATE`, ROLLBACK on any throw. Pre-flight collision check returns `{error: "target_exists", conflicting: [...]}` without touching the DB. Cascades through `tags.name` PK + sub-tag prefixes (recursive), `note_tags.tag_name`, `tags.parent_names` JSON, `tokens.scoped_tags` JSON, `indexed_fields.declarer_tags` JSON, note body content (`#oldname` / `[[_tags/oldname]]`), and `_tags/<oldname>` paths. Returns structured cascade stats. Replaces the prior fail-closed 409 on token-referenced tags.

**Affected:**

- `parachute-patterns` — `tag-data-model.md` rewritten to describe the
  shipped model (multi-inheritance, `_default`, schema_conflict warning,
  rename cascade); migration history section added recording the
  three-step arc (vault#245 → vault#249 → vault#269+#272). New
  `vault-mcp-discovery.md` covers the projection + brief shape and the
  scope-filtering symmetry.
- `parachute-vault` — already shipped today; this patterns PR catches the
  doc up to reality. Future-work issues filed against vault for auto-init
  / title-templates / named-queries / AI commands (separate tracker).
- `parachute-notes` / clients — no breaking change. The Notes UI still
  reads tag schema via `list-tags { include_schema: true }` (unchanged
  surface). Clients integrating MCP get the new connect-time brief
  automatically. Clients that called the now-deleted note-schema /
  schema-mapping / synthesize-notes MCP tools must migrate to writing
  `fields` on tag records via `update-tag` (or `_default` for the
  universal-fallback case).

**Status:** patterns refresh: this PR. Vault implementation: complete in
0.4.1-rc.4.

---

## 2026-05-08 — `publicExposure` is a hub-side per-request layer-gate

**Change:** [`module-json-extensibility.md`](../patterns/module-json-extensibility.md)
refreshed — the `hasAuth` section's runtime description was stale.
`publicExposure` is now enforced **per request, in hub**, not at expose
time. Every reverse-proxied request is tagged with the layer it arrived
on (`loopback` / `tailnet` / `public`) and hub consults the target
service's `publicExposure` to decide whether to proxy or 404. The expose
surface collapses to a single hub catchall on the tailnet; per-service
expose toggles are no longer independent state.

Access matrix codified by [parachute-hub#187](https://github.com/ParachuteComputer/parachute-hub/pull/187):

| `publicExposure` | Loopback | Tailnet | Public | Gated by |
| --- | --- | --- | --- | --- |
| `"allowed"` | reaches | reaches | reaches | service's own auth |
| `"loopback"` | reaches | 404 | 404 | hub layer-gate |
| `"auth-required"` | reaches | reaches | reaches | service's own auth |

`"allowed"` and `"auth-required"` produce identical hub behavior; the
distinction is documentary intent. `"loopback"` is the only value that
withholds non-loopback traffic. The pre-#187 wording — "treated as
loopback at expose time until the operator opts in explicitly" —
described an at-expose-time filtering model that no longer matches the
runtime; scrubbed.

Closes [`parachute-patterns#39`](https://github.com/ParachuteComputer/parachute-patterns/issues/39).

**Affected:**

- `parachute-patterns` — pattern doc updated (this PR). No code change.
- `parachute-hub` — already shipped the runtime in
  [`#187`](https://github.com/ParachuteComputer/parachute-hub/pull/187).
  Pattern doc now matches.
- Module authors (vault, scribe, notes, agent, third-party) — no
  manifest change required. `hasAuth` semantics are unchanged; only the
  doc's description of how hub honors the derived `publicExposure` is
  refreshed.

**Status:** complete on 2026-05-08.

---

## 2026-05-04 — `paraclaw` renamed to `parachute-agent`

**Change:** the exploration package previously called `paraclaw` is
renamed to `parachute-agent` for naming-pattern cohesion with the rest
of the ecosystem (`parachute-vault`, `parachute-hub`, `parachute-scribe`,
`parachute-notes`). Surfaces:

| Surface | From | To |
| --- | --- | --- |
| Repo | `ParachuteComputer/paraclaw` | `ParachuteComputer/parachute-agent` |
| npm | `paraclaw` (unpublished) | `@openparachute/agent` |
| CLI binary | `claw` | `parachute-agent` |
| Mount path | `/claw` | `/agent` |
| Service registry name (services.json key) | `claw` | `agent` |
| Display name | `Paraclaw` | `Parachute Agent` |
| Container labels | `paraclaw-install=…` | `parachute-agent-install=…` |
| OAuth scopes | `claw:read` / `claw:write` / `claw:admin` | `agent:read` / `agent:write` / `agent:admin` |

The friendly informal handle `claw` is retained for local-dev tooling
(`.claude/skills/claw`, `scripts/claw`). This rename is for the formal
published surfaces — pattern docs use `parachute-agent` / `agent`
consistently going forward.

Since `paraclaw` was never published to npm, no `claw:*` tokens exist
in the wild — the OAuth scope namespace flip is a cosmetic rename, not
a breaking change for any minted bearer.

**Affected:**

- `parachute-agent` (was `paraclaw`) — full source rename in the
  upstream repo (separate PR there).
- `parachute-hub` — `SERVICE_SPECS` entry renamed; on hub start, a
  one-shot migration in `services-manifest.ts` rewrites `services.json`
  rows whose key was `claw` to `agent` (separate PR there).
- `parachute.computer` — site copy updated (separate PR there).
- `parachute-patterns` — this scrub: `oauth-scopes.md` (registered
  scope namespace), `tag-data-model.md` (adoption row),
  `tag-scoped-tokens.md` (use-case copy + adoption row + follow-up),
  `module-json-extensibility.md` (one rationale line),
  `research/tag-scoped-tokens-survey.md` (one informal mention).
  Historical migration-notes entries left in place as point-in-time
  records — readers should interpret pre-2026-05-04 references to
  `paraclaw` / `claw:*` as the package now known as `parachute-agent`.

**Status:** patterns scrub: this PR. Cross-repo PRs landing on
2026-05-04 ahead of tomorrow afternoon's publish.

---

## 2026-05-03 — `_schemas/*` retirement to `note_schemas` + `schema_mappings` (vault)

> **Superseded 2026-05-09 by vault#269.** The `note_schemas` + `schema_mappings` two-table subsystem and the six MCP tools introduced here were ripped six days later when an audit found zero operator use of the path-prefix mapping kind, and tag-mapped schemas were fully redundant with `tags.fields`. Note-validation now lives on `tags.fields` with `_default` as the universal-fallback ancestor. See the 2026-05-09 entry above. Entry kept for migration history.

**Change:** [`tag-data-model.md`](../patterns/tag-data-model.md) approach extended to note-validation schemas. Companion to the tag-data-model reshape (#245). Retires the `_schemas/<name>` config-note pattern + the singleton `_schema_defaults` note in favor of two SQL tables: `note_schemas (name PK, fields JSON, description, required JSON)` for schema definitions, and `schema_mappings (schema_name FK, match_kind ENUM 'path_prefix' | 'tag', match_value)` for the path-prefix + tag-based mapping rules.

Schema migration v14 → v15: additive; data migration copies existing `_schemas/<name>` notes' metadata + `_schema_defaults` mappings → new tables. Migration is transactional (BEGIN IMMEDIATE / COMMIT or ROLLBACK), idempotent on re-runs, and verified on byte-identical copies of all three of Aaron's real DBs.

New MCP/HTTP authoring surface: `update-note-schema` / `delete-note-schema` / `list-note-schemas` / `set-schema-mapping` / `delete-schema-mapping`. MCP tool count: 10 → 16.

Tag-scope auth-check is threaded through `handleNoteSchemas` consistent with the `handleTags` precedent — tag-scoped tokens cannot enumerate or write `tag`-kind mappings outside their allowlist. `path_prefix` mappings are orthogonal to tag scope (no filter applied). String-form fallback honored.

`_schemas/<name>` notes + `_schema_defaults` note left in place post-migration as harmless historical record.

**Affected:**

- `parachute-vault` — adopted in [`vault#249`](https://github.com/ParachuteComputer/parachute-vault/pull/249), shipped at rc.33
- `parachute-patterns` — `tag-scoped-tokens.md` had stale references to `_schemas/<name>` notes scrubbed out alongside this entry (same patterns PR)
- `parachute-notes` / clients — Notes app and other vault clients should migrate any direct reads/writes against `_schemas/<name>` paths to the new MCP/HTTP surface; legacy reads still work for backwards-compat but won't reflect the latest schema state

**Status:** Shipped. Arc complete (tag-data-model + schemas-retirement landed across vault#245 + vault#249).

---

## 2026-05-03 — Tag data model reshape (vault)

**Change:** [`tag-data-model.md`](../patterns/tag-data-model.md) introduced.
Retires the notes-as-config pattern for tag concerns: collapses
`tags + tag_schemas + _tags/<name>` into a single row on `tags` carrying
`description`, `fields`, `relationships`, and `parent_names` columns. Adds
typed-relationship declarations (named cardinality vocabulary: `one`,
`optional`, `many`, `many-required`) — declared but not enforced in Phase 1.
The hierarchy resolver swaps its data source from `_tags/*` notes to the
new `parent_names` column; cache invalidation moves to `tags` row writes.
Companion retirement of `_schemas/*` pattern (note-validation defaults)
folds in the same sprint.

**Why:** notes are user content; system configuration belongs in tables.
The historical config-as-note convention pre-dated tags being first-class
SQL identities and conflated "what is a note" with "what is system
configuration." Vault is SQLite, not files-on-disk; export logic can derive
markdown from tables when needed.

**Affected:**

- `parachute-vault` — implementation pending in vault#244 (single PR on
  `ag-unforced-dev`); schema migration v13 → v14 + data migration from
  `tag_schemas` and `_tags/*` notes
- `parachute-patterns` — `tag-scoped-tokens.md` §Storage details still
  describes cache invalidation as firing on `_tags/*` writes; post-migration
  it fires on `tags` row writes. Update on next patterns PR alongside the
  vault implementation merge

**Status:** Design merged via patterns#29. Implementation shipped in [`vault#245`](https://github.com/ParachuteComputer/parachute-vault/pull/245) at rc.31. Companion `_schemas/*` retirement shipped at rc.33 via vault#249 — see entry above. Arc complete.

---

## 2026-05-03 — Tag-scoped tokens Phase 1 (vault)

**Change:** [`tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md) Phase 1
lands in vault — per-token `scoped_tags` (whitelist of tag roots; absent =
unrestricted) enforced on read and write across HTTP and MCP. Schema
migration v13 adds the `scoped_tags TEXT` column on `tokens` (JSON array,
nullable). Auth checks the parsed allowlist with a **string-form fallback**
on the raw root: `t.split("/")[0]` is matched against the token's raw scope
list, so an orphan sub-tag (one without a `tag_schemas` row for its root)
stays accessible to a token scoped to that root — fail-open on the read
path so missing schema rows can never silently hide notes. Mint validation
rejects path-form scopes (`vault:foo/bar:read`) — only roots are
mintable. Tag-dependency 409 guards on `DELETE /tags/:name`,
`POST /tags/merge`, and `POST /tags/:name/rename` (and the MCP `delete-tag`
tool) refuse the operation when any live token references the tag, returning
`{error_type: "tag_in_use_by_tokens", tag, referenced_by: [{id, label}]}` —
fail-closed so token authorities can't be silently invalidated by a
schema-side rename or delete. Out-of-scope reads return 404 (not 403);
out-of-scope writes return 403 `tag_scope_violation`.

**Affected:**

- `parachute-vault` — adopted in
  [`#241`](https://github.com/ParachuteComputer/parachute-vault/pull/241)
  (rc.30, merged 2026-05-03). Reference: `src/tag-scope.ts`
  (`noteWithinTagScope` / `tagsWithinScope` / `filterNotesByTagScope`),
  `src/token-store.ts` (`findTokensReferencingTag`), `src/mcp-tools.ts`
  (`applyTagDependencyGuards` always-on wrapper, `applyTagScopeWrappers`
  scoped-only). Phase 2 (rename cascade across token rows + path-form
  scope semantics) tracked in
  [`#240`](https://github.com/ParachuteComputer/parachute-vault/issues/240).
- `paraclaw` — Phase 2 work; will gain a parallel `claw:` scope-tag
  vocabulary once vault Phase 2 ships. No code change required for
  Phase 1.
- `parachute-notes` — no change. PWA reads/writes go through the
  existing token; out-of-scope cells materialize as 404 from vault.
- `parachute-hub` — no OAuth-layer change. `vault:<name>:<verb>` scope
  shape unchanged; tag scoping is a vault-internal token attribute,
  not exposed in OAuth picker UI for Phase 1.

**Status:** Phase 1 complete on 2026-05-03 (vault rc.30). Phase 2
(cascade + path-form) deferred pending data-model architecture doc.

---

## 2026-05-02 — `module.json` gains `managementUrl`

**Change:** [`module-json-extensibility.md`](../patterns/module-json-extensibility.md)
adds one optional field — `managementUrl?: string` — declaring where a
module's admin UI lives.

- Relative path (e.g. `"/admin"`) — hub resolves against the module's
  well-known origin (`<module-url><managementUrl>`).
- Full absolute URL — hub uses verbatim.
- Absent — no link rendered (CLI-only management, or no admin surface).

Aaron's call recorded 2026-05-02: per-module admin UIs live with the
modules. Hub stays a thin directory + link-out; each module owns its
admin surface end-to-end. Avoids hub leaking module-internal API shapes
(vault's name list, scribe's job queue, etc.) into the portal.
Backwards-compatible — same rule as `hasAuth` / `init` / `urlForEntry`:
absent = "not present". Continues the schema work from
[`parachute-patterns#19`](https://github.com/ParachuteComputer/parachute-patterns/pull/19).
Closes [`parachute-patterns#20`](https://github.com/ParachuteComputer/parachute-patterns/issues/20).

**Affected:**

- `parachute-patterns` — pattern doc updated (this PR). No code change.
- `parachute-vault` — will declare `managementUrl: "/admin"` once
  vault-side SPA Phase A ships
  ([`parachute-vault#216`](https://github.com/ParachuteComputer/parachute-vault/issues/216)).
- `parachute-hub` — reads `managementUrl` from each module's well-known
  doc and renders a "Manage <displayName>" link on the vault list /
  directory page
  ([`parachute-hub#158`](https://github.com/ParachuteComputer/parachute-hub/issues/158)).
- `parachute-scribe`, `parachute-notes`, `paraclaw` — opportunity to
  adopt later (each can ship its own admin UI if/when one materializes;
  not on the immediate roadmap).

**Status:** pattern doc landed (this PR). Vault adoption + hub render
PRs pending.

---

## 2026-04-30 — `module.json` gains `hasAuth`, `init`, `urlForEntry`

**Change:** [`module-json-extensibility.md`](../patterns/module-json-extensibility.md)
adds three optional fields so the canonical schema can carry behaviors
hub's transitional `FIRST_PARTY_FALLBACKS.extras` block currently holds:

- `hasAuth: boolean` — module is itself an OAuth resource server. Drives
  the default `publicExposure` for `kind: "api" | "tool"` services.
- `init: { command: [string, ...string[]] }` — post-install one-shot.
  Safety constraint: `command[0]` must equal a bin from the installed
  npm package (rejects e.g. `["rm", "-rf", "/"]` at install time).
- `urlForEntry.perConsumer.<consumerId>: { appendPath? | replaceWith? }`
  — declarative URL adjustment per well-known consumer (today's only
  case: claude.ai → vault gets `/mcp` appended).

Aaron's call recorded 2026-04-30: **path 1 (extend the schema) over
path 2 (codify a permanent extras lane)**. Closes
[`parachute-hub#100`](https://github.com/ParachuteComputer/parachute-hub/issues/100).
Backwards-compatible — every new field is optional with a sensible
"absent" default, so existing `module.json` files stay valid.

**Affected:**

- `parachute-patterns` — pattern doc updated (this PR). No code change.
- `parachute-hub` — needs a parser update in `src/module-manifest.ts`
  (read the three new fields, route them through `composeServiceSpec`)
  and an install-time bin-name check for `init.command[0]` (resolved
  via the installed package's `package.json` `bin` field). Tracked by
  hub#100.
- `parachute-vault` — emit `hasAuth: true`, `init: { command:
  ["parachute-vault", "init"] }`, and `urlForEntry.perConsumer["claude.ai"]:
  { appendPath: "/mcp" }` in `.parachute/module.json`. One PR.
- `parachute-scribe` — omit `hasAuth` (absent = `false`, the conservative
  default until `SCRIBE_AUTH_TOKEN` ships); emit `urlForEntry.perConsumer`
  if needed. One PR.
- `parachute-notes` — emit baseline fields (no `hasAuth`, no `init`).
  One PR.
- `parachute-hub` (cleanup) — delete each module's `FALLBACK:` entry in
  `src/service-spec.ts` once its upstream `module.json` ships the
  equivalent declarations. One PR per module.

**Status:** pattern doc landed (`parachute-patterns#19`). Downstream
parser + emit + retirement PRs pending.

---

## 2026-04-28 — Vault scopes are resource-bound (`vault:<name>:<verb>`)

**Change:** the hub's OAuth picker rewrites an unnamed `vault:<verb>`
request to `vault:<picked>:<verb>` before issuing the auth code; vault
rejects bare `vault:<verb>` from hub-issued JWTs and strict-checks
`aud=vault.<name>` on each request. `pvt_*` tokens unaffected (legacy
direct-token path bypasses JWT validation). Closes the design discussion
in [`parachute-vault#179`](https://github.com/ParachuteComputer/parachute-vault/pull/179);
landed in [`parachute-vault#180`](https://github.com/ParachuteComputer/parachute-vault/pull/180)
and [`parachute-hub#95`](https://github.com/ParachuteComputer/parachute-hub/pull/95).
Pattern doc: [`oauth-scopes.md`](../patterns/oauth-scopes.md).

Also captured in the same pattern update:
- `claw:read` / `claw:write` / `claw:admin` registered (paraclaw vocabulary
  with admin ⊇ write ⊇ read inheritance).
- `parachute:host:admin` introduced as the first **non-requestable**
  operator-only scope (cross-vault host admin, used for hub-orchestrated
  vault provisioning via `POST /vaults`).

**Affected:**

- `parachute-vault` — reference implementation (PR #180 + #184 + #187).
  Hub-JWT bearers now go through resource-bound + audience-bound
  enforcement.
- `parachute-hub` — picker UI + `POST /vaults` + `NON_REQUESTABLE_SCOPES`
  enforcement (PR #95). Operator tokens auto-include
  `parachute:host:admin` on next mint.
- `parachute-notes` / `paraclaw` / `parachute-scribe` — no current code
  carries hardcoded `vault:read|write|admin` strings (verified at write
  time). New OAuth flows will pick up the picker rewrite automatically.
  Watch for any future hardcoded scope literal — they'd start receiving
  401s from JWT-validating vault paths.
- Existing `pvt_*` tokens keep working without change (different code
  path, no audience check). Operator-token rotation needed to pick up
  `parachute:host:admin` (run `parachute auth rotate-operator`).

**Status:** complete on 2026-04-28.

---

## 2026-04-26 — Hub is the OAuth issuer

**Change:** the hub origin is the canonical OAuth issuer for the
ecosystem. Vault still implements the OAuth endpoints, but advertises
the hub as `issuer` (and stamps it into token `iss` claims) whenever
the request reaches it via the hub origin. Falls back to the
vault-local URL on direct loopback. See
[`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md); pairs
with [`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md).

**Affected:**

- `parachute-vault` — already implements the contract. Reference:
  `resolveOAuthCoordinates` in `src/oauth.ts`, landed in
  [#147](https://github.com/ParachuteComputer/parachute-vault/pull/147)
  and refined in
  [#152](https://github.com/ParachuteComputer/parachute-vault/pull/152).
- `parachute-hub` (renamed from `parachute-cli` —
  [cli#55](https://github.com/ParachuteComputer/parachute-cli/issues/55))
  — derives the canonical hub origin in `src/hub-origin.ts` and passes
  it through as `PARACHUTE_HUB_ORIGIN` on `expose up` / `start`.
- `parachute-scribe`, `parachute-channel`, future modules — when they
  begin OAuth enforcement, validate `iss` against the hub origin (not
  their own URL). No code change needed before they implement OAuth.
- Phase B2 cutover (hub becomes IdP itself) tracked in
  [hub#58](https://github.com/ParachuteComputer/parachute-hub/issues/58)
  and
  [vault#169](https://github.com/ParachuteComputer/parachute-vault/issues/169).

**Status:** Phase 0+1 complete on 2026-04-20. Phase B2 in design.

---

## 2026-04-26 — Well-known discovery URLs follow RFC 8414 §3.1

**Change:** OAuth metadata for an issuer with a path component lives
at `<origin>/.well-known/<type>/<issuer-path>` (path-insertion), not
`<issuer>/.well-known/<type>` (path-append). Vault serves both for
client compatibility, but path-insertion is the canonical advertised
form. See
[`patterns/well-known-discovery-rfc.md`](../patterns/well-known-discovery-rfc.md);
pairs with [`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md).

**Affected:**

- `parachute-vault` — already conforms. Path-insertion routes added
  in [#149](https://github.com/ParachuteComputer/parachute-vault/pull/149)
  after the `/vault/<name>/` URL migration; path-append routes have
  been there since launch. Reference: top of `route()` in
  `src/routing.ts`.
- `parachute-hub` (renamed from `parachute-cli` —
  [cli#55](https://github.com/ParachuteComputer/parachute-cli/issues/55))
  — picks this up when the hub becomes the IdP itself in Phase B2
  ([hub#58](https://github.com/ParachuteComputer/parachute-hub/issues/58)).
  Hub origin has no path component, so insertion and append collapse
  to the same `/.well-known/<type>` URL — the distinction only
  matters for issuers with a path.
- `parachute-scribe`, `parachute-channel`, future modules — when they
  begin serving OAuth metadata, serve both shapes for any path-rooted
  issuer they advertise.

**Status:** complete for vault on 2026-04-20 (PR #149). Other modules
not yet OAuth-enforcing.

---

## 2026-04-26 — Parallel cross-repo PRs documented

**Change:** new pattern doc
[`patterns/parallel-cross-repo-PRs.md`](../patterns/parallel-cross-repo-PRs.md).
When a single conceptual change spans multiple Parachute repos, the
team-lead briefs each steward in parallel and each steward opens its
own PR independently. No master PR, no orchestration branch, no
"merge X first" instructions. The composition is parallel-safe by
design — additive contracts, backwards-compatible shape changes, or
symmetric contracts that exist on both sides. Captures the shipping
shape already used for OAuth Phase 0 (4 simultaneous PRs) and
stateless-scribe.

**Affected:**

- Team-lead / patterns steward — adopt the convention going forward;
  use it to scope multi-repo changes before briefing the stewards.
- Tentacle stewards — each PR's description references the shared
  design doc / brief note; no cross-PR coordination mid-flight.
- Future ecosystem-wide changes — design parallel-safe scope first,
  brief stewards in parallel second.

**Status:** convention documented on 2026-04-26. Already in active
use during launch-week shipping (OAuth Phase 0, stateless scribe);
this writes it down.

---

## 2026-04-26 — Reviewer-agent convention documented

**Change:** new pattern doc
[`patterns/reviewer-agent.md`](../patterns/reviewer-agent.md). For PRs
touching auth / scope / schema / public API / module-protocol /
inter-service contracts, the team-lead runs a fresh-spawn `reviewer`
agent against the diff before recommending merge. Convention, not
enforcement; pairs with [`governance.md`](../patterns/governance.md)
Rule 1 (every PR reviewed by a team-lead role and merged by a human).
The reviewer agent's value is the fresh-context pass — both steward
and team-lead are anchored to what they meant the change to do; a
fresh agent reads the diff cold against named patterns / RFCs /
surrounding code and surfaces the gap.

**Affected:**

- Team-lead / patterns steward — adopt the convention going forward;
  cite reviewer findings in the verification summary.
- Future PRs in the listed change-classes — should expect a reviewer
  pass.

**Status:** convention documented on 2026-04-26. Already in informal
use during launch-week shipping; this writes it down.

---

## 2026-04-26 — Module JSON extensibility (target convention)

**Change:** new pattern doc
[`patterns/module-json-extensibility.md`](../patterns/module-json-extensibility.md)
— third-party modules declare themselves via a `.parachute/module.json`
file shipped in the npm package; `name` / `manifestName` /
`displayName` / `tagline` / `kind` / `port` / `paths` / `health` /
`startCmd` / `scopes` / `dependencies`. **No `@openparachute/` scope or
`parachute-*` prefix required** — the contract is what makes a module
a Parachute module, not its name. **Status: target, not yet
implemented in `parachute install`.** Today the hub uses a hardcoded
`SERVICE_SPECS` fallback — a first-party shortcut, not an
architectural limit.

**Affected:**

- `parachute-hub` — needs the `module.json` reader / validator /
  installer step before this is real. Tracked as Phase 3 work in the
  design doc. Hardcoded `SERVICE_SPECS` retires (or shrinks to a
  transitional fallback) when `module.json` lands.
- `parachute-vault`, `parachute-notes`, `parachute-scribe`,
  `parachute-channel` — when the convention lands, ship
  `.parachute/module.json` matching what each currently asserts
  through `SERVICE_SPECS`. No runtime change.
- Third-party authors — the canonical shape, today, is in
  [`parachute.computer/design/2026-04-20-module-architecture.md`](https://github.com/ParachuteComputer/parachute.computer/blob/main/design/2026-04-20-module-architecture.md)
  (extensibility section). The pattern doc is the durable reference.

**Status:** convention documented; hub implementation deferred to
Phase 3.

---

## 2026-04-26 — Mount-path convention documented

**Change:** new pattern doc
[`patterns/mount-path-convention.md`](../patterns/mount-path-convention.md).
Frontend modules are served at a subpath under the ecosystem origin
(today: `/notes/`), declared once via Vite `base` and read by everyone
through `import.meta.env.BASE_URL`. Three coordinated downstream
consumers — Vite asset URLs, React Router `basename`, PWA manifest
`scope` / `start_url` / `id`. Internal routes are mount-relative
(`/n/:id`, not `/notes/n/:id`); the router's basename does the
prefixing. OAuth redirect URIs read `BASE_URL` so the callback resolves
under the deployed mount. Override knob: `VITE_BASE_PATH`.

**Affected:**

- `parachute-notes` — reference implementation, already conformant.
  Refactor sequence: PR
  [#49](https://github.com/ParachuteComputer/parachute-notes/pull/49)
  (move `base` to `/notes`) → PR
  [#50](https://github.com/ParachuteComputer/parachute-notes/pull/50)
  (drop `/notes/` from internal routes) → PR
  [#54](https://github.com/ParachuteComputer/parachute-notes/pull/54)
  (deep-link shim for pre-refactor bookmarks). Architecture writeup at
  the top of `parachute-notes/CLAUDE.md` already forward-references
  this doc.
- Future Parachute frontends (PWAs / SPAs) — adopt the same shape: pick
  a stable slug, set Vite `base`, write mount-relative routes, mirror
  the manifest. Hub catalog (`/.well-known/parachute.json`) auto-renders
  any frontend module that publishes a `services.json` entry with
  `kind: "frontend"`.
- Third-party frontends — same contract. Standard SPA-under-subpath
  hygiene; nothing Parachute-specific.

**Status:** complete on 2026-04-26 for `parachute-notes`. Pattern doc
captures live behavior; no service-side changes required.

---

## 2026-04-26 — Service-to-service auth is a single-validator seam

**Change:** inter-service calls (vault → scribe today; future pairs
later) authenticate via a bearer token validated by a single
function on the callee — `validateToken(token) → {valid, scopes}`.
The CLI mints the secret on install and writes it to both ends. The
upgrade path to hub-issued JWTs in Phase B2 is a body-swap of that
one function; callers and callees don't change. See
[`patterns/service-to-service-auth.md`](../patterns/service-to-service-auth.md);
pairs with [`patterns/hub-as-issuer.md`](../patterns/hub-as-issuer.md)
and [`patterns/oauth-scopes.md`](../patterns/oauth-scopes.md).

**Affected:**

- `parachute-hub` — already implements the trust broker in
  `src/auto-wire.ts` (mints `SCRIBE_AUTH_TOKEN`, writes to vault `.env`
  and scribe `config.json`, idempotent, restarts vault). No code
  change needed; pattern documents what's there.
- `parachute-scribe` — already implements the validator seam in
  `src/auth.ts`. Returns scopes-on-success even on the shared-secret
  path so the JWT swap is callable-compatible.
- `parachute-vault` — caller-side resolver in `src/scribe-env.ts`
  handles canonical `SCRIBE_AUTH_TOKEN` + deprecated `SCRIBE_TOKEN`
  with a one-shot warning.
- Phase B2 cutover (`validateToken` body becomes JWT verify; shared
  scope-guard library) tracked in
  [hub#59](https://github.com/ParachuteComputer/parachute-hub/issues/59).
- Future inter-service pairs — declare the env var name in
  `.parachute/module.json` and `auto-wire` provisions on install.

**Status:** Phase 0+1 complete on 2026-04-23 for the vault↔scribe
pair. Phase B2 in design.

---

## 2026-04-26 — Writes require `if_updated_at` (or explicit `force: true`)

**Change:** Parachute write APIs require an `if_updated_at`
precondition by default; `force: true` is the explicit opt-out.
Conflicts return a structured 409 (`error_type: "conflict"` +
`current_updated_at` / `your_updated_at` / `path` / `note_id`);
missing precondition returns a structured 428 (RFC 6585,
`error_type: "precondition_required"`). Single-resource reads
always include `updated_at` so the next write has a token. See
[`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md).

**Affected:**

- `parachute-vault` — reference implementation.
  [#153](https://github.com/ParachuteComputer/parachute-vault/pull/153)
  landed required `if_updated_at` + the structured conflict shape.
  Both HTTP (`src/routes.ts`) and MCP (`src/mcp-http.ts`) tool
  surfaces enforce identically.
- `parachute-notes` — must forward `if_updated_at` from PWA edits to
  vault writes; don't strip it. PWA's local store should hold the
  last-seen `updated_at` per note.
- Future API-surface modules — adopt the same shape on every mutating
  endpoint over a database-backed resource. Pattern doc has the rules.

**Status:** complete for vault on 2026-04-23 (PR #153). Notes adoption
ongoing — confirm on next touch.

---

## 2026-04-26 — Context-in-payload pattern documented

**Change:** new pattern doc
[`patterns/context-in-payload.md`](../patterns/context-in-payload.md). The
provider pre-fetches narrowly-scoped context (a few dozen names) and ships
it inline in the trigger payload — multipart `context` part for attachment
sends, top-level `context: {...}` field for JSON sends. The consumer is
stateless: parses tolerantly and never calls back into the provider. Empty
payload → no part attached. Reference pair: `parachute-vault` →
`parachute-scribe` for transcription proper-noun correction (vault
[#156](https://github.com/ParachuteComputer/parachute-vault/pull/156)).

**Affected:**

- `parachute-vault` — already conformant. `src/context.ts`
  (`fetchContextEntries`, `appendContextPart`) implements the provider
  side; trigger config exposes `include_context` (predicate list with
  `tag` / `exclude_tag` / `include_metadata`).
- `parachute-scribe` — already conformant. `src/context.ts`
  (`parseContextPayload`, `buildProperNounsBlockFromEntries`) implements
  the tolerant consumer side.
- Future modules taking context-relevant free-text (cleanup, summarization,
  classification) — adopt the same `entries[]` shape on receive. Future
  context-providing modules — emit the exact same shape, do not fork into a
  per-provider schema.

**Status:** complete on 2026-04-26. Pattern doc captures live behavior; no
service-side changes required.

---

## 2026-04-25 — CLI is the port authority at install time

**Change:** `parachute install` now picks each service's port up front and
writes `PORT=<n>` into `~/.parachute/<svc>/.env`. Idempotent — an existing
`PORT` in `.env` wins, so re-installs and user-edited ports survive
upgrades. See [`patterns/cli-as-port-authority.md`](../patterns/cli-as-port-authority.md);
pairs with [`patterns/canonical-ports.md`](../patterns/canonical-ports.md).

**Affected:**

- `parachute-cli` — implemented in
  [#54](https://github.com/ParachuteComputer/parachute-cli/pull/54)
  (closes #53). Helper: `src/port-assign.ts`. Hook: `src/commands/install.ts`.
- `parachute-vault`, `parachute-notes`, `parachute-scribe`,
  `parachute-channel` — no service-side changes required. Each already
  reads `PORT` from env with a compiled-in fallback; the CLI's `.env`
  value is merged into the spawn env by `lifecycle.start`. Confirm the
  pattern on the next touch and add a comment if a service hard-codes its
  port instead of reading env.
- Third-party / future modules — same contract: read `PORT` from env, fall
  back compiled-in, no integration with the CLI required.

**Status:** complete for committed-core services on 2026-04-25.

---

## 2026-04-15 — `parachute-*` bin naming

**Change:** all Parachute executables adopt the `parachute-<module>` prefix
(see `naming/bins.md`). The umbrella `parachute` bin is reserved for
`@openparachute/cli`.

**Affected:**

- `parachute-vault` — renamed `parachute` → `parachute-vault` in
  [#134](https://github.com/ParachuteComputer/parachute-vault/pull/134) (2026-04-21).
- `parachute-scribe` — renamed `scribe` → `parachute-scribe` in
  [#9](https://github.com/ParachuteComputer/parachute-scribe/pull/9) (2026-04-22).
- `parachute-narrate` — not yet published; will ship as
  `parachute-narrate` from day one.
- `parachute-channel` — conformant (`parachute-channel`, `parachute-channel-bridge`).
- `parachute-agents` — conformant (`parachute-agent`, `parachute-agent-ui`).
- `tailshare` — exempt; not a Parachute-branded tool.

**Status:** complete for shipped modules. Narrate to follow on first publish.

---

## 2026-04-15 — parachute-patterns repo created

**Change:** this repo exists. Conventions that were implicit across the
ecosystem (naming, brand palette, agent schema, modularity principle, etc.)
are now written down.

**Affected:** every Parachute repo eventually needs a README link back to
this repo (`adoption/checklist.md`). Non-urgent — add as repos get touched.

**Status:** in progress.

---

## Template

```
## YYYY-MM-DD — <one-line change>

**Change:** what changed and why. Link to the pattern file.

**Affected:** which repos need to follow and what specifically each needs
to do.

**Status:** DRAFT | in progress | complete.
```
