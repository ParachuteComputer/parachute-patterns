# Brand palette

Canonical source:
[parachute-daily/lib/core/theme/design_tokens.dart](https://github.com/ParachuteComputer/parachute-daily/blob/main/lib/core/theme/design_tokens.dart).
That's the Dart/Flutter authority. `brand/tokens.css` in this repo is the
ported CSS custom-property version for web apps. Keep them in sync — any
palette change lands in Daily first, then gets ported here.

## Keywords

Smoothness, balance, growth, connected, in tune with nature. "Think
naturally" — technology that gives you space rather than demands attention.

## Primary — Forest Green (grounded, natural, trustworthy)

| Token | Hex | Use |
|---|---|---|
| `forest` | `#40695B` | primary actions, brand presence |
| `forestLight` | `#5A8577` | backgrounds, containers |
| `forestMist` | `#D4E5DF` | subtle backgrounds |
| `forestDeep` | `#2D4A40` | emphasis |

## Secondary — Turquoise (flow, clarity, breath)

| Token | Hex | Use |
|---|---|---|
| `turquoise` | `#5EA8A7` | secondary actions, links, accents |
| `turquoiseLight` | `#7FBFBE` | lighter variant |
| `turquoiseMist` | `#D5ECEB` | backgrounds |
| `turquoiseDeep` | `#3D8584` | emphasis |

## Neutrals — warm, soft tones

| Token | Hex | Use |
|---|---|---|
| `cream` | `#FAF9F7` | page backgrounds (not clinical white) |
| `softWhite` | `#FFFEFC` | surfaces with warmth |
| `stone` | `#E8E6E3` | light warm gray |
| `driftwood` | `#9B9590` | secondary text |
| `charcoal` | `#3D3A37` | primary text |
| `ink` | `#1F1D1B` | high-contrast text |

## Semantic — gentle, not alarming

| Token | Hex | Use |
|---|---|---|
| `success` / `successLight` | `#6B9B7A` / `#E3F0E7` | soft sage, not harsh |
| `warning` / `warningLight` | `#D4A056` / `#FFF3E0` | warm amber, inviting |
| `error` / `errorLight` | `#B86B5A` / `#FBEAE6` | soft terracotta — serious, not aggressive |
| `info` / `infoLight` | `#6B8BA8` / `#E6EEF4` | muted blue-gray |

## Dark mode

| Token | Hex | Use |
|---|---|---|
| `nightSurface` | `#1A1917` | base surface (deep warm dark, not pure black) |
| `nightSurfaceElevated` | `#262523` | elevated surface |
| `nightForest` | `#7AB09D` | primary (lighter for visibility) |
| `nightTurquoise` | `#8CCFCE` | secondary |
| `nightText` | `#E8E5E1` | primary text |
| `nightTextSecondary` | `#A09B95` | secondary text |

## Rules

- Never use pure `#FFFFFF` or `#000000`. We use warm cream and warm ink.
- Semantic colors are gentle on purpose — alarming red has no place in a
  "think naturally" product.
- If you need a hue we don't have, propose a new token in a PR against Daily
  first, then port here.
