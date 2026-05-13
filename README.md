# parachute-patterns

Shared conventions across the Parachute ecosystem — the single source of truth
for how Parachute modules align with their siblings.

Parachute is intentionally a set of small pieces, loosely joined: Vault, Daily,
Scribe, Narrate, Channel, Agents, Cloud, Octopus, the `parachute` CLI. Every
module stands alone; composition is opt-in. That modularity only holds together
if the surfaces they share — naming, brand, schemas, auth, reporting shapes —
stay coherent. This repo is where those surfaces are written down.

## Who this is for

- **Humans** starting a new Parachute module, or adopting a pattern into an
  existing one.
- **Tentacles** (Uni facets, see [UnforcedAGI](https://github.com/ParachuteComputer/UnforcedAGI))
  working inside a Parachute repo.
- **Future Parachute modules** — when we invent the fifth, sixth, tenth thing,
  it should feel like a Parachute thing.

## For tentacles working in a Parachute repo

Before you ship code that crosses a naming, brand, schema, or pattern
boundary, check the relevant file here. If the convention is wrong, propose a
change in this repo first. Every Parachute module should be able to point at a
single source of truth for how it aligns with its siblings.

## Layout

```
naming/       package names, bin names, repo names
modularity/   the standalone-first principle, with worked examples
brand/        palette, typography, motifs, canonical tokens.css
schemas/      agent markdown, vault note metadata, lint rules
patterns/     loadX sources, report contract, token auth, MCP transport, dev-auto-user
guides/       long-form how-to references that explain how patterns combine
cookbook/     short recipes — one outcome, one page, links out for depth
research/     in-flight design notes for not-yet-committed direction
adoption/     checklist for new modules, migration notes log
```

Each file is short on purpose — one screen, one pattern. When examples are
needed, link to the upstream repo rather than duplicating code here.

## Contributing

- Open a PR with the change. If the pattern is new (not documented before),
  include a one-paragraph rationale. If the pattern is changing, log the
  change in `adoption/migration-notes.md` with the date and the repos that
  need to follow.
- `[DRAFT]` means the pattern is proposed but not yet adopted across the
  ecosystem. Remove the marker once the first two modules conform.
- Keep tone warm, precise, not precious.

## Where this sits in the stack

parachute-patterns is documentation only — no code, no build, no runtime
dependency. Every other Parachute repo may reference it, but none import from
it. The repo is the contract, not the implementation.

License: AGPL-3.0 (matching the family).
