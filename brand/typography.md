# Typography

## [DRAFT]

The mobile app canonicalized sizes and weights in
[design_tokens.dart](https://github.com/ParachuteComputer/parachute-daily/blob/main/lib/core/theme/design_tokens.dart).
The web-side font family choices (Inter / Fraunces / JetBrains Mono) are
used in practice across `octopus-ui` and `parachute.computer`, but haven't
been pinned as a canonical stack here yet.

## Sizes (from Daily)

| Token | px |
|---|---|
| displayLarge | 48 |
| displayMedium | 36 |
| displaySmall | 28 |
| headlineLarge | 24 |
| headlineMedium | 20 |
| headlineSmall | 18 |
| titleLarge | 18 |
| titleMedium | 16 |
| titleSmall | 14 |
| bodyLarge | 16 |
| bodyMedium | 14 |
| bodySmall | 13 |
| labelLarge | 14 |
| labelMedium | 12 |
| labelSmall | 11 |

## Line heights

- `tight`: 1.2 (display, headlines)
- `normal`: 1.5 (body default)
- `relaxed`: 1.7 (long-form reading)

## Letter spacing

- `tight`: -0.5 (display)
- `normal`: 0
- `wide`: 0.5 (labels, uppercase)

## Font families — proposed (not yet canonical)

- **Sans / UI:** Inter
- **Serif / long-form:** Fraunces
- **Mono / code:** JetBrains Mono

## Open questions

- Lock the web font stack. Needs someone to audit existing web properties
  (`octopus-ui`, `parachute.computer`, the parachute-cloud dashboard) and
  reconcile.
- Variable-font vs static cutoffs, fallback stacks, self-host vs CDN — all
  unresolved. File an issue against this repo when the audit happens.
