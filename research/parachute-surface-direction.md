# Parachute Surface — direction

> Status: **`[DRAFT]`** — early exploration, May 2026. Working name: "surface." A broader brand-coherence conversation (canopy / parachute-thematic family) is ongoing; the name may converge.

A research note for the team to think with. Captures the direction, not a build plan. Inputs to think *with*, not specs to implement.

---

## TL;DR

A new layer in the Parachute mental model: **surface**. The customizable presentation layer atop vault.

Three layers:

| Layer | What it is | Status |
|---|---|---|
| **Vault** | The data + content substrate. Notes, tags, schemas, indexed fields. | Committed core. Stable shape. |
| **Agent** | Intelligence built around the vault. AI consumer + actor. | Committed core. |
| **Surface** | Adaptable presentation layer. Renders vault content for humans, in many ways. | Exploration. This doc. |

Surface is for **humans**. Agent is for **AI**. Both consume vault. Both will exist.

Surface should work in two modes:
- **Static** — build once, deploy as HTML (like Obsidian Quartz, GitHub Pages-style).
- **Active** — runtime renderer sourcing from vault API (like Notes PWA today).

The same surface implementation should be capable of both. SSG is a deployment mode, not an architecture.

---

## Why the third layer

Today:
- **Vault** stores content. Markdown, tags, metadata. Well-shaped.
- **Notes** (the PWA) is *one* presentation atop vault. Hard-coded to a specific UI.
- **WovenBoulder** (Unforced-Dev/WovenBoulder, May 2026) is a second presentation. Static site, civic-wiki-flavored. Built externally against the vault API.

Each new presentation re-derives the wheel: how to query vault, how to slug IDs, how to render markdown, how to handle metadata. Two presentations is fine; ten would be friction.

A first-party presentation layer means:
- Shared substrate for the common pieces (data layer, rendering, metadata mapping).
- Per-deployment customization (themes, layouts, components).
- Plays well with vault's evolution (new metadata fields, new indexed-field shapes flow through).
- Can be static *or* active without re-architecting.

Notes PWA fits within this category — it's one surface instance, just bespoke.

---

## The static-vs-active duality

A surface should support both modes because both are first-class:

| Mode | Example | Properties |
|---|---|---|
| Static | A civic wiki rebuilt nightly, deployed to GH Pages | Cheap to host, no auth, content snapshot frozen at build |
| Active | Notes PWA — interactive, real-time, auth'd | Always-current, supports write-back, requires server |

Same surface code, different deployment + auth posture. The architecture should not assume one or the other.

Implication: the surface is **a thing you configure**, more than a thing you build from scratch each time. Two deployments of the same surface might differ only in (a) which vault they point at, (b) their theme/layout, (c) which components they enable.

---

## Inputs

Three inputs informing the direction. None is prescriptive.

### Input 1: WovenBoulder

A first SSG-shape exploration against vault's HTTP API. Builds a civic wiki from `vault.boulder`. Its `PARACHUTE_INSIGHTS.md` documents friction points encountered during the build.

The friction points are inputs, not specs — see the vault evaluation issue. Each warrants first-principles evaluation against vault's broader patterns before any implementation. Some may be best solved by API additions; others by tag conventions or existing primitives.

### Input 2: MDX / Astro thinking doc (Techne folder, May 2026)

A draft from the Techne conversation proposing MDX as the note format + Astro as the rendering engine. Specific framework choices; the doc itself acknowledges limited Parachute context.

What's interesting: MDX collapses the markdown-vs-rich-rendering binary. A note can stay plain markdown for portability and AI ingestion, *while* embedding components when rich rendering is desired.

What's not committed: that we must use MDX, Astro, or any specific framework. The substantive idea is that **notes can carry typed rich-rendering hooks via metadata**, while the markdown body stays portable.

### Input 3: "HTML is the new markdown" (Thariq Shihipar, Anthropic, 2026-05-08)

Argument: AI fluently generates HTML; HTML structurally beats markdown for things that get re-read, compared, or interacted with; the "markdown is easier to author" rationale weakens when an AI is the author.

