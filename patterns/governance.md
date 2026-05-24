# Governance: PR review, RC versioning, patterns alignment

> One short doc covering how Parachute repos ship code post-launch (v0.x,
> April 2026 onward). Five rules, one shared shape.

## Rule 1 — No auto-merge

**Every PR is reviewed by a team-lead role and merged by a human.** Tentacles
open PRs and report status; team-lead reviews and writes a verification
summary; the repo owner (currently Aaron) clicks merge.

- All Parachute repos with code or content (`parachute-hub`, `parachute-vault`,
  `parachute-app`, `parachute-notes`, `parachute-runner`, `parachute-scribe`,
  `parachute-agent` (retired), `parachute.computer`, `parachute-patterns`)
  have **branch protection on `main`**: no force-push, no branch deletion,
  PR-required for changes. `parachute-agent` joined this set on its
  committed-core promotion (2026-05-05) and retains branch protection through
  retirement (2026-05-20) for historical preservation. `parachute-notes`
  stays protected through the Phase 2-3 deprecation arc; archive happens at
  Phase 4 (see notes#154). Same review-discipline / RC-versioning /
  patterns-check rules apply to every protected repo.
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

- The PR bumps `package.json` to `0.X.Y-rc.N` (next rc number; the patch
  number `Y` stays fixed across the rc chain until promotion). Don't
  ship a "final" version straight from a feature PR.
- After the human merge, push a matching git tag (`v0.X.Y-rc.N`). CI
  publishes — see [`release-ci.md`](release-ci.md) for the workflow shape.
  The tag is the canonical release marker; the publish is automated.

**Promotion (a separate, deliberate action):**

- Open a PR that drops the `-rc.N` suffix (e.g. `0.X.Y-rc.N` → `0.X.Y`).
- Reviewer + merge.
- Push the bare-version tag (`v0.X.Y`). CI publishes with `dist-tag=latest`
  AND tags the container image as `:stable`.
- Same source commit; no second build, no second version. Keeps git
  history, npm versions, and container image tags aligned.

**Doc-only PRs are EXEMPT from rc.N bumping** during an active rc chain —
they merge without a version change and get picked up by the next
code-touching PR's rc bump (or by the stable promotion, whichever lands
first). Don't fragment a release into many patch bumps mid-validation.

If a doc-only fix needs to ship outside an active rc chain (main is on a
stable version with no rc in flight), bump the next patch
(`0.X.Y` → `0.X.(Y+1)`), tag, ship.

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

## Rule 5 — CHANGELOG discipline: match the release log to the npm record

The CHANGELOG serves two readers: consumers want "what's in this
release" (canonical, aligned 1:1 with npm `@latest`); developers want
per-bump archaeology. Both deserve space.

The shape:

- **Stable section per published `@latest` version.** Headline
  narrative rolling up the rc chain. Migration risks + breaking
  changes in the TL;DR. This is what upgrade docs (e.g.
  `UPGRADING.md`) and external readers parse.
- **RC section per rc-bump-that-actually-publishes-to-`@rc`.** Per-PR
  development log. Stays as historical detail; not retroactively
  edited.

**An rc bump that doesn't `npm publish --tag rc` gets NO CHANGELOG
section.** This is the discipline gap that produced ~28 ghost-version
entries in the `vault@0.3.6-rc.X` chain (rc.1 then rc.30–rc.39 in
CHANGELOG; only `0.3.0-rc.1`, `0.3.0`, `0.3.1`, `0.3.3` on npm).
Don't write CHANGELOG entries for versions that don't exist in the
world.

At stable promotion: the rc-chain entries stay below the new stable
section. The stable section's narrative is the headline; the rc
entries are the citations.

**Why this is its own rule.** Rule 2 (RC versioning) covers the
publish discipline; this rule covers the CHANGELOG discipline that
has to ride alongside it. Skipping either produces drift: publish
without entry = silent; entry without publish = fiction.

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
- Every CHANGELOG entry for a version that never reached npm becomes
  a footgun for the consumer reader who's trying to decide what to
  install.

The cost of these rules is small (one extra click for merge, one extra
command for promotion, one extra paragraph in review, one extra
discipline on bundling, one extra check before writing a CHANGELOG
section). The benefit is durable alignment across modules and humans.

## Open questions

- **Multi-human transition**: when a second human contributor joins, bump
  required approvals from `0` to `≥1` on each repo and add explicit
  `CODEOWNERS` files for path-scoped review. Out of scope today; not
  forgotten.
