---
title: CLA rollout — org-wide contributor license agreement
date: 2026-06-04
status: active
originating-pr: parachute-patterns#117
---

# CLA rollout

OpenParachutePBC adopted an org-wide Individual Contributor License
Agreement (decided 2026-06-04). Agreement text + reusable check workflow
live in `ParachuteComputer/.github`; signatures are recorded org-wide in
`ParachuteComputer/cla-signatures`; each repo carries a thin caller
workflow. Policy + mechanics: [patterns/cla.md](../patterns/cla.md).

The goal: licensing flexibility for the company (commercial licensing
alongside AGPL) while §9 of the agreement pledges contributions stay
available under an OSI-approved open-source license.

## Central infrastructure

- [x] `ParachuteComputer/.github` repo — `CLA.md`, `CONTRIBUTING.md`,
      reusable `workflows/cla.yml` (created 2026-06-04)
- [x] `ParachuteComputer/cla-signatures` repo — README +
      `signatures/v1/` scaffold (created 2026-06-04)
- [ ] Org secret `CLA_PAT` — fine-grained PAT, `contents:write` on
      `cla-signatures` only (**Aaron**: create the PAT; setting the org
      secret can be delegated once the value exists)
- [ ] Legal review of `CLA.md` (**Aaron/counsel**: entity name +
      jurisdiction, §9 phrasing, employer-IP nuances)
- [x] `parachute-patterns/patterns/cla.md` — policy pattern (this PR)
- [x] `parachute-patterns/scripts/rollout-cla.sh` — caller-PR opener
      (this PR)

## Per-repo caller workflows

Each item = a PR adding `.github/workflows/cla.yml` (caller template in
[patterns/cla.md](../patterns/cla.md)). Use
[`scripts/rollout-cla.sh`](../scripts/rollout-cla.sh) to open them.

### Tier 1 — committed core + core support

- [ ] parachute-vault
- [ ] parachute-surface
- [ ] parachute-scribe
- [ ] parachute-hub
- [ ] parachute-patterns
- [ ] parachute.computer

### Tier 2 — shipped / active

- [ ] parachute-workspace (pilot — prove the flow here first)
- [ ] parachute-runner
- [ ] parachute-brain
- [ ] parachute-pebble
- [ ] paraclaw
- [ ] .github (the central repo accepts contributions too)

### Tier 3 — explorations / archiving (public, can still receive PRs)

- [ ] parachute-notes (archiving — still public)
- [ ] parachute-agent (renamed from parachute-channel 2026-06-17)
- [ ] parachute-daily
- [ ] parachute-narrate
- [ ] parachute-octopus
- [ ] parachute-agents
- [ ] parachute-cloud
- [ ] openparachute-cli
- [ ] meshwork
- [ ] prism
- [ ] tailshare
- [ ] pcc

**Excluded:** `cla-signatures` (bot-written record repo; hand edits
forbidden by policy, so no contribution flow to gate).

## Doc references

- [ ] Workspace `CLAUDE.md` — note the CLA pattern under governance
      (optional; pattern doc may be sufficient)
- [ ] `parachute.computer` site — contributing page, if/when one exists
      (none today; no action until then)

## Enforcement (gated on Aaron)

- [ ] Core-team signatures (Aaron + active maintainers sign on their
      next PRs)
- [ ] Go-decision: flip `CLA Assistant` to a **required status check**
      in branch protection across Tier 1 (then 2/3). Until then the
      check is advisory.

## Notes

- The caller uses `pull_request_target` + `issue_comment`; the reusable
  workflow never checks out PR code (safety invariant — see the review
  checklist in [patterns/cla.md](../patterns/cla.md)).
- Until `CLA_PAT` exists, the check will fail on its first real
  signature attempt (it can't write to `cla-signatures`). Pilot on
  parachute-workspace only after the secret is set.
