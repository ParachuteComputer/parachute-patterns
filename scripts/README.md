# scripts/

Small operational scripts that help maintain the patterns + the ecosystem they describe. **No application code lives here** — this is a docs/conventions repo; scripts in this directory are tooling around the conventions, not implementations of them.

## Current scripts

- [`audit-canonical-refs.sh`](./audit-canonical-refs.sh) — grep-based audit for stale architectural references across the workspace. Run after architectural shifts (e.g. a new entry in [`../migrations/`](../migrations/)) or before releases to catch propagation misses.
- [`rollout-cla.sh`](./rollout-cla.sh) — opens per-repo PRs adding the CLA caller workflow (see [`../patterns/cla.md`](../patterns/cla.md) + [`../migrations/2026-06-04-cla-rollout.md`](../migrations/2026-06-04-cla-rollout.md)). Idempotent; `--all` or explicit repo args.

## Adding a script

A script earns its place here when:

- It supports a discipline already documented in `patterns/` or `guides/`.
- It runs locally, against checked-out repos, with no production access —
  **or** it's operational automation acting through the GitHub API on the
  org's own repos (like `rollout-cla.sh`); those must be idempotent and
  say what they touch in their header comment.
- It's a couple hundred lines or fewer. Larger tooling belongs in its own repo.

When adding one:

1. Drop it in this directory, executable bit set.
2. Add a usage block at the top of the script (comment block above `set -uo pipefail` or equivalent).
3. List it in the **Current scripts** section above with a one-line description.
4. If it's tightly tied to a specific migration, cross-link from the migration doc.

## Adding a new audit class to `audit-canonical-refs.sh`

Each architectural shift produces a new class of stale-reference pattern. When you spot one (during a migration, or via a bug report like hub#323 → hub#324, or via a bug-shape like the parachute-surface#13 / parachute-runner#4 duplicate-port-row regression), add a grep block to the script:

```bash
echo "--- '<pattern description>' ---"
echo "(<why this is now stale + which migration introduced the shift>)"
grep -rn --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E "<the grep regex>" \
    "$WORKSPACE" 2>/dev/null | grep -v "$EXCLUDES" | head -20
echo ""
```

Keep the script honest:

- One grep block per class of stale ref.
- Exclude `CHANGELOG`, `migrations/`, `_site`, `node_modules`, `.git/`, `DEPRECATED`, `BLOG-OUTLINE` by default (already in `$EXCLUDES`). Workspace-root draft docs (`BLOG-OUTLINE-*.md`, etc.) are expected noise — they legitimately quote stale framing as historical narration; add new filename fragments to `LINE_EXCLUDES` (in the script) the same way `BLOG-OUTLINE` was added if a future draft class leaks through.
- Cite the migration that introduced the shift in the block's intro echo.
- Cap each block at `head -20` so output stays readable.

Not every block has to fit the `--include='*.md'` shape. The `self-register row name` block, for example, walks a discovered list of `self-register.ts` files (under `parachute-*/src` and `parachute-*/packages/*/src`) and runs a focused regex per-file rather than a workspace-wide grep. Use whichever shape gives the cleanest signal:

- **Workspace-wide grep** when the stale ref is text that could appear anywhere (doc copy, comments, hardcoded ports).
- **Discover-then-check** when the bug shape is structural — a specific kind of file where a specific line shape is wrong (the convention violation in [`patterns/services-json-row-conventions.md`](../patterns/services-json-row-conventions.md), wrong import path, missing required field). Cite the pattern doc that establishes the convention.

The script is not exhaustive — it catches known stale patterns, not unknown ones. Real audits still rely on a human reading the changes against the migration doc. The script is the safety net for the patterns we've already seen drift.
