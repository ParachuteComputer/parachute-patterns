# cookbook

Concrete recipes — how to combine Parachute primitives for specific outcomes. One file per recipe, the same one-screen budget as `patterns/`.

Cookbook entries differ from `patterns/` and `guides/`:

- **`patterns/`** documents *conventions* (how Parachute modules align — names, schemas, contracts).
- **`guides/`** documents *long-form how-to* references (builder-oriented, multi-chapter, "how do I X across the whole stack").
- **`cookbook/`** documents *recipes* (one outcome, one short writeup, link out for depth).

Reach for cookbook when the answer to "how do I do X" is short and concrete enough to fit on one page, but specific enough that it doesn't belong as a `pattern`.

## Entries

- [`vault-portable-export.md`](./vault-portable-export.md) — lossless markdown export of a vault, with recipes for git-as-projection and disaster-recovery snapshots.
