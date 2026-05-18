# Format-aware notes — research

**Status:** research-tier. Real open design questions remain; not yet
a pattern.
**Date:** 2026-05-17
**Companion to:** `patterns/module-discovery.md` (umbrella),
`research/parachute-surface-direction.md` (surfaces atop vault),
`guides/building-a-surface.md` (builder companion)
**Tracker:** [parachute-patterns#65](https://github.com/ParachuteComputer/parachute-patterns/issues/65)

## Why this is research and not yet a pattern

Vault 0.4.5 introduced an `extension` column + sidecar metadata for
non-markdown notes
([vault#328](https://github.com/ParachuteComputer/parachute-vault/issues/328);
shipped at vault 0.4.5). The PWA-side counterpart — format-aware
rendering dispatch in
[notes#138](https://github.com/ParachuteComputer/parachute-notes/issues/138)
— is deferred for v0.5 but already partially scoped.

Two surfaces are already implementing pieces of an emerging pattern:
**surfaces consume vault's `extension` field to dispatch renderers.**
But the pattern isn't yet resolved across enough open questions to
write it down as a pattern doc per `CLAUDE.md`'s "document what's
real" rule. This file collects the context so the eventual pattern
doc has a starting point.

## What's shipped (vault side, 0.4.5)

Three things are real today:

1. **`extension` column** on `notes` (TEXT NOT NULL DEFAULT 'md').
   Schema migration v17 → v18. Every existing note auto-defaults to
   `'md'`; no data migration needed beyond ALTER TABLE.

2. **Sidecar metadata files** at `.parachute/notes-meta/<note-id>.yaml`
   for extensions that can't carry inline frontmatter. The predicate
   `supportsInlineFrontmatter(extension)` splits the world:
   - frontmatter-compatible: `.md`, `.mdx`, future `.org`
   - sidecar-required: `.csv`, `.yaml`, `.json`, `.txt`, etc.

   Sidecar contents are identical in shape to inline frontmatter,
   lifted into a separate file. The note's content file holds raw
   bytes of the declared format.

3. **API surface carries `extension`** on create/update/query. Notes
   created without an explicit extension default to `md`; explicit
   value pinned at create time and editable via update.

What this isn't yet: a substrate-level commitment to *validating*
the content matches the declared extension. Vault stores bytes;
extension is a declared label, not an enforced constraint.

## What's emerging (notes side, vault clients side)

Surfaces consume `extension` to pick a renderer. Notes#138 sketches
the dispatch as:

```ts
function pickRenderer(note: Note): Renderer {
  switch (note.extension) {
    case "md":   return MarkdownView;
    case "mdx":  return MdxView;       // bundle-weight concern; v3 axis
    case "csv":  return CsvTableView;  // PapaParse, read-only first pass
    case "yaml":
    case "json": return CodeMirrorView; // mode-pick on extension
    case "txt":  return PlaintextView;
    default:     return PlaintextView;
  }
}
```

The dispatcher lives in the surface, not in vault. Vault's job is to
say "this is a CSV"; the surface's job is to render it as a CSV.

If multiple surfaces (Notes, eventual third-party surfaces, agent-side
preview cards) all consume the same `extension` field but each dispatches
to its own renderer fleet, the pattern is: **vault declares; surface
dispatches**. The two sides agree on the vocabulary; nothing else
constrains them.

## Open questions

These are the questions the future pattern doc has to answer. They're
open today.

### Q1 — Where does format validation live?

When a note's content doesn't match its declared extension, who
catches it?

- **Vault validates at write time.** Pro: bytes-in-the-DB are
  always coherent with the label. Con: vault gains a per-extension
  parser dependency (CSV, YAML, JSON parsers in the substrate);
  the substrate becomes opinionated about format rules.
- **Surface validates at read time.** Pro: vault stays
  parser-agnostic; new extensions can be added without substrate
  changes. Con: malformed content sits in vault until something
  tries to render it; corruption is detected late.
- **Both.** Vault does a fast-path syntactic check at write (parse
  ok / not ok, no schema awareness); surface does a richer
  semantic check at read (required columns, type coercion). Pro:
  layered defense. Con: same parser dependency lives in two
  places; the "which check is authoritative" boundary is fuzzy.

Aaron flagged in conversation 2026-05-16 that he leans toward
**surface validates** for the v0.5 cut, then revisit if real
corruption shows up. No commitment yet.

### Q2 — How do third-party surfaces declare renderer capabilities?

A first-party surface (Notes) can hardcode its switch statement.
A third-party surface (eventual community-built surface on top of
vault) needs to advertise which extensions it can render so
clients picking a surface know what they're getting.

Candidate shapes:

- **`module.json` field** — `surfaces.extensions: ["md", "csv",
  "yaml"]`. Pros: lands cleanly in the module-discovery cluster
  (per [`module-discovery.md`](../patterns/module-discovery.md)).
  Cons: static declaration drifts from real renderer fleet over
  time.
- **Runtime endpoint** — `<surface>/capabilities/extensions`
  returns the live list. Pros: always-fresh. Cons: one more
  endpoint to spec; one more hop to render the discovery UI.
- **No declaration; fall through to plaintext** for unknown
  extensions. Pros: zero coordination. Cons: poor discoverability;
  user picks a surface without knowing if their CSVs will render.

The umbrella doc for module discovery already exists; this is a
candidate addition once Q1 + Q2 land together.

### Q3 — Sidecar lifecycle across multi-writer edits

A CSV note has a sidecar at `.parachute/notes-meta/<id>.yaml`. Two
writers each edit the CSV (the content file) without touching the
sidecar. What's the OC token shape?

- **Single `updated_at`** covering both content + sidecar. Simplest
  if both files always write together. Sidecar-only edits (e.g.
  tag change) still bump the content's `updated_at`.
- **Separate `updated_at`** per axis (content vs metadata). Two
  conflict-detection clocks; richer concurrency but more surface
  area.

Today's
[`optimistic-concurrency.md`](../patterns/optimistic-concurrency.md)
pattern only addresses single-resource writes. Multi-file notes
need either an "atomic pair" semantics or a separate clock per
file. Vault#328 ships with single-clock; whether that's
enough-for-v0.5 or needs an upgrade-path doc is open.

### Q4 — MDX bundle weight

MDX requires a JSX runtime + compiler bundle. The PWA's current
bundle is ~600KB gz; adding MDX support pushes that past 1MB. The
trade is rich-document features vs initial-load time.

Three paths:

- **Bundle MDX in the PWA.** Worst case for first paint; best UX
  for MDX users.
- **Render-on-server.** Push MDX through a hub-side or vault-side
  compiler endpoint, return HTML. Pros: keeps the PWA bundle
  small. Cons: introduces a server-side rendering surface; auth
  story for the compile endpoint.
- **Defer MDX support.** Render MDX as plaintext for v0.5; revisit
  when there's demand. Aaron's 2026-05-16 call.

Q4 is closer to a product question than an architecture question;
the pattern doc can capture the *trade* without picking a winner.

### Q5 — What does "extension" mean for binary attachments?

Vault distinguishes notes (text with extension) from attachments
(blobs under `.parachute/attachments/<id>/<filename>`). An image,
PDF, or audio file is an attachment, not a note with `extension:
png`. The line is currently drawn at "can it be text?"

If a third-party surface wants to render images inline as
note-like cards, the question becomes: are images notes with
binary content, or are they always attachments? Current answer:
attachments. The pattern doc should make this explicit so the
boundary doesn't drift.

## Cross-links

- [vault#328](https://github.com/ParachuteComputer/parachute-vault/issues/328)
  — vault-side: extension column + sidecar metadata
- [notes#138](https://github.com/ParachuteComputer/parachute-notes/issues/138)
  — notes-side: Phase 2 PWA rendering dispatch
- [`patterns/module-discovery.md`](../patterns/module-discovery.md)
  — module cluster umbrella (Q2 lands here when resolved)
- [`patterns/optimistic-concurrency.md`](../patterns/optimistic-concurrency.md)
  — single-clock OC pattern (Q3 may extend)
- [`research/parachute-surface-direction.md`](./parachute-surface-direction.md)
  — surfaces as a category (where third-party renderer-fleet
  discovery lives)
- [`guides/building-a-surface.md`](../guides/building-a-surface.md)
  — builder companion (will gain a "format-aware rendering" section
  once Q1+Q2 resolve)

## When this becomes a pattern doc

When Q1 + Q2 are resolved across vault + notes implementation. The
pattern would name:

- the substrate contract (vault declares `extension`, doesn't
  validate beyond syntactic-parse-ok),
- the surface contract (consume `extension`, dispatch renderer,
  validate semantically per surface's rules),
- the multi-writer-edit model for sidecars (Q3),
- the third-party-surface capability-declaration mechanism (Q2),
- the binary-attachments boundary (Q5).

Promote at that point per [`CLAUDE.md`](../CLAUDE.md) — remove the
research-tier prefix, move to `patterns/format-aware-notes.md`, file
adoption-notes entry, drop a tracking link from the
module-discovery umbrella's cross-links section.
