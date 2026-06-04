#!/usr/bin/env bash
# rollout-cla.sh — open per-repo PRs adding the CLA caller workflow.
#
# For each target repo, creates a `cla-rollout` branch off the default
# branch, adds .github/workflows/cla.yml (the thin caller from
# patterns/cla.md), and opens a PR. Idempotent: skips repos that already
# have the workflow file or an open cla-rollout PR.
#
# Usage:
#   scripts/rollout-cla.sh repo1 [repo2 ...]   # specific repos
#   scripts/rollout-cla.sh --all               # every repo in the migration list
#
# Requires: gh (authenticated with workflow scope), jq.
# See migrations/2026-06-04-cla-rollout.md for the rollout checklist.

set -euo pipefail

ORG="ParachuteComputer"
BRANCH="cla-rollout"
WORKFLOW_PATH=".github/workflows/cla.yml"

# Tiers from migrations/2026-06-04-cla-rollout.md (cla-signatures excluded).
# Pilot on parachute-workspace FIRST (after CLA_PAT is set); use --all only
# once the flow is proven there.
ALL_REPOS=(
  # Tier 1 — committed core + core support
  parachute-vault parachute-surface parachute-scribe parachute-hub
  parachute-patterns parachute.computer
  # Tier 2 — shipped / active
  parachute-workspace parachute-runner parachute-brain parachute-pebble
  paraclaw .github
  # Tier 3 — explorations / archiving
  parachute-notes parachute-channel parachute-daily parachute-narrate
  parachute-octopus parachute-agents parachute-cloud openparachute-cli
  meshwork prism tailshare pcc
)

CALLER_CONTENT=$(cat <<'YAML'
name: CLA

on:
  issue_comment:
    types: [created]
  pull_request_target:
    types: [opened, closed, synchronize]

permissions:
  actions: write
  contents: read
  pull-requests: write
  statuses: write

jobs:
  cla:
    uses: ParachuteComputer/.github/.github/workflows/cla.yml@main
    secrets: inherit
YAML
)

PR_BODY=$(cat <<'BODY'
Adds the org-wide CLA check to this repo — a thin caller of the reusable
workflow in [`ParachuteComputer/.github`](https://github.com/ParachuteComputer/.github).

- Agreement: [CLA.md](https://github.com/ParachuteComputer/.github/blob/main/CLA.md)
- Policy + mechanics: [parachute-patterns/patterns/cla.md](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/cla.md)
- Rollout checklist: [migrations/2026-06-04-cla-rollout.md](https://github.com/ParachuteComputer/parachute-patterns/blob/main/migrations/2026-06-04-cla-rollout.md)

Contributors sign once (org-wide) by commenting on their PR; signatures
are recorded in `ParachuteComputer/cla-signatures`. The check is
advisory until the org-wide required-status-check decision.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)

if [[ "${1:-}" == "--all" ]]; then
  repos=("${ALL_REPOS[@]}")
elif [[ $# -ge 1 ]]; then
  repos=("$@")
else
  echo "usage: $0 --all | repo1 [repo2 ...]" >&2
  exit 1
fi

for repo in "${repos[@]}"; do
  full="$ORG/$repo"
  echo "── $full"

  # Skip if the workflow already exists on the default branch.
  if gh api "repos/$full/contents/$WORKFLOW_PATH" >/dev/null 2>&1; then
    echo "   skip: $WORKFLOW_PATH already present"
    continue
  fi

  # Skip if an open rollout PR already exists.
  open_pr=$(gh pr list -R "$full" --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [[ -n "$open_pr" ]]; then
    echo "   skip: open PR #$open_pr already exists"
    continue
  fi

  default_branch=$(gh api "repos/$full" --jq .default_branch)
  base_sha=$(gh api "repos/$full/git/ref/heads/$default_branch" --jq .object.sha)

  # Create (or reset) the rollout branch at the default-branch head.
  if gh api "repos/$full/git/ref/heads/$BRANCH" >/dev/null 2>&1; then
    gh api -X PATCH "repos/$full/git/refs/heads/$BRANCH" -f sha="$base_sha" -F force=true >/dev/null
  else
    gh api -X POST "repos/$full/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$base_sha" >/dev/null
  fi

  # Add the caller workflow on the branch.
  encoded=$(printf '%s\n' "$CALLER_CONTENT" | base64)
  gh api -X PUT "repos/$full/contents/$WORKFLOW_PATH" \
    -f message="ci: add org-wide CLA check (caller workflow)" \
    -f content="$encoded" \
    -f branch="$BRANCH" >/dev/null

  pr_url=$(gh pr create -R "$full" \
    --head "$BRANCH" --base "$default_branch" \
    --title "ci: add org-wide CLA check" \
    --body "$PR_BODY")
  echo "   opened: $pr_url"
done
