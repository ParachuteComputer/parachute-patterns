# Governance: PR review, RC versioning, patterns alignment

> One short doc covering how Parachute repos ship code post-launch (v0.x,
> April 2026 onward). Three rules, one shared shape.

## Rule 1 — No auto-merge

**Every PR is reviewed by a team-lead role and merged by a human.** Tentacles
open PRs and report status; team-lead reviews and writes a verification
summary; the repo owner (currently Aaron) clicks merge.

- All Parachute repos with code or content (`parachute-cli`, `parachute-vault`,
  `parachute-notes`, `parachute-scribe`, `parachute.computer`,
  `parachute-patterns`) have **branch protection on `main`**: at least 1
  approving review required, no force-push, no branch deletion.
- New Parachute repos turn on the same protection at the moment they hit
  RC / first publish. Before that, direct push is fine while shape is fluid.
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

## Why these rules

The first two months of post-launch shipping (April 2026 → ?) are the period
of most rapid change. In that window:

- Every direct-merge is a chance to ship something the team owner didn't
  expect.
- Every untagged `@latest` publish is a chance for new users to install a
  half-validated artifact.
- Every undocumented pattern becomes harder to retrofit later.

The cost of these rules is small (one extra click for merge, one extra
command for promotion, one extra paragraph in review). The benefit is
durable alignment across modules and humans.

## Open questions

- **Self-approval**: GitHub allows a repo admin to approve their own PR in
  some configurations. We're not currently using `enforce_admins`, so
  admins can technically merge without a separate approval. This is
  intentional for emergency overrides; track abuse.
- **Multi-tentacle approval workflow**: when the codebase has >1 active
  human contributor, we add explicit `CODEOWNERS` and require code-owner
  reviews. Out of scope today.
