# Parachute design system

The canonical visual + verbal language for every Parachute surface — the lighthouse this repo points at when a downstream module asks "what does a Parachute thing look like?"

This file declares: one brand mark, one tagline (pending confirmation), one palette, one type stack, one verb vocabulary, one state vocabulary, one component library. Every committed-core module — hub server-rendered surfaces, hub admin SPA, vault SPA, app admin + bundled UIs, scribe admin — is expected to conform. The Notes PWA and the public site inherit the same tokens but own their own composition.

This doc is the lighthouse. Downstream workstreams (B/C/F/G/I/J in the 2026-05-25 audit) reference it; they do not re-derive its decisions. Update this file when the convention itself changes — adopters follow.

<!-- TODO sections — populate in order, commit each as a checkpoint -->

## 1. Why this doc exists

The 2026-05-25 UI/UX audit ([`parachute-hub/AUDIT-UI-UX.md`](https://github.com/ParachuteComputer/parachute-hub/blob/main/AUDIT-UI-UX.md)) found Parachute shipping eight distinct surfaces with two-and-a-half palettes, three brand marks, two competing taglines, and six action verbs covering the same OAuth approval flow. The audit's headline recommendation was Workstream A: **declare a Parachute design system in `parachute-patterns/`** as the single lever every downstream UI consistency fix hangs on (audit §5, recommendations A–J).

This is that doc. It supersedes the earlier `[DRAFT]` brand stubs in [`brand/palette.md`](../brand/palette.md), [`brand/typography.md`](../brand/typography.md), and [`brand/tokens.css`](../brand/tokens.css). Those files were ports of the parachute-daily Flutter app's tokens (Forest Green `#40695B`, Fraunces/Inter); they were never adopted by any committed-core web surface. The committed-core surfaces that did ship — hub-discovery, hub-OAuth, hub-admin, vault SPA, scribe admin, the Notes PWA — converged independently on a different palette (sage `#4a7c59`) and different type stack (Instrument Serif + DM Sans). This doc canonizes what shipped, not what was drafted.

Downstream workstreams gated on this lighthouse:

- **B** — adopt the design system in app-admin (replace `#1e6bb8` blue + JetBrains sans-stack with the canonical palette + type).
- **C** — declare `uiUrl` in vault + scribe `module.json` so the discovery page uses canonical chrome instead of bespoke tiles.
- **F** — unify state vocabulary across CLI (`running` / `stopped`) and SPA (`active` / `pending-oauth` / `disabled`).
- **G** — add persistent cross-surface chrome (the 32px brand strip).
- **I** — audit + rewrite action-verb copy across OAuth + login + forms.
- **J** — first-class loading / empty / error components shared across all surfaces.

Each workstream cites Section N of this file rather than re-deriving its decisions. When a convention here is wrong, change it here first and propagate downstream via a [migration doc](../migrations/README.md).

## 2. Brand identity

TODO — brand mark (inlined SVG), tagline candidates, usage rules.

## 3. Palette

TODO — codify hub-home tokens as canon; document the Google-Fonts vs no-Google-Fonts split.

## 4. Typography

TODO — Instrument Serif + DM Sans + system-font fallbacks for OAuth surfaces.

## 5. Verb vocabulary

TODO — kill Authorize/Allow/Grant duplication; settle on Sign in / Sign out / Approve / Deny / Continue. Per-domain table.

## 6. State vocabulary

TODO — pick canonical states, map old terms; workstream F adopts across surfaces.

## 7. Components

TODO — Loading / Empty / Error banner / Buttons (primary/secondary/destructive) / Brand-line / Persistent chrome strip (for Workstream G).

## 8. Where this applies

TODO — committed-core surface inheritance, Notes PWA + public site.

## 9. Adoption + enforcement

TODO — per-PR reviewer checks; migration plan listing the surfaces with biggest gap.

## 10. Open questions for branding

TODO — final tagline, custom wordmark, mobile + dark-mode coherence.
