# Governance: PR review, RC versioning, patterns alignment

> One short doc covering how Parachute repos ship code post-launch (v0.x,
> April 2026 onward). Five rules, one shared shape.

## Rule 1 — No auto-merge

**Every PR is reviewed by a team-lead role and merged by a human.** Tentacles
open PRs and report status; team-lead reviews and writes a verification
summary; the repo owner (currently Aaron) clicks merge.

- All Parachute repos with code or content (`parachute-hub`, `parachute-vault`,
  `parachute-surface`, `parachute-notes`, `parachute-runner`, `parachute-scribe`,
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

**Re-affirmed 2026-06-13 after a drift.** Practice had slipped to
stable-direct across three trains (hub 0.7.0, hub 0.7.1, vault 0.6.x — no
rc was ever cut); the bun-linked local box + reviewer gating carried the
correctness weight, so it *felt* safe. It wasn't complete: it stranded an
rc-channel operator (`friends.parachute.computer` on `0.6.5-rc.8`) below
`@latest`, because `parachute upgrade` follows `@rc` and `@rc` never moved.
The rule stands as written: **every code-touching train publishes `-rc.1`
(→ `@rc`) first, soaks, then promotes the SAME `0.X.Y` bits to `@latest`.**
The next code-touching train across any module starts at `-rc.1`. The rc
channel is a real canary — that's the point of the second ceremony. (See
`Decisions/2026-06-13-rc-first-release-discipline` in the parachute-parachute
team vault; Aaron chose re-affirm over amend-to-stable.)

**Every code-touching PR bumps `rc.N` and publishes to `@rc`.**
Re-adopted 2026-06-23 (Aaron), reversing the 2026-05-24 "tag when ready,
not on every PR" rule. The earlier objection — rc bumps "living in commits
but never reaching npm" (hub#349-#358's rc.30/31/32) — is now moot: CI
publishes on tag push (Trusted Publishing, see [`release-ci.md`](release-ci.md)),
so a bump that pushes its tag *does* reach npm. With that, per-PR rc earns
its keep: the `@rc` channel tracks `main` continuously, so **every box can
soak every change** (`parachute upgrade` on the rc channel) instead of waiting
for an operator to decide to cut an rc. More frequent, lower-stakes testing
across the fleet is the whole point; the version-history churn is the
accepted cost. (Decision: `Decisions/2026-06-23-resume-per-pr-rc` in the
parachute-parachute team vault.)

**Per code-touching PR (typical case):**

- The PR bumps `package.json` to the next rc number (`0.X.Y-rc.(N+1)`).
  The patch number `Y` stays fixed across the rc chain until promotion;
  the rc counter increments each PR. Add the matching CHANGELOG rc section
  (Rule 5).
- Reviewer + human merge as usual.
- On merge, push the matching git tag (`v0.X.Y-rc.N`, or the monorepo
  per-package form like `notes-ui-v0.X.Y-rc.N`). CI publishes to `@rc`.
  The tag is the canonical release marker; the publish is automated. The
  tag points at the squashed merge commit on `main`, so it's pushed
  *after* merge, not before.

**Re-baselining a stale `@rc` (stable ran ahead during the gap).** During
the tag-when-ready interval the `@rc` dist-tag fell below `@latest` on
several packages. No mass republish is needed: each package's **next**
code-touching PR starts a fresh rc chain at `0.X.(Y+1)-rc.1` above its
current stable, which re-points `@rc` above `@latest` organically as PRs
land. hub#660's channel-resolution guarantee (below) prevents stranding in
the meantime.

**Promotion to stable:**

- Bump `package.json` to drop the `-rc.N` suffix (e.g. `0.X.Y-rc.N` →
  `0.X.Y`) — separate small PR, or direct on main per repo norms.
- Push the bare-version tag (`v0.X.Y`). CI publishes with
  `dist-tag=latest` AND (where applicable) tags the container image as
  `:stable`.

**The local bun-linked box is not a substitute for an rc soak.** It runs
`main` (ahead of any rc) and validates *code* — not the published-artifact
+ migration-at-real-install path the `@rc` canary exercises. This is
exactly why stable-direct felt safe but wasn't complete (2026-06-13 drift).

**Upgrade channel resolution — the guarantee that prevents stranding.**
`parachute upgrade` on the **rc channel** resolves to the highest version
*above installed* across BOTH `@rc` and `@latest` (the downgrade guard is
unchanged). So a canary mid-chain rides the newer rc; a canary with no
newer rc but a newer stable converges to stable, and picks up the next rc
when it ships. The operator stays on the rc *channel* without ever
stranding below `@latest`. This is the client-side, token-free fix
(parachute-hub `upgrade.ts`, closes hub#659). A server-side npm
`dist-tag` advance was considered and deferred — trusted-publishing is
token-free for `publish` only, and reintroducing an `NPM_TOKEN` just for
`dist-tag` isn't worth it when the client-side fix is complete.

**Doc-only PRs never bump version.** They merge straight to main and
will be included in whatever the next ship-driven version bump captures.

**The increment is the PATCH (`y`) by default — minor (`x`) bumps are
Aaron's explicit call, never inferred.** Settled 2026-06-09 after the
boundary-arc stable train shipped as minor bumps (hub 0.6→0.7, vault
0.5→0.6, …) on a judged-by-magnitude basis that wasn't Aaron's intent:
"let's make sure we move back to 0.x.y releases (on y dimension) going
forward since we're about to be doing a lot more changes. We've got a
long way to go yet until we're at 1.0." Pre-1.0, the version number is a
release counter, not a significance signal — significance lives in the
release notes. Don't read "big change" as "minor bump"; the next stable
after `0.X.Y` is `0.X.(Y+1)` unless Aaron says otherwise.

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
