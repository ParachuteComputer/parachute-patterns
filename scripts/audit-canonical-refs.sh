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
  --exclude-dir=.claude
)

# After grep finishes, line-level excludes for files we can't prune via
# --exclude-dir (CHANGELOGs and DEPRECATED.md files are inside live repos;
# BLOG-OUTLINE-*.md are workspace-root drafts that legitimately quote
# stale framing as historical narration).
LINE_EXCLUDES='CHANGELOG\|DEPRECATED\|BLOG-OUTLINE'

# Historical-doc excludes for rename/retirement sweeps: dated design docs
# (design/YYYY-MM-DD-*.md, workspace-root DESIGN-YYYY-*) and the
# adoption/migration-notes.md running log deliberately quote the names that
# were current when they were written. migrations/ is already dir-excluded
# above for the same reason. Scope these narrowly — live pattern docs and
# code do NOT get this pass.
HISTORICAL_DOC_EXCLUDES='design/20[0-9][0-9]-\|DESIGN-20[0-9][0-9]-\|migration-notes'

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
echo "(post-Notes-as-app: four — vault/surface/scribe/hub. Anything saying 'five' is stale)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.njk' \
    -E "four committed.core|five committed.core" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | head -20; } || true
echo ""

echo "--- 'Notes — frontend PWA' / 'Notes PWA backed by' (legacy framing) ---"
echo "(Notes is hosted by parachute-surface now; 'Notes — frontend PWA' wording is stale)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E "Notes — frontend PWA|Notes PWA backed by" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | head -20; } || true
echo ""

echo "--- hardcoded port 1942 outside parachute-notes ---"
echo "(1942 is the deprecating notes-daemon port; new operator-facing copy should point at /surface/notes via hub)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E ":1942|port: 1942|port=1942" \
    "$WORKSPACE" 2>/dev/null | grep -v "$LINE_EXCLUDES" | grep -v "parachute-notes\|canonical-ports\|service-spec" | head -20; } || true
echo ""

# NOTE (2026-07-01): `parachute-agent` is the LIVE module — the renamed
# parachute-channel (migrations/2026-06-17-channel-to-agent.md). The
# *retired* Claude-in-containers agent (2026-05-20) is the separate
# `paraclaw` repo; don't conflate the two. The old block here treated
# `parachute-agent` as the retired name and its exclusions hid the live
# module's drift — replaced by the channel-staleness sweep below.

echo "--- stale 'channel' module references (channel→agent rename, 2026-06-17) ---"
echo "(the live module is parachute-agent — ex parachute-channel. Stale: parachute-channel, @openparachute/channel, channel:send, #channel-message, /admin/channel-token, PARACHUTE_CHANNEL_*. Historical docs excluded; lines narrating the rename / back-compat aliases excluded.)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --exclude-dir=research \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' --include='*.sh' --include='*.json' \
    -E "parachute-channel|@openparachute/channel|channel:send|#channel-message|/admin/channel-token|PARACHUTE_CHANNEL_" \
    "$WORKSPACE" 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | grep -v "$HISTORICAL_DOC_EXCLUDES" \
    | grep -v "audit-canonical-refs" \
    | grep -vi "renam\|legacy\|alias\|redirect\|compat\|deprecat\|dual-read\|dual-accept" \
    | head -30; } || true
echo ""

