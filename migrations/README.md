# Migrations

A `migration` here means: an architectural shift that changes the canonical shape of the ecosystem (which modules are committed-core, where Notes lives, what the install command is, etc.).

Each architectural-decision PR ships with a corresponding `migrations/YYYY-MM-DD-<slug>.md` file that lists every code/doc location consumers need to update. Future propagation PRs check items off; the file gives a single place to look when you want to know "is this shift fully propagated?"

## When to write one

Make a migration doc when ANY of these are true:

- A committed-core module changes (added, removed, role shifts).
- The canonical install / setup path changes.
- A pattern's reference implementation changes module.
- A doc statement that's quoted elsewhere ("the four committed-core modules") changes.

Skip for: bug fixes, additive features, refactors that don't change canonical shapes.

## Format

Frontmatter: `title`, `date`, `status` (`active` / `complete` / `abandoned`), `originating-pr`.

Body: short context (why the shift), then sections:

- **Code references** — checklist of code locations to update.
- **Doc references** — checklist of doc locations to update.
- **Operator-facing references** — public surfaces (READMEs, install guides, blog).
- **External references** — anything offsite (npm package descriptions, GitHub repo descriptions).

Each item is a checkbox + `repo:path` + (when in flight) the PR number that addresses it.

## Maintenance

- **Active migration:** keep updating as items land.
- **Complete:** mark status `complete` + leave for historical reference.
- **Abandoned:** mark status `abandoned` + note why.

Don't delete migration files; they're the historical record.

## Why this discipline exists

The Notes-as-app shift (2026-05-21) caught us out: hub's setup wizard was still hardcoded to "install Notes" as the canonical first install, even though the architecture had shifted to "install App which auto-bootstraps notes-ui." An audit then found ~9 stale references scattered across patterns + site + workspace docs.

Root cause: no discipline linking an architectural-decision PR to all the consumer code/docs that need updating. A migration file in the originating PR would have made the propagation obvious — every downstream surface a check-mark away from "done."

## Example

See [`2026-05-21-notes-as-app.md`](./2026-05-21-notes-as-app.md) for the canonical reference (retroactive — written after the shift to seed the discipline).

## Related

- [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — grep-based audit script for known stale-reference patterns. Run it after architectural shifts (or before releases) to catch missed propagations.
- [`../patterns/governance.md`](../patterns/governance.md) — review discipline that surrounds these migrations.
- Workspace [`CLAUDE.md`](../../CLAUDE.md) — names this discipline as the expected workflow when shipping architectural shifts.
