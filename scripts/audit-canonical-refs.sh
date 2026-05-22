#!/usr/bin/env bash
# Audit canonical-architecture references across the workspace.
#
# Run after architectural shifts, before releases, or whenever you suspect
# stale refs. Output is grep results grouped by class of stale pattern —
# review by hand, cross-check against the relevant migrations/*.md.
#
# Usage:
#   ./scripts/audit-canonical-refs.sh [/path/to/workspace]
#
# Default workspace path: ~/ParachuteComputer
#
# Adding new patterns: drop a new "echo" + "grep" block below. The
# discipline is "one class of stale ref per block" — each block names
# what it's looking for + cites which migration introduced the shift.

set -euo pipefail

WORKSPACE="${1:-$HOME/ParachuteComputer}"

if [[ ! -d "$WORKSPACE" ]]; then
  echo "error: workspace dir not found: $WORKSPACE" >&2
  exit 1
fi

# Shared grep args:
#   --exclude-dir prunes vendor/build/git dirs from descent (the slow part).
#   The migrations/ dir is excluded because it deliberately quotes stale patterns
#   for historical reference.
GREP_DIR_EXCLUDES=(
  --exclude-dir=node_modules
  --exclude-dir=_site
  --exclude-dir=.git
  --exclude-dir=dist
  --exclude-dir=build
  --exclude-dir=.next
  --exclude-dir=migrations
)

# After grep finishes, line-level excludes for files we can't prune via
# --exclude-dir (CHANGELOGs and DEPRECATED.md files are inside live repos;
# BLOG-OUTLINE-*.md are workspace-root drafts that legitimately quote
# stale framing as historical narration).
LINE_EXCLUDES='CHANGELOG\|DEPRECATED\|BLOG-OUTLINE'

echo "=== Auditing canonical-architecture references in $WORKSPACE ==="
echo ""

echo "--- 'install Notes' / 'parachute install notes' ---"
echo "(should be 'install App' per Notes-as-app migration 2026-05-21)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E "parachute install notes|install Notes|Install Notes" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | head -20; } || true
echo ""

echo "--- 'four committed-core' / 'five committed-core' ---"
echo "(post-Notes-as-app: four — vault/app/scribe/hub. Anything saying 'five' is stale)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.njk' \
    -E "four committed.core|five committed.core" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | head -20; } || true
echo ""

echo "--- 'Notes — frontend PWA' / 'Notes PWA backed by' (legacy framing) ---"
echo "(Notes is hosted by parachute-app now; 'Notes — frontend PWA' wording is stale)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E "Notes — frontend PWA|Notes PWA backed by" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | head -20; } || true
echo ""

echo "--- hardcoded port 1942 outside parachute-notes ---"
echo "(1942 is the deprecating notes-daemon port; new operator-facing copy should point at /app/notes via hub)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E ":1942|port: 1942|port=1942" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | grep -v "parachute-notes\|canonical-ports\|service-spec" | head -20; } || true
echo ""

echo "--- 'parachute-agent' (retired 2026-05-20) outside retirement/historical docs ---"
echo "(operator-facing docs should reference parachute-runner; agent retired)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E "parachute-agent|parachute_agent" \
    "$WORKSPACE" 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | grep -v "parachute-agent/\|trust-gradient\|retired\|governance\|FALLBACK\|service-spec\|loadAgents\|RELEASE-NOTES\|WAKE-UP\|BETA-EMAIL\|launch-day" \
    | head -20; } || true
echo ""

echo "=== Done. Review findings; cross-check against migrations/*.md. ==="
echo ""
echo "Notes:"
echo "  - Vendor/build dirs (node_modules, _site, dist, build, .next, .git, migrations) are pruned via --exclude-dir."
echo "  - CHANGELOGs + DEPRECATED.md are excluded line-level (they're historical record)."
echo "  - parachute-notes/canonical-ports.md/service-spec.ts are excluded from the port-1942 check (they're the canonical source)."
echo "  - parachute-agent retirement docs + launch-day artifacts are excluded from the agent check."
echo "  - Add new grep blocks above when you hit a new class of stale ref."
