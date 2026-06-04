# Contributor License Agreement (CLA)

**Status:** adopted 2026-06-04 · **Rollout:** [migrations/2026-06-04-cla-rollout.md](../migrations/2026-06-04-cla-rollout.md)

Every contribution to an OpenParachute repository requires a signed
Individual Contributor License Agreement. The agreement text, the
signing flow, and the enforcement machinery are all centralized; each
repo carries only a thin caller workflow.

## Why

OpenParachutePBC needs licensing flexibility — the ability to offer
commercial licensing alongside AGPL, relicense if the ecosystem's needs
change, and act as a single licensing counterparty as the company grows.
Without a CLA, every contributor retains exclusive rights over their
diff and any future licensing decision needs unanimous consent from
every past contributor.

The flip side — protecting the open-source posture — is handled inside
the agreement itself: **§9 ("The OpenParachute Pledge")** commits that
every contribution stays available under an OSI-approved open-source
license, at minimum the license the project carried at contribution
time (AGPL-3.0 for most repos today). The CLA is a license grant, not a
copyright assignment; contributors keep ownership of their work.

## Who signs

**Everyone, including core team.** Outside contributors must sign
before merge. Core-team members should sign too — it costs one comment,
makes the signature record complete from day one, and avoids a
two-class contributor model. Bot accounts (`*[bot]`) are allowlisted.

A contributor signs **once**, org-wide. The signature is recorded in
[`ParachuteComputer/cla-signatures`](https://github.com/ParachuteComputer/cla-signatures)
(`signatures/v1/cla.json`) and covers all current and future
contributions to every OpenParachute repository.

## The pieces

| Piece | Where | Role |
|---|---|---|
| Agreement text | [`ParachuteComputer/.github/CLA.md`](https://github.com/ParachuteComputer/.github/blob/main/CLA.md) | The ICLA itself (Apache-ICLA-derived + §9 pledge). DRAFT pending legal review — mechanics are live, text may be refined. |
| Org contributing guide | [`ParachuteComputer/.github/CONTRIBUTING.md`](https://github.com/ParachuteComputer/.github/blob/main/CONTRIBUTING.md) | Default CONTRIBUTING for repos without their own; explains the signing flow. |
| Reusable check workflow | [`ParachuteComputer/.github/.github/workflows/cla.yml`](https://github.com/ParachuteComputer/.github/blob/main/.github/workflows/cla.yml) | `workflow_call` wrapper around `contributor-assistant/github-action` v2.6.1 (SHA-pinned). One place to upgrade the action or change config. |
| Signature record | [`ParachuteComputer/cla-signatures`](https://github.com/ParachuteComputer/cla-signatures) | Bot-written JSON; never hand-edited except verified withdrawal requests. |
| Per-repo caller | `.github/workflows/cla.yml` in each repo | Thin caller (below). The only thing that lives in individual repos. |
| Org secret `CLA_PAT` | org settings | Fine-grained PAT, `contents:write` on `cla-signatures` only. Lets the action in any repo write the central signature file. |

## The caller workflow

Each repo carries exactly this (see the rollout script,
[`scripts/rollout-cla.sh`](../scripts/rollout-cla.sh)):

```yaml
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
```

Notes on the shape:

- `pull_request_target` (not `pull_request`) so the check runs with
  repo-context permissions on fork PRs — required for the bot to
  comment. The reusable workflow never checks out or executes PR code,
  which is what makes `pull_request_target` safe here.
- `issue_comment` catches the signing comment ("I have read the CLA
  Document and I hereby sign the CLA") and `recheck`.
- `secrets: inherit` passes the org `CLA_PAT` through.
- The version pin is `@main` on our own `.github` repo; the third-party
  action inside is SHA-pinned. Upgrading the action = one PR to
  `.github`, zero per-repo churn.

## How signing works (contributor view)

1. Open a PR. The CLA check comments with a link to the agreement.
2. Read it; comment exactly: `I have read the CLA Document and I hereby
   sign the CLA`.
3. The check flips green on this and every future PR in any repo.
4. Stuck check after signing → comment `recheck`.

## Enforcement levels

1. **Advisory (rollout default):** the check runs and comments, but
   isn't a required status check — a maintainer can still merge an
   unsigned PR. This is where every repo starts.
2. **Required (target):** `CLA Assistant` added to required status
   checks in branch protection. Flipping this org-wide is an explicit
   go-decision (Aaron), not part of the mechanical rollout.

## Changing the agreement text

The agreement is versioned by the signatures path (`signatures/v1/`).
Editorial fixes (typos, formatting) can land in place. A *substantive*
change to the grant or the pledge requires bumping to `signatures/v2/`
in the reusable workflow so existing signatures aren't silently
reinterpreted — everyone re-signs on their next PR. Get counsel review
before any substantive change (and before relying on v1 in anger; the
current text is a DRAFT adapted from the Apache ICLA).

## Review checklist for this pattern

When reviewing a PR that touches CLA machinery:

- Caller workflows must match the template above exactly — drift in
  `permissions` or triggers breaks the check in non-obvious ways.
- Never check out PR code in any workflow triggered by
  `pull_request_target`.
- The third-party action stays SHA-pinned in the central reusable
  workflow; callers reference our own repo only.
- Signature-file edits in `cla-signatures` come only from the bot.
