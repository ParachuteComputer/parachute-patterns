# Governance: PR review, RC versioning, patterns alignment

> One short doc covering how Parachute repos ship code post-launch (v0.x,
> April 2026 onward). Four rules, one shared shape.

## Rule 1 — No auto-merge

**Every PR is reviewed by a team-lead role and merged by a human.** Tentacles
open PRs and report status; team-lead reviews and writes a verification
summary; the repo owner (currently Aaron) clicks merge.

- All Parachute repos with code or content (`parachute-hub`, `parachute-vault`,
  `parachute-notes`, `parachute-scribe`, `parachute-agent`,
  `parachute.computer`, `parachute-patterns`) have **branch protection on
  `main`**: no force-push, no branch deletion, PR-required for changes.
  `parachute-agent` joined this set on its committed-core promotion
  (2026-05-05) and is subject to the same review-discipline / RC-versioning /
  patterns-check rules as the original five.
- **Required-review count is calibrated to team size**:
  - **Solo human team (today):** required approvals = `0`. The single human
    *is* both reviewer and merger; a separate "approve" click before "merge"
    is ceremony without an additional safeguard. The discipline is on the
    automated actors (tentacles, team-lead) not to merge without a human.
  - **Multi-human team (later):** required approvals = `≥1`. Bump back up
    when a second human contributor with merge authority joins so PRs see a
    second pair of eyes before main.
- New Parachute repos turn on the same protection at the moment they hit
  RC / first publish, calibrated to whatever team-size rule is active. Before
  RC, direct push is fine while shape is fluid.
- Reverts and emergency hotfixes follow the same rule: branch, PR, review,
  human merge. Speed comes from a faster review cycle, not from skipping
  review.

## Rule 2 — RC versioning before `@latest`

While the ecosystem is pre-1.0, every published change goes to npm's `rc`
dist-tag first; promotion to `@latest` is a deliberate, separate step.

**Per PR:**

- The PR bumps `package.json` to `0.X.Y-rc.N` (next patch + a fresh rc
  number). Don't ship a "final" version straight from a feature PR.
- After the human merge, the publisher runs `npm publish --tag rc` so the
  build is reachable as `@openparachute/<pkg>@rc` (or
  `@openparachute/<pkg>@0.X.Y-rc.N` directly) but **not** the default
  `@latest` install for new users.

**Promotion (a separate, deliberate action):**

- Run `npm dist-tag add @openparachute/<pkg>@0.X.Y-rc.N latest` once the RC
  has been validated (smoke install, manual demo, real-world feedback).
- The same RC artifact becomes the `@latest`; no second build, no second
  version. This keeps git history and npm versions aligned and keeps the
  cadence fast.

**Doc-only / test-only PRs follow the same convention** for uniformity. Every
PR that changes the published artifact bumps the version. The cost is one
line in `package.json`; the benefit is no special-casing.

**At v1.0 and after**, switch to standard SemVer with `alpha` / `beta` / `rc`
prerelease tags as feature stability warrants, and to a "release PR" pattern
that promotes `0.X.Y-rc.N` → `0.X.Y` final via a small dedicated PR for a
cleaner public version history. This pattern doc gets a v1.0 update at that
time.

## Rule 3 — Patterns check in every review

Every PR review surfaces three questions (in the team-lead's report to the
repo owner):

1. **Which patterns from `parachute-patterns/` does this PR touch?**
   Explicit (the PR cites a doc) or implicit (the PR conforms to a pattern
   without naming it).
2. **Does it conform?** If not, why? (Sometimes the right call is the
   non-conforming change; the pattern is wrong or stale.)
3. **Does it establish a new pattern that should be documented, or change an
   existing pattern?** If yes, file or update the relevant pattern doc — as
   a follow-up PR in `parachute-patterns/` or, if small, bundled into the
   originating PR.

The patterns repo's steward (the `patterns` tentacle) is an active
participant in this loop — flagged when a new pattern is established,
involved in updates that affect cross-cutting conventions.

## Rule 4 — PR cadence: bundle by session/theme, not by issue

**The unit of review is the PR; the unit of change is the commit.** One
PR per coherent session of work; multiple commits inside it; reviewer
reads commit-by-commit.

**Bundle** when changes share a theme (e.g. "Capture flow polish"),
touch overlapping files, or naturally read as one shipping unit. The
default is to bundle.

**Split** only when:

- changes touch genuinely independent surfaces, or
- one needs urgent ship while a sibling is in design, or
- the bundle would push past ~800-1000 LOC and a reviewer would lose
  the thread.

Discipline inside a bundle:

- PR title names the bundle theme, not any one issue.
- PR body lists every issue closed (`Closes #123`, `Closes #124`).
- Each commit message stays tight — one logical change per commit, so
  the commit-by-commit read tracks the work narrative.
- Squash-merge on land (same as today). Squash-commit message
  summarizes the bundle; the commit-by-commit history is preserved on
  the PR for reviewers but collapses on `main`.

**Why this is its own rule.** Earlier shipping practice drifted toward
one-PR-per-issue because of a team-lead-private memory called
`feedback_serial_pr_flow` that says "one PR at a time — serialize,
don't batch." That memory is about *parallelism* (don't run N PRs
against the same shared file concurrently), not about *granularity*.
The two are independent axes:

- **Serialize, don't parallelize.** Finish a PR through merge before
  opening the next, especially when they touch overlapping surfaces.
  Still right.
- **Bundle, don't fragment.** Within one PR, pull in every coherent
  change from the session. Each repo-owner click costs the same
  whether the PR carries one fix or four; spreading four PRs out costs
  four clicks. The cadence catches up faster when bundled.

Most session-shaped work satisfies both: one bundle PR (granularity),
landed before the next session begins (serial).

## Why these rules

The first two months of post-launch shipping (April 2026 → ?) are the period
of most rapid change. In that window:

- Every direct-merge is a chance to ship something the team owner didn't
  expect.
- Every untagged `@latest` publish is a chance for new users to install a
  half-validated artifact.
- Every undocumented pattern becomes harder to retrofit later.
- Every fragmented PR set is a click-cost that scales with the wrong axis
  (issues touched), not the right one (sessions of work).

The cost of these rules is small (one extra click for merge, one extra
command for promotion, one extra paragraph in review, one extra
discipline on bundling). The benefit is durable alignment across modules
and humans.

## Open questions

- **Multi-human transition**: when a second human contributor joins, bump
  required approvals from `0` to `≥1` on each repo and add explicit
  `CODEOWNERS` files for path-scoped review. Out of scope today; not
  forgotten.
