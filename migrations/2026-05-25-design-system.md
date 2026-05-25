---
title: Design system adoption
date: 2026-05-25
status: active
originating-pr: parachute-patterns#94 (`patterns/design-system.md` — workstream A)
---

# Design system adoption

The 2026-05-25 UI/UX audit ([`parachute-hub/AUDIT-UI-UX.md`](https://github.com/ParachuteComputer/parachute-hub/blob/main/AUDIT-UI-UX.md)) found Parachute shipping eight distinct surfaces with two-and-a-half palettes, three brand marks, two competing taglines, and six action verbs covering the same OAuth approval flow. Workstream A — declare a Parachute design system in `parachute-patterns/` — landed at [patterns#94](https://github.com/ParachuteComputer/parachute-patterns/pull/94) as the lighthouse every downstream UI consistency fix points at.

This file is the propagation checklist. Workstreams B/C/F/G/I/J each tick off their row when they land in the relevant committed-core repo. See [`../patterns/design-system.md`](../patterns/design-system.md) for the source-of-truth on palette / type / verbs / states / components.

The shift in one line: **every committed-core admin chrome surface adopts the canonical sage palette + privacy-safe type stack + canonical verbs/states/components**, replacing the per-surface bespoke palettes/marks/copy that drifted across modules.

## Why the discipline

design-system.md is a 920-line doc that fans out across six committed-core repos. Without a propagation checklist, individual workstream PRs land in isolation and there's no single place to ask "is the design system fully propagated?" or "which workstream is the bottleneck?" Per the format in [`README.md`](./README.md), this file tracks every adopter — code references first, doc references second, operator-facing third.

The design-system.md PR ([patterns#94](https://github.com/ParachuteComputer/parachute-patterns/pull/94)) itself deferred this file to "the first workstream PR that adopts from the doc — at which point the checklist is created with concrete items covering B/C/F/G/I/J and gets ticked off as each lands." Workstream B (parachute-app reskin) is that first PR; this migration file ships alongside it.

## Workstream menu

The five workstreams downstream of design-system.md, ranked by the audit's gap-size in §9 (biggest first):

| Workstream | What it does | Owner module |
|---|---|---|
| **B** | Reskin parachute-app admin SPA — the single largest visual outlier | parachute-app |
| **C** | Declare `uiUrl` in vault + scribe `module.json` so the discovery page uses canonical chrome instead of bespoke tiles | parachute-vault, parachute-scribe |
| **F** | Unify state vocabulary across CLI (`running` / `stopped`) and SPA (`active` / `pending-oauth` / `disabled`) → canonical `active` / `pending` / `inactive` / `failing` | parachute-hub (CLI + SPA in one repo) |
| **G** | Retire the three legacy brand marks (`🪂` favicon, `⌬` OAuth glyph, `S` scribe letter-mark) + ship the 32px persistent chrome strip across server-rendered + module-served surfaces | parachute-hub (then propagated) |
| **I** | Audit + rewrite action-verb copy across OAuth + login + forms per §5 vocabulary | parachute-hub |
| **J** | First-class loading / empty / error components shared across all surfaces; unify the two banner naming conventions (`.error-banner` ↔ `.banner-error`) | parachute-hub (then propagated) |

## Code references

Per-workstream checklists. Each item is a checkbox + `repo:path` + (when in flight) the PR number that addresses it.

### Workstream B — parachute-app admin SPA reskin

- [x] `parachute-app/web/admin/src/styles.css` — adopt canonical palette + radii + privacy-safe type stack; existing class names preserved as canonical-shape aliases. ([parachute-app#35](https://github.com/ParachuteComputer/parachute-app/pull/35))
- [x] `parachute-app/web/admin/src/components/BrandMark.tsx` — inline canonical SVG mark from design-system.md §2 verbatim (38 paths verified). ([parachute-app#35](https://github.com/ParachuteComputer/parachute-app/pull/35))
- [x] `parachute-app/web/admin/src/App.tsx` — brand-line swap from `parachute-app · admin` lowercase-hyphenated header to mark + `Parachute` wordmark + `app` chip per §7. ([parachute-app#35](https://github.com/ParachuteComputer/parachute-app/pull/35))
- [x] `parachute-app/web/admin/src/routes/Modules.tsx` — per-row `Remove` → `Uninstall` rename (canonical verb per §5) + `destructive` button class. ([parachute-app#35](https://github.com/ParachuteComputer/parachute-app/pull/35))

### Workstream C — vault + scribe `module.json` `uiUrl` declarations

- [ ] `parachute-vault/.parachute/module.json` — declare `uiUrl` so hub-discovery + admin SPA render the canonical chrome instead of a bespoke vault tile.
- [ ] `parachute-scribe/.parachute/module.json` — same.
- [ ] `parachute-hub/src/api-modules.ts` — verify the discovery page consumes the new `uiUrl` field as designed.

### Workstream F — state vocabulary unification

CSS renames + supervisor state model refresh; CLI column shape change.

- [ ] `parachute-hub/web/ui/src/styles.css` — rename `.status-pending-oauth` → `.status-pending`, `.status-disabled` → `.status-inactive`; add `.status-failing` (per §6 §7); keep one-release back-compat aliases.
- [ ] `parachute-hub/src/commands/status.ts` — collapse `PROCESS` + `HEALTH` columns into one `STATE` column; map to `active` / `pending` / `inactive` / `failing` per §6 rollup.
- [ ] `parachute-hub/web/ui/src/routes/Modules.tsx` (or wherever the status badge is rendered) — swap copy to lowercase canonical states (`active` / `pending` / `inactive` / `failing`).
- [ ] `parachute-hub/src/supervisor.ts` (or wherever supervisor state is owned) — rename internal `pending-oauth` → `pending`, `disabled` → `inactive`; introduce `failing` based on consecutive health-probe failures (recommended threshold: 3).

### Workstream G — retire legacy brand marks + persistent chrome strip

- [ ] `parachute-hub/src/hub.ts:124` — `🪂` favicon → canonical SVG mark.
- [ ] `parachute-hub/src/oauth-ui.ts:260,348,515,686,798` — `⌬ Parachute` → canonical mark + wordmark.
- [ ] `parachute-hub/src/admin-login-ui.ts:67-69` — `⌬ Parachute admin` → canonical mark + wordmark + `admin` chip.
- [ ] `parachute-hub/web/ui/src/App.tsx` — `Parachute Admin <sub>` → canonical brand component (mark + wordmark + chip).
- [ ] `parachute-scribe/src/admin-ui.ts:80,83` — `S Scribe · configuration` → canonical mark + wordmark + `scribe` chip.
- [ ] `parachute-hub/src/admin-login-ui.ts` + `oauth-ui.ts` — rename `.brand-tag` class → `.brand-chip` (HTML emit sites + CSS); keep one-release alias per design-system.md §7.
- [ ] Persistent chrome strip middleware (location TBD per workstream G's call): hub-server middleware OR module-side import. Inject the 32px `.pc-chrome` shape from §7 on every server-rendered + module-served surface listed in §8 Circle 1.

### Workstream I — verb-copy sweep

OAuth-flow copy primarily; the admin SPAs are mostly canonical already.

- [ ] `parachute-hub/src/oauth-ui.ts:351,376` — `<title>Authorize <client>?</title>` → `Approve <client> · Parachute`.
- [ ] `parachute-hub/src/oauth-ui.ts:508` — pending-client inline submit `Approve and continue` → `Approve`.
- [ ] `parachute-hub/src/oauth-ui.ts:592` — `Sign in as admin to approve` → `Sign in to approve`.
- [ ] `parachute-hub/src/oauth-ui.ts` — pending-client `<title>` `App not yet approved` → `Approve <client>?`.

### Workstream J — shared loading / empty / error components

- [ ] `parachute-hub/web/ui/src/styles.css` — rename `.error-banner` / `.warn-banner` → `.banner-error` / `.banner-warn` / `.banner-success` per §7 (with one-release back-compat alias).
- [ ] `parachute-hub/web/ui/src/components/Loading.tsx` (new) — canonical loading spinner per §7, replaces ad-hoc `<p className="loading">Loading…</p>` inline patterns.
- [ ] `parachute-hub/web/ui/src/components/Empty.tsx` (new) — canonical empty-state shapes (`.empty` minimal + `.empty-rich` per §7).
- [ ] `parachute-vault/web/ui/src/styles.css` — pick up the renamed banner classes once they ship.
- [ ] `parachute-app/web/admin/src/styles.css` — pick up the renamed banner classes once they ship (in this PR, `.error` / `.warning` / `.success` map to the canonical visual via aliases; rename in a follow-up after the canonical class names ship in hub).
- [ ] `parachute-scribe/src/admin-ui.ts` — replace `<fieldset class="loading"><legend>...</legend></fieldset>` form-shaped loader with the canonical spinner.

## Doc references

Patterns + guides that quote the design-system canon. Update as the doc evolves.

- [x] `parachute-patterns/patterns/design-system.md` — the canon itself. (patterns#94)
- [ ] `parachute-patterns/brand/palette.md` + `brand/typography.md` + `brand/tokens.css` + `brand/motifs.md` — `[DRAFT]` stubs that are superseded by design-system.md. Cleanup options per §9 (delete, redirect, or reframe as the Daily-Flutter palette). Not in scope for the workstreams above; flag for a separate cleanup PR.
- [ ] `parachute-patterns/scripts/audit-canonical-refs.sh` — extend to grep for design-system canon (e.g. `--accent: #(?!4a7c59)`, hardcoded `#1e6bb8`, `font-size: 15px` outside body-default contexts) as workstreams B/F land. Currently only checks committed-core list references.

## Operator-facing references

The design system is mostly an internal-coherence concern — it doesn't expose operator-facing copy beyond what the workstreams above sweep. Two cases where it surfaces:

- [ ] `parachute.computer/design/` — when the next design doc lands, it should reference design-system.md as the canonical visual language rather than re-deriving its decisions.
- [ ] `parachute-hub/README.md` — if/when the README documents the admin UI screenshots, the canonical-palette screenshot should replace any captured pre-Workstream-B/F/G.

## External references

- [ ] GitHub repo description for `parachute-patterns` — optionally add "(visual + verbal canon for the Parachute ecosystem)" framing.

## What landed in the originating PRs

- [patterns#94](https://github.com/ParachuteComputer/parachute-patterns/pull/94) — the design system canon (920 lines, 10 sections, every committed-core surface inventoried).
- [parachute-app#35](https://github.com/ParachuteComputer/parachute-app/pull/35) — workstream B reskin of the largest outlier. Ships with this migration file as a sibling PR.

## Cross-references

- [`../patterns/design-system.md`](../patterns/design-system.md) — the source-of-truth canon.
- [`../patterns/governance.md`](../patterns/governance.md) — rule 3 (every PR review surfaces which patterns the change touches) makes per-PR conformance checks mandatory; the reviewer agent applies the design-system-specific checks per design-system.md §9.
- [`./README.md`](./README.md) — the migration-file discipline + format.
- [`./2026-05-21-notes-as-app.md`](./2026-05-21-notes-as-app.md) — the canonical example, also still active (notes-daemon retirement is in Phase 3-4).
