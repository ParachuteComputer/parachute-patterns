# Vault MCP discovery

> One-line summary: a Parachute-Vault MCP client learns the vault's shape (tags-with-schemas, indexed fields, query hints) two ways — a markdown brief in the `initialize` response, and a JSON projection from the `vault-info` tool — both built from the same `buildVaultProjection` source, both scope-filtered when the caller is tag-scoped.

## Convention

The vault projection is one document with three shapes (one source, two surfaces, optional stats):

```ts
interface VaultProjection {
  tags: ProjectionTag[];               // tags carrying their own description or fields
  indexed_fields: ProjectionIndexedField[];
  query_hints: string[];               // verbatim catalog of query-notes shapes
  stats?: VaultStats;                  // included on request only
}

interface ProjectionTag {
  name: string;
  description: string | null;
  parents: string[];                   // verbatim from tags.parent_names
  effective_parents: string[];         // walk-order ancestor closure, _default appended when present
  fields: Record<string, TagFieldSchema> | null;       // own (verbatim from tags.fields)
  effective_fields: Record<string, SchemaField>;       // own ∪ inherited, first-in-walk wins
  relationships: TagRecord["relationships"] | null;
}
```

Built by `core/src/vault-projection.ts::buildVaultProjection(db, { includeStats? })`. Pure read; no caches mutated.

## Two surfaces, one source

### `vault-info` MCP tool — JSON projection

Returns the full `VaultProjection` JSON. Agents call this to refresh mid-session when schema or tags have changed (the connect-time brief is sent only once).

Defaults to including `stats`; the caller can flip `include_stats: false` to skip the stats roll-up. The wrapper threads tag-scope filtering through (see §Scope filtering).

### `getServerInstruction` — markdown brief at MCP `initialize`

The MCP server returns a markdown brief in the `serverInfo.instructions` field of the `initialize` response. Same projection, rendered terse. Sent **once at connect**. Goal: every fact an agent needs to start using the vault sensibly, with explicit pointers for refresh.

Shape:

```
You are connected to Parachute Vault "<name>".

<vault description, if set>

## Quick orientation (call `vault-info` for full schema)

- N notes, M tags
- K tags with schemas: <names>
- Indexed metadata fields (queryable with operators):
  - <field> (<type>; from #<tag>, #<tag>)
  - ...

## Querying

- `query-notes { tag: "X" } — all notes with tag X (includes descendants per inheritance)`
- `query-notes { tag: "X", metadata: { field: { op: value } } } — operator queries on indexed fields (eq/ne/gt/gte/lt/lte/in/not_in/exists)`
- `query-notes { search: "..." } — full-text search across content`
- `query-notes { near: { id: "..." }, depth: 2 } — graph neighborhood within N hops`
- `query-notes { id: "<note-id-or-path>" } — fetch a single note by ID or path`

## Refreshing context

If schema or tags change during this session, call `vault-info` to refresh the full projection. Call `list-tags { include_schema: true }` for tag-only details.
```

Rendered by `projectionToMarkdown` in the same file. Token budget guideline: ~600 tokens for a small vault (~4 tags-with-schemas), under ~5K at 50 tags-with-schemas.

## Scope filtering

Both surfaces are symmetric for tag-scoped tokens.

- When the caller's token has `scoped_tags`, the projection is filtered before rendering / returning. `tags` and `indexed_fields` are reduced to entries an in-scope tag contributes to. Aggregate counts in the markdown brief reflect the filtered view.
- When the caller is unscoped (`scoped_tags === null`), no filter is applied — full projection.

The filter is applied at the wrapper layer (`src/mcp-tools.ts::getServerInstruction` and the `vault-info` tool wrapper) so neither surface can leak out-of-scope tag names. A tag-scoped agent can't learn about tags outside its allowlist via the connect-time brief any more than it can via `list-tags`.

## Why one source

The brief and the JSON tool target different audiences (one-shot orient vs. on-demand refresh) and different formats (markdown vs. JSON), but they describe the same vault shape. Two computations would drift: a tag added to one surface but not the other, or different inheritance semantics, or asymmetric scope filtering.

`buildVaultProjection` is the single read path. `projectionToMarkdown` and the `vault-info` JSON serializer are render functions over its output. The scope filter (`filterProjectionForTagScope`) wraps both. Adding a future surface (REST `GET /vault/<name>/projection`, or a CLI `parachute-vault info` command) reuses the same source.

## Inheritance is visible

`ProjectionTag.effective_parents` and `effective_fields` are computed via `resolveTagInheritance`, which calls into `resolveNoteSchemas({ tags: [tag] })` — the same resolver that drives runtime validation. Walk order, conflict precedence (first-in-walk wins), and `_default` semantics are guaranteed identical between projection and validation; an agent reading `effective_fields` sees exactly what the validator will check against.

See [`tag-data-model.md`](./tag-data-model.md) §Schema inheritance for the inheritance model itself.

## Adoption

| Module | Action |
| --- | --- |
| **vault** | Shipped vault#273 (closed vault#270): `buildVaultProjection`, `projectionToMarkdown`, expanded `vault-info` tool, `getServerInstruction` rewrite. Both surfaces honor tag-scope. |
| **parachute-agent** | No code change; the agent picks up the new brief automatically on connect via standard MCP handshake. |
| **hub** | No change. |
| **notes** | No change. The Notes UI reads schema from `list-tags { include_schema: true }`, which is a separate (un-projected) surface. |

## Future evolution

| Extension | Sketch | When to revisit |
| --- | --- | --- |
| **Brief truncation heuristic** | Cap rendered tags at N, link to `vault-info` for the rest | When a vault hits ~50+ tags-with-schemas and the brief gets noisy |
| **Per-call refresh hints** | Surface "schema changed since you last connected" on `vault-info` responses | If agent confusion from stale connect-time briefs becomes real |
| **REST projection endpoint** | `GET /vault/<name>/projection` returns the same JSON | When a non-MCP client (UI, CLI tool) needs the projection without going through MCP |

## Adoption notes

- Shipped 2026-05-09 in vault 0.4.1-rc.4 (vault#273).
- Companion docs: [`tag-data-model.md`](./tag-data-model.md) (the schema model the projection describes), [`tag-scoped-tokens.md`](./tag-scoped-tokens.md) (the scope mechanism the filter respects), [`mcp-transport.md`](./mcp-transport.md) (the underlying MCP shape).

_Last updated: 2026-05-09 — current with vault 0.4.1-rc.4._