Pushback: markdown's portability, diff-friendliness, paste-anywhere, AI-context-efficiency are still load-bearing for *units of meaning* (notes). The argument applies more to *artifacts* (research explainers, dashboards, design comps) than to notes per se.

Synthesis: a surface should be able to render plain markdown (the portable substrate) AND rich rendering (the visually expressive layer). The choice is per-note, declared via metadata, not enforced globally.

---

## Open questions

Pre-implementation, the surface direction has these load-bearing decisions to make:

### 1. Framework choice

Vanilla Astro+MDX? Astro+vanilla MD? Quartz-inspired bespoke? Custom-from-scratch? Something else (Next.js, Hugo, Eleventy)?

Trade-off axes: ecosystem leverage, customization ceiling, AI-extensibility, build-time vs SSR support, learning curve for users.

### 2. Content format mix

- Markdown-only (current)?
- Markdown + MDX as opt-in per note (via metadata field)?
- Markdown + HTML escape hatch?
- Mixed (each note declares its content format)?

Vault doesn't need to care which — notes are text. Surface needs to know to render correctly.

### 3. Component library

If rich rendering is supported, where do the components live? In the surface repo? A separate `parachute-components` package? Federated across instances?

Open: versioning model, contribution flow, AI-extensibility (can a user prompt for a new component on demand?), plain-text-fallback discipline.

### 4. Customizability

How configurable is a deployed surface?
- Theme (colors, typography) — definitely.
- Layout templates — likely.
- Custom components — open.
- Deeper structural changes — open.

Trade-off: more customizability = more user power but also more deployment-time complexity.

### 5. Relationship to Notes PWA

Notes is one specific surface today. When the abstract surface layer materializes:
- Does Notes become "the canonical surface, configured one way"?
- Does Notes coexist alongside a new generic surface?
- Does Notes' implementation merge into surface or stay separate?

### 6. Authoring UX

Surface affects authoring. Today, vault notes are authored via:
- Notes PWA (web)
- MCP (AI clients)
- Vault CLI

If rich content (MDX, HTML, embedded components) becomes possible, how do authors create/edit such content? Markdown + JSX in a text editor is fine for developers. Non-developers need a richer surface OR AI-assisted authoring.

### 7. Federation

A note has a stable identifier. Cross-instance referencing, embedding, syndication — interesting possibilities, big design surface. Probably deferred.

### 8. Authorship attribution + revision

Notes have authors; revisions accumulate. The surface displays these. Today vault tracks author + updated_at but no rich revision history. Surface might need richer.

---

## Where this isn't going (yet)

To keep this scoped:
- **Not** a build directive. This is a research note.
- **Not** a commitment to MDX/Astro/any specific stack.
- **Not** a vault refactor — vault stays as-is. This is downstream.
- **Not** a Notes deprecation — Notes coexists; possibly merges later.
- **Not** federation work. Defer.
- **Not** an AI-component-authoring system. Defer.

---

## Sibling artifacts

- Vault evaluation issue (parachute-vault): friction points surfaced by WovenBoulder; per-point first-principles evaluation before any API changes.
- Tracking issue (this repo): captures the open questions above; sub-discussions branch from it.

---

## Inputs (links + context)

- **WovenBoulder** — Unforced-Dev/WovenBoulder. `PARACHUTE_INSIGHTS.md` for the field-test feedback.
- **MDX / Astro thinking doc** — Aaron's Techne folder, drafted May 2026. Specific framework proposal with broad context.
- **"HTML is the new markdown"** — Thariq Shihipar, Anthropic, X post 2026-05-08, plus [Simon Willison's writeup](https://simonwillison.net/2026/May/8/unreasonable-effectiveness-of-html/).
- **Obsidian Quartz** — quartz.jzhao.xyz. Prior art for "static site generator over a markdown vault." Worth studying.
- **Three-layer mental model** — vault (data) / agent (intelligence) / surface (presentation). New as of this doc; not yet documented elsewhere.

---

*Drafted 2026-05-10. This is a working document — the team should add inputs, push back, and shape the direction.*