echo "--- 'parachute-runner' promoted/live framing (runner retired 2026-07-01) ---"
echo "(runner is fully retired — superseded by parachute-agent scheduled jobs (#agent/job); see parachute-runner/DEPRECATED.md + migrations/2026-07-01-runner-retirement.md. The runner repo itself is historical record; lines narrating the retirement are excluded.)"
{ grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --exclude-dir=parachute-runner \
    --exclude-dir=research \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.njk' \
    -E "parachute-runner|@openparachute/runner" \
    "$WORKSPACE" 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | grep -v "$HISTORICAL_DOC_EXCLUDES" \
    | grep -v "audit-canonical-refs" \
    | grep -vi "retire\|deprecat\|supersed\|legacy\|not for new" \
    | head -30; } || true
echo ""

echo "--- self-register row name written as literal short name ---"
echo "(should be \`name: manifest.manifestName\` or \`name: ROW_NAME\` per services-json-row-conventions; literal short names create duplicate-port rows)"
{
  # Discover self-register.ts under any first-party package layout (src/ or
  # packages/*/src/). Sort + uniq so the broad glob doesn't re-list the
  # explicit set above. Quiet `find` so missing dirs don't noise the output.
  find "$WORKSPACE"/parachute-*/src \
       "$WORKSPACE"/parachute-*/packages/*/src \
       -maxdepth 1 -name self-register.ts -type f 2>/dev/null \
    | sort -u
} | while read -r f; do
  hits=$(grep -nE "^\s+name:\s*\"[a-z][a-z-]+\"" "$f" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    echo "  ^ $f writes a literal short name as services.json row identity — should be manifestName"
  fi
done
echo ""

# --- Workstream I: non-canonical verb vocabulary -----------------------
# design-system.md §5 settled the operator-facing verbs for the OAuth
# approval flow + module-management. Surfaces using retired alternatives
# (Authorize / Allow / Grant / Approve-and-continue) drift the visual
# vocabulary and confuse operators flowing through the OAuth + module-
# management surfaces.
#
# Scoping decisions (per patterns#99 reviewer):
#   - `Connect` is NOT included in the verb-drift set. The audit caught
#     legitimate "Connect" usage in install.njk + the VaultPopover button
#     label — those describe vault-connection actions, not OAuth flow
#     verbs. design-system.md §5 doesn't claim authority over every
#     "connect" word in the product.
#   - parachute-notes (archiving) excluded so archived-repo hits don't
#     permanently noise the audit. parachute-agent is NO LONGER excluded
#     (2026-07-01): it's the live ex-channel module, and excluding it hid
#     live drift.
#   - Test files (`*.test.ts*`) excluded — assertions like
#     `expect(html).toContain("Authorize")` are pinning surface copy,
#     not driving drift. Cleanup of the surface flips the test
#     simultaneously.
#   - The match anchors are `>...<` (JSX/HTML text node), `aria-label=`,
#     and JSX `title=`/page-title constructions. Bare-quoted strings
#     are NOT matched — too many false positives from variable
#     assignments and intermediate constants. Result: catches user-
#     facing copy, misses internal symbol noise.

echo "--- Non-canonical OAuth verbs (Authorize / Allow / Grant / Approve-and-continue) ---"
echo "(design-system.md §5 — canonical: Sign in / Sign out / Approve / Deny / Continue)"
{
  grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --exclude-dir=patterns \
    --exclude-dir=parachute-notes \
    --include='*.tsx' --include='*.ts' --include='*.njk' --include='*.html' \
    --exclude='*.test.ts*' \
    -E ">[[:space:]]*(Authorize|Allow|Grant|Approve and continue)[[:space:]]*<|aria-label=\"(Authorize|Allow|Grant|Approve and continue)\"|title=\"(Authorize|Allow|Grant|Approve and continue)" \
    "$WORKSPACE" 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | head -30
} || true
echo ""

echo "--- Non-canonical module-action verbs (Remove instead of Uninstall) ---"
echo "(design-system.md §5 + Workstream B app#35 — module-row destructive action is 'Uninstall')"
{
  grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --exclude-dir=patterns \
    --include='*.tsx' --include='*.ts' --include='*.njk' \
    --exclude='*.test.ts*' \
    -E ">[[:space:]]*Remove[[:space:]]*<|aria-label=\"Remove\"" \
    "$WORKSPACE"/parachute-surface "$WORKSPACE"/parachute-hub 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | head -20
} || true
echo ""

echo "--- Legacy state vocabulary in user-facing copy (Pending-OAuth / Disabled) ---"
echo "(design-system.md §6 + Workstream F — canonical: active / pending / inactive / failing.)"
echo "(CSS class aliases .status-disabled / .status-pending-oauth retained for one rc-chain; the block excludes those + scopes to capitalized user-facing labels in HTML/JSX text nodes. Lowercase status-enum string literals (status === \"disabled\") are intentionally NOT matched — those are wire-shape values, separate from the user-facing label vocabulary.)"
{
  grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --exclude-dir=patterns \
    --exclude-dir=parachute-notes \
    --include='*.tsx' --include='*.ts' --include='*.njk' --include='*.html' \
    --exclude='*.test.ts*' \
    -E ">Pending-OAuth<|>Disabled<" \
    "$WORKSPACE"/parachute-hub "$WORKSPACE"/parachute-surface "$WORKSPACE"/parachute-vault "$WORKSPACE"/parachute-scribe "$WORKSPACE"/parachute-agent 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | head -20
} || true
echo ""

echo "--- Stale pvt_* token guidance / 'vault tokens create' (pvt_* DROP — vault#282 Stage 2) ---"
echo "(vault no longer mints pvt_* opaque tokens — access tokens are hub-issued JWTs. Operator-facing copy + CLI guidance should point at the hub mint-token flow / mcp-install, never 'parachute vault tokens create'. Lines describing the removal itself are excluded; UPGRADING.md is the recovery-path doc and is excluded; patterns/research/scratch are excluded as non-canonical narration.)"
{
  grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --exclude-dir=patterns \
    --exclude-dir=research \
    --exclude-dir=scratch \
    --exclude-dir=parachute-notes \
    --include='*.tsx' --include='*.ts' --include='*.njk' --include='*.html' --include='*.md' \
    --exclude='*.test.ts*' \
    --exclude='UPGRADING.md' \
    -E "vault tokens create|Bearer pvt_|creates? a pvt_|=pvt_" \
    "$WORKSPACE" 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | grep -vi "removed\|no longer\|deprecat\|exits 1\|vestigial\|drop\|legacy" \
    | head -20
} || true
echo ""

echo "--- Legacy UI-URL semantics: mount-joined \"/admin/\" manifests + hub /admin/vaults route (B4 — hub-module-boundary 2026-06-09) ---"
echo "(uiUrl/managementUrl/configUiUrl resolve by form: leading-/ is origin-absolute VERBATIM; vault's per-instance form is \"admin/\"; the provisioning UX lives at /vault/admin/. A manifest still declaring the legacy \"/admin/\" literal, or copy pointing at the hub's /admin/vaults page, is stale once Phase B lands. Lines narrating the shim/retirement + the migration-notes running log are excluded.)"
{
  grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.md' --include='*.ts' --include='*.tsx' --include='*.json' --include='*.njk' \
    -E "\"?(uiUrl|managementUrl|configUiUrl)\"?[[:space:]]*:[[:space:]]*\"/admin/?\"|/admin/vaults" \
    "$WORKSPACE" 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | grep -v "migration-notes" \
    | grep -vi "legacy\|compat\|deprecat\|retire\|shim\|pre-B4\|hub-module-boundary" \
    | head -30
} || true
echo ""

# --- Missing-dependency UX: hand-synced install strings outside depcheck ----
# patterns/missing-dependency-ux.md (task #188, migration 2026-05-29) makes
# `@openparachute/depcheck` the single owner of dependency install strings +
# the message formatter. A module carrying its own `brew install` /
# `apt-get install` / `dnf install` recipe, or a raw `Executable not found`
# literal, in `src/` is drift back to hand-synced strings — the exact thing
# the shared lib exists to prevent.
#
# Advisory, not a hard fail (like the rest of the script). Expected legitimate
# hits during the adoption arc: depcheck's own registry (packages/depcheck),
# vault's git-preflight.ts (being folded into depcheck), hub's
# cloudflaredInstallHint (the static-binary precedent) — these ARE the
# canonical sources and are excluded. Anything else is a candidate to route
# through depcheck.

echo "--- Hand-synced install strings / raw 'Executable not found' outside @openparachute/depcheck ---"
echo "(missing-dependency-ux.md — depcheck owns install recipes + the ENOENT message; modules wire spawn sites, they don't carry strings)"
{
  grep -rn "${GREP_DIR_EXCLUDES[@]}" \
    --include='*.ts' --include='*.tsx' \
    --exclude='*.test.ts*' \
    --exclude-dir=depcheck \
    -E "brew install|apt-get install|dnf install|Executable not found in \\\$PATH|not found on PATH" \
    "$WORKSPACE"/parachute-hub "$WORKSPACE"/parachute-vault \
    "$WORKSPACE"/parachute-scribe "$WORKSPACE"/parachute-runner 2>/dev/null \
    | grep -v "$LINE_EXCLUDES" \
    | grep -v "git-preflight\|cloudflaredInstallHint\|cloudflare/detect" \
    | head -30
} || true
echo ""

echo "=== Done. Review findings; cross-check against migrations/*.md. ==="
echo ""
echo "Notes:"
echo "  - Vendor/build dirs (node_modules, _site, dist, build, .next, .git, migrations) are pruned via --exclude-dir."
echo "  - CHANGELOGs + DEPRECATED.md are excluded line-level (they're historical record)."
echo "  - parachute-notes/canonical-ports.md/service-spec.ts are excluded from the port-1942 check (they're the canonical source)."
echo "  - parachute-agent is the LIVE module (ex parachute-channel, renamed 2026-06-17); the retired containers agent is the paraclaw repo."
echo "  - Dated design docs (design/YYYY-MM-DD-*) + adoption/migration-notes.md are excluded from the rename/retirement sweeps (historical record); migrations/ is dir-excluded."
echo "  - parachute-runner hits: runner retired 2026-07-01 — see migrations/2026-07-01-runner-retirement.md for the propagation checklist."
echo "  - channel-block hits inside hub's one-cycle back-compat shims (301 redirect route, LEGACY_MANIFEST_ALIASES map, install alias) are EXPECTED until the contract PR drops them."
echo "  - depcheck's own registry + vault git-preflight.ts + hub cloudflaredInstallHint are excluded from the install-string check (canonical sources)."
echo "  - /admin/vaults hits in hub code are EXPECTED until the hub-module-boundary Phase B5 SPA slim lands — that sweep tracks the propagation."
echo "  - Add new grep blocks above when you hit a new class of stale ref."
