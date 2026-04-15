# Motifs

## [DRAFT]

Parachute's visual vocabulary beyond color. What a "Parachute thing" looks
and feels like, regardless of medium.

## Principles

- **Settling, not snapping.** Motion feels like a deep breath. Standard
  transitions are 250ms with `easeOutCubic`; ambient animations can run 4s
  with `easeInOut` ("breathing"). Source:
  [design_tokens.dart `Motion`](https://github.com/ParachuteComputer/parachute-daily/blob/main/lib/core/theme/design_tokens.dart).
- **Pebbles, leaves, water ripples.** Corners are soft. Default card radius
  is 16px; buttons 12px; badges 8px; pills full. No hard right-angle card
  chrome.
- **Subtle depth.** Shadows are warm-tinted (charcoal at 4–10% alpha, small
  blur, small offset). No harsh elevation.
- **Breathing room.** Spacing leans generous. Default page padding 16px,
  section dividers 24–32px.

## Known motifs in flight

- **Silk-drift** — the ambient animation used on parachute.computer hero
  treatments. Canonical implementation lives in the
  [parachute.computer](https://github.com/ParachuteComputer/parachute.computer)
  repo. No pattern file yet — pin the component once we use it twice.
- **Octopus glyph** — used by UnforcedAGI / Octopus. Source-of-truth asset
  path TBD.
- **Card treatments** — cream surface, subtle warm shadow, generous interior
  padding (16px), soft radius. Used in Daily, octopus-ui.

## Open questions

- Publish the silk-drift component (React + CSS, or web-component) so other
  web properties can reuse it without copy-paste.
- Canonical SVG assets folder — where do Parachute glyphs live? Probably a
  branded `brand/assets/` directory here, once we have them committed.
