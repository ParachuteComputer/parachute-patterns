# scripts/

Small operational scripts that help maintain the patterns + the ecosystem they describe. **No application code lives here** — this is a docs/conventions repo; scripts in this directory are tooling around the conventions, not implementations of them.

## Current scripts

- [`audit-canonical-refs.sh`](./audit-canonical-refs.sh) — grep-based audit for stale architectural references across the workspace. Run after architectural shifts (e.g. a new entry in [`../migrations/`](../migrations/)) or before releases to catch propagation misses.

## Adding a script

A script earns its place here when:

- It supports a discipline already documented in `patterns/` or `guides/`.
- It runs locally, against checked-out repos, with no production access.
- It's a couple hundred lines or fewer. Larger tooling belongs in its own repo.

When adding one:

1. Drop it in this directory, executable bit set.
2. Add a usage block at the top of the script (comment block above `set -uo pipefail` or equivalent).
3. List it in the **Current scripts** section above with a one-line description.
4. If it's tightly tied to a specific migration, cross-link from the migration doc.

## Adding a new audit class to `audit-canonical-refs.sh`

Each architectural shift produces a new class of stale-reference pattern. When you spot one (during a migration, or via a bug report like hub#323 → hub#324), add a grep block to the script:

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
- Exclude `CHANGELOG`, `migrations/`, `_site`, `node_modules`, `.git/`, `DEPRECATED` by default (already in `$EXCLUDES`).
- Cite the migration that introduced the shift in the block's intro echo.
- Cap each block at `head -20` so output stays readable.

The script is not exhaustive — it catches known stale patterns, not unknown ones. Real audits still rely on a human reading the changes against the migration doc. The script is the safety net for the patterns we've already seen drift.
