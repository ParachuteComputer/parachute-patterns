# Modularity is the product

## Convention

**Every Parachute module stands alone. Composition is opt-in. No hidden
coupling.**

Concretely: a module must be useful installed by itself, with no other
Parachute module present. If it *can* compose with a sibling, that
composition is a config flag or plugin — never a build-time dependency,
never a runtime requirement.

## Why

- Adoption path: a user or developer picks up one piece (say, the vault) and
  gets real value without signing up for a platform.
- Each module stays small and focused. The pressure to grow features lives
  inside that module, not in a shared core.
- The failure mode we're avoiding is "Parachute Suite" — a coupled monorepo
  where every module imports the others, nothing can be adopted in isolation,
  and a breaking change anywhere propagates everywhere. (See Emacs:
  indispensable for some, unadoptable for most.)
- The magic is cumulative: each added module makes the others more powerful
  without any of them *requiring* the others.

## Rules

- **No `@openparachute/*` package may import from another at build time
  unless it's genuinely a library layer** (e.g. a future `@openparachute/core`
  providing vault types). Runtime integrations go through configured clients
  or MCP.
- **Every integration is a flag.** `config.agentSource = "dir" | "vault"`.
  `config.backend = "vercel-ai" | "claude"`. `config.vault = { url, token }`
  (absent → no vault features). Defaults must exercise the standalone path.
- **Graceful absence.** When an optional integration is missing, the module
  falls back to its standalone behavior and logs (not errors). Example:
  `loadAgentsFromVault` returns `{}` with a warning when the vault is
  unreachable so the runner still boots (see
  [parachute-agents/src/agent-sources.ts](https://github.com/ParachuteComputer/parachute-agents/blob/main/src/agent-sources.ts)).
- **Document the opt-in.** Each composable integration gets an entry in the
  module's README *and* a `patterns/` entry here if the shape is reusable
  across modules.

## What this looks like in practice

See `modularity/examples.md` for Scribe + vault, Agents + vault, Octopus +
vault composed without coupling.

## Open questions

- A shared `@openparachute/vault-client` package would reduce duplication
  across Agents, Daily, Prism. It would be a library (importable), not a
  runtime dependency, so it doesn't violate the principle — but the
  threshold for "this is worth extracting" isn't codified yet. Tracked in
  parachute-vault issue #102.
