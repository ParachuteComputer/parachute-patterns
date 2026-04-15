# CLAUDE.md — parachute-patterns

This repo is **documentation**, not code. When you work here you are curating
conventions that every other Parachute repo points at.

## Rules

- **No code.** No `package.json`, no build step, no lint config beyond
  markdown. If you feel the urge to add tooling, stop and ask.
- **One pattern per file.** If a file starts growing two ideas, split it.
- **Short beats complete.** One screen per file. Link to upstream source
  rather than duplicating it. An out-of-date duplicate is worse than a link.
- **Document what's real.** Don't invent conventions we haven't established.
  For anything uncertain, mark `[DRAFT]` at the top and note the open
  question. Remove the marker once the first two modules conform.
- **When a pattern changes**, update the file *and* file an issue against any
  Parachute repo that needs to follow, *and* add an entry to
  `adoption/migration-notes.md` with the date, the change, and the affected
  repos.

## Shape of a good pattern file

1. One-line summary at the top.
2. The convention itself (TL;DR).
3. Why — the constraint or lesson that produced it.
4. Examples — link to specific files in upstream repos.
5. Open questions / drafts at the bottom if any.

## Scope

- **In scope:** naming, modularity principle, brand tokens, shared schemas,
  cross-cutting patterns (auth, transport, report contract, loader shapes),
  adoption guidance.
- **Out of scope:** per-module architecture, runtime code, anything that
  belongs inside a single repo's own docs.

## Working conventions

- Feature branches. PR to `main`. No direct commits to `main`.
- Every PR that changes an established pattern should reference the sibling
  repo(s) that will need to follow.
