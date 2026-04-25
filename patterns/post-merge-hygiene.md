# Post-merge hygiene

## Convention

Immediately after a PR merges, the steward (tentacle or human) returns the
local checkout to `main`:

```
git checkout main && git pull
```

This is one of the few non-negotiable per-repo rituals. Every Parachute
repo's `CLAUDE.md` documents it; the umbrella
[`ParachuteComputer/CLAUDE.md`](https://github.com/ParachuteComputer/parachute.computer)
calls it out as "important."

## Why

Parachute is developed against `bun link`-ed local installs. `parachute
start vault`, `parachute start notes`, the running `parachute` umbrella
binary — all of them resolve to whatever code is in the working tree of
the corresponding repo, not to the published artifact.

That means leaving a repo checked out on a feature branch after merge has
two failure modes:

1. **Stale.** The local install runs the pre-merge state of the feature
   branch, missing whatever was added by review feedback or rebases.
2. **Diverged.** If `main` has moved on (another PR landed, or your PR was
   rebased before merge), the local install is now running code that
   doesn't match anything anyone else has — neither `main` nor the merged
   PR's final commit.

Both are silent. The steward sees their PR show up green on GitHub and
assumes the running daemon picked it up. It didn't.

We caught this on **2026-04-21**: a sweep across the active repos found
vault, notes, scribe, and cli all sitting on stale feature branches.
Channel's steward was the only one doing it correctly. The pattern got
documented across every CLAUDE.md the same week.

## Rules

- **Run `git checkout main && git pull` as the very next action after the
  human merge confirmation.** Not "later," not "before your next PR" —
  immediately, while you still have context that the merge happened.
- **Verify with `git status`.** It should print
  `Your branch is up to date with 'origin/main'.` Anything else (detached
  HEAD, ahead of origin, behind origin) is a state to investigate, not
  ignore.
- **No background-branch shortcut.** Don't try to keep working on the same
  feature branch by rebasing it on top of fresh `main`. If you have
  follow-up work, branch a new feature branch from the freshly-pulled
  `main`. It's one extra command and it keeps the chain of branches
  honest.
- **For repos with running daemons** (vault, channel, scribe via `serve`),
  consider a `parachute restart <svc>` after the pull so the running
  process picks up the new code. The need for this should fade as
  hot-reload coverage improves; for now it's the simplest way to be sure
  what's actually running.

## When this rule doesn't apply

- **Pure read-only work.** If you're just inspecting a repo without
  running its `bun link`-ed code, you can stay on a branch.
- **Repos without `bun link` installs.** `parachute-patterns` (this repo)
  is documentation only — there's no running daemon to drift from. The
  rule still applies for clarity, but the failure mode it prevents
  doesn't bite here.
- **Worktrees.** A separate worktree on a feature branch doesn't poison
  the linked install in the main checkout. Tentacles using `isolation:
  worktree` are isolated by construction; the rule applies to whichever
  checkout the running daemon resolves through.

## Where this applies

Every Parachute repo with code that gets `bun link`-ed for development:

- [`parachute-cli`](https://github.com/ParachuteComputer/parachute-cli/blob/main/CLAUDE.md#post-merge-hygiene)
- [`parachute-vault`](https://github.com/ParachuteComputer/parachute-vault/blob/main/CLAUDE.md#post-merge-hygiene)
- [`parachute-notes`](https://github.com/ParachuteComputer/parachute-notes/blob/main/CLAUDE.md#post-merge-hygiene)
- [`parachute-scribe`](https://github.com/ParachuteComputer/parachute-scribe/blob/main/CLAUDE.md#post-merge-hygiene)
- [`parachute-channel`](https://github.com/ParachuteComputer/parachute-channel/blob/main/CLAUDE.md#post-merge-hygiene)
- [`parachute.computer`](https://github.com/ParachuteComputer/parachute.computer/blob/main/CLAUDE.md#post-merge-hygiene) (Eleventy build, not a daemon, but same rule for consistency)

A new repo's `CLAUDE.md` should include the same section, linking back to
this doc. The text in each repo's `CLAUDE.md` may be one-sentence terse —
the canonical *why* lives here.

## Relationship to governance

This pattern is the operational complement to
[`governance.md`](./governance.md): branch-protection forces every change
through a reviewed PR; post-merge hygiene ensures the steward's local
state actually reflects what was merged. Without the second half, the
first creates a false sense of alignment.
