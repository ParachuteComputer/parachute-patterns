# Modularity in practice

Three worked examples of sibling modules composing without coupling.

## Scribe → Vault (proper nouns)

**Standalone:** `parachute-scribe` takes audio or raw text and returns clean
text. Works fully offline of the vault.

**Opt-in composition:** when a vault is configured, Scribe pulls a
proper-noun list from notes tagged `scribe/proper-noun` and biases the
cleanup pass. Without a vault, the cleanup pass still runs — just without
the custom vocabulary.

**What makes this modular:** Scribe has a `ProperNounSource` interface with
implementations for `file`, `inline`, and `vault`. The vault impl is one of
three; none is privileged.

## Agents → Vault (agent definitions)

**Standalone:** `@openparachute/agent` loads agent markdown from a directory
(`loadAgentsFromDir`). Deploy-time bundled or filesystem-watched.

**Opt-in composition:** set `config.agents` to the result of
`loadAgentsFromVault({ vault, tag: "agent-definition" })` and the same runner
reads agents from vault notes instead. The parsed shape is identical — the
source just differs.

**What makes this modular:** the runner consumes a `Record<string, string>`
map of `path → markdown`. Where that map came from is the caller's problem.
See `patterns/loadAgents.md` for the shared source-tagged-union convention.

## Octopus → Vault (future: team roster)

**Standalone:** `octopus-ui` reads the live team from
`~/.claude/teams/octopus/config.json`. No network. No vault.

**Opt-in composition (planned):** with `OCTOPUS_CONFIG_SOURCE=vault`, the UI
server reads the roster from a vault note tagged `octopus-config`. Enables
driving octopus-ui from a tablet against a hosted vault.

**What makes this modular:** the config source is an env-selected strategy.
The default stays filesystem-local. Nothing in the UI assumes a vault exists.

## What these share

Each integration:

1. Has a **standalone default** that works without the sibling.
2. Exposes a **named strategy** (env var, config field, or plugin) that swaps
   in the composed implementation.
3. Uses a **stable data shape** at the boundary (a proper-noun list; an
   agent-markdown map; a team roster) so either side can evolve the
   internals without the other noticing.

When you propose a new cross-module integration, check against those three.
