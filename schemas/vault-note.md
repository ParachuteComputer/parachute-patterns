# Vault note conventions

Canonical vault description lives in the live vault itself — call
`vault-info` via the `parachute-vault` MCP for the full tag taxonomy and
any updates. This file captures the conventions that cross module
boundaries.

## metadata.summary — always

Every note should carry a 1–2 sentence `metadata.summary`.

```
metadata:
  summary: <one to two sentences>
```

**Why:** lightweight scanning. `query-notes` can return summaries without
content, which keeps context budgets cheap when something is walking many
notes. Without a summary, you pay full content cost to decide relevance.

## Tags define what a note IS

Tags describe identity. A note about a decision has tag `uni/decision`; an
agent-run log has `agent-run`; a handoff has `uni/handoff`. Tags are
hierarchical via `/` (e.g. `uni/decision`, `uni/handoff`, `uni/state`).

## Links define how notes CONNECT

Relationships (mentions, related-to, derived-from, etc.) go through
outgoing links. Wikilinks in content (`[[Projects/Parachute]]`) auto-resolve
and count as `mentions`.

## Wikilinks use full paths

Always: `[[Projects/Parachute Vault]]`. Never: `[[Parachute Vault]]`.

**Why:** path prefixes are namespaces — `People/`, `Projects/`,
`Uni/Decisions/` — and shortening loses the folder signal. Full paths
survive renames better (the vault's wikilink resolver keys on the path).

## Standard note types shared across the ecosystem

| Tag | Path convention | Written by | Purpose |
|---|---|---|---|
| `uni/decision` | `Uni/Decisions/<YYYY-MM-DD>-<slug>` | central source (Uni) | architectural/directional choice + rationale |
| `uni/handoff` | `Uni/Handoffs/<YYYY-MM-DD>-<slug>` | tentacles | what was done / learned / unresolved, at the end of a work block |
| `uni/state` | `Uni/State/<YYYY-MM-DD>-<slug>` | central source | "resume from here" snapshot before compaction or quiet period |
| `agent-definition` | (module-specific) | humans / agents | agent markdown consumed by `@openparachute/agent` |
| `agent-run` | (auto) | agent runner | opt-in mirror of high-signal run logs |
| `agent-skill` | (TBD) | humans | reusable composable prompt — future, when skills layer lands |
| `octopus-config` | `Uni/Octopus/config` | central source | opt-in team roster when `OCTOPUS_CONFIG_SOURCE=vault` |

## Dates

Convert relative dates to absolute when saving (user says "Thursday" →
store `2026-03-05`). Memories and notes decay fast otherwise.

## Rules

- `metadata.summary` is load-bearing — don't skip it.
- Use existing tags where possible. Introduce a new tag via
  `vault-info --description` and document it here if it's cross-module.
- Paths are stable identity. Renaming a note is expensive (wikilinks need
  rewriting). Pick the path once, carefully.
