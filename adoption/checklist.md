# Adoption checklist — new Parachute module

When you create a new module in the Parachute family, run through this
list. Every item points at the canonical pattern file.

## Naming

- [ ] Repo lives under `ParachuteComputer/parachute-<module>` (`naming/repos.md`).
- [ ] npm package is `@openparachute/<module>` (`naming/packages.md`).
- [ ] Primary bin is `parachute-<module>` (`naming/bins.md`).
- [ ] Extra bins, if any, are `parachute-<module>-<role>`.
- [ ] `package.json` `bin` field declared up front, even if unpublished.

## License + meta

- [ ] AGPL-3.0 LICENSE in repo root.
- [ ] README links back to `parachute-patterns` at the top:
  > Parachute conventions live in [parachute-patterns](https://github.com/ParachuteComputer/parachute-patterns).
- [ ] `CLAUDE.md` if the repo will be worked on by tentacles — point at
  upstream conventions, keep repo-specific rules short.

## Modularity

- [ ] The module works standalone — no sibling Parachute module is *required*
  to boot.
- [ ] Each opt-in integration with a sibling is a config flag or plugin,
  not a build-time import (`modularity/principle.md`).
- [ ] Missing optional integrations degrade gracefully (log, don't crash).

## Brand (if the module has UI)

- [ ] Uses the Parachute palette — either import `brand/tokens.css` (web) or
  port from Daily's `design_tokens.dart` (mobile/desktop).
- [ ] Soft radii, warm shadows, settling motion (`brand/motifs.md`).
- [ ] Uses the Parachute font families where customizable.

## Schemas

- [ ] If the module authors agent markdown, it parses against the canonical
  schema (`schemas/agent-markdown.md`).
- [ ] Notes written to the vault carry `metadata.summary` and use full-path
  wikilinks (`schemas/vault-note.md`).

## Patterns (apply if relevant)

- [ ] Lists loaded from multiple sources use the `loadX` tagged-union shape
  (`patterns/loadAgents.md`).
- [ ] Reports/handoffs back to a parent agent follow the report contract
  (`patterns/report-contract.md`).
- [ ] Issued tokens use the `pvt_` prefix, sha256 storage, scope, cookie
  reveal (`patterns/token-auth.md`).
- [ ] MCP transport is Streamable HTTP at `/mcp`, bearer or OAuth client
  credentials (`patterns/mcp-transport.md`).
- [ ] Dev-mode auth shortcut (if any) gated on `PARACHUTE_DEV_AUTO_USER`
  (`patterns/dev-auto-user.md`).

## After

- [ ] If your module introduces a pattern the ecosystem should follow, PR it
  into this repo **before** rolling it out to siblings.
- [ ] Log any deviation from a canonical pattern in
  `adoption/migration-notes.md` with the reason.
