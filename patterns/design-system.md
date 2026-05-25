# Parachute design system

The canonical visual + verbal language for every Parachute surface — the lighthouse this repo points at when a downstream module asks "what does a Parachute thing look like?"

This file declares: one brand mark, one tagline (pending confirmation), one palette, one type stack, one verb vocabulary, one state vocabulary, one component library. Every committed-core module — hub server-rendered surfaces, hub admin SPA, vault SPA, app admin + bundled UIs, scribe admin — is expected to conform. The Notes PWA and the public site inherit the same tokens but own their own composition.

This doc is the lighthouse. Downstream workstreams (B/C/F/G/I/J in the 2026-05-25 audit) reference it; they do not re-derive its decisions. Update this file when the convention itself changes — adopters follow.

<!-- TODO sections — populate in order, commit each as a checkpoint -->

## 1. Why this doc exists

TODO

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
