# Frontmatter lint rules

## [DRAFT]

Shared linting for markdown files with YAML frontmatter. Applies to agent
markdown (`@openparachute/agent`), memory files (`~/.claude/projects/.../memory/*.md`),
and any future markdown-with-frontmatter surface.

## Rules (apply to any frontmatter we author)

1. **Opening `---` and closing `---` on their own lines.** No content on the
   same line as the fence.
2. **2-space indent, no tabs.** YAML parsers differ on tabs; avoid the class
   entirely.
3. **Strings containing `:` must be quoted.** Example:
   `description: "Runs at 9:00 daily"`.
4. **Dates are ISO-8601** (`2026-04-15` or `2026-04-15T12:00:00Z`).
5. **Arrays prefer block form** when more than 2 items; inline `[a, b]` is
   fine for short lists.
6. **Unknown top-level keys are warnings, not errors.** The canonical schemas
   (agent markdown, memory entries) should grow deliberately; a warning
   flags drift without blocking.

## Schemas that live elsewhere

- Agent markdown: `schemas/agent-markdown.md` → Zod in
  [parachute-agents/src/agents.ts](https://github.com/ParachuteComputer/parachute-agents/blob/main/src/agents.ts).
- Memory files (user / feedback / project / reference): Uni's auto-memory
  convention in the UnforcedAGI global CLAUDE.md.

## Open questions

- No shared lint tool has been built. `gray-matter` + a schema is the
  obvious path. If/when we ship one, it lives in `@openparachute/cli` as
  `parachute lint` and points at the schemas above.
- Should memory files have a shared Zod schema too, matching the
  `name/description/type/...` frontmatter Uni writes? Probably yes — file
  an issue when someone hits an inconsistency.
