# Reviewer agent

## Convention

For PRs that touch **auth, scope, schema, or public API**, the team-lead
runs a `reviewer` agent against the diff before recommending merge.
This is an additional pass on top of the steward's self-tests and the
team-lead's own verification — the agent reads the diff with no prior
context from the conversation, which catches things the author and
the steward who watched the PR get drafted both miss.

This is a **convention, not enforcement.** No CI gate fires it; no
merge block. The team-lead invokes it when the change-class warrants
it. Other PR classes (UI tweaks, doc edits, test-only changes,
internal refactors with no surface change) skip the reviewer agent.

This pattern pairs with [`governance.md`](./governance.md) Rule 1 —
"every PR is reviewed by a team-lead role and merged by a human." The
reviewer agent is a tool the team-lead uses inside that review, not a
replacement for the human merge step.

## Why a fresh-context reviewer

Tentacles draft PRs in the context of a conversation with the team-lead.
That conversation gives them the *intent* of the change — which is
load-bearing for productivity but creates a blind spot: the steward
won't notice when the diff drifts from the intent, because they're
seeing it through the lens of what they meant to do. The team-lead has
the same issue from the other direction (knew the brief, saw the
draft, anchored on the design).

A fresh agent has neither anchor. It reads the diff cold against
whatever standards the prompt names — patterns, RFCs, the existing
codebase — and surfaces the gap between what the diff *says* and what
the surrounding code expects. The class of bug it catches is the
class where the steward and team-lead both nodded along with the same
mistake.

This is why the reviewer is **fresh-spawn each time, not a long-lived
agent.** Memory of prior reviews would re-introduce the anchoring the
fresh-spawn was meant to break.

## When to invoke

Run the reviewer agent on PRs that touch:

- **Auth** — token issuance, validation, refresh, OAuth flows, scope
  checks, JWKS, anything in `parachute-vault/src/oauth.ts` or
  comparable callee surfaces.
- **Scope vocabulary** — adding/removing/renaming a scope, changing
  scope inheritance, splitting `vault:write` semantics, etc. See
  [`oauth-scopes.md`](./oauth-scopes.md).
- **Public API surface** — request shapes, response shapes, error
  envelopes, optional-vs-required fields, status-code semantics. The
  thing that stings here is a quietly-breaking change to a field
  third-party clients depend on.
- **Schemas** — JSON Schema files, well-known metadata shapes,
  database migrations on shared resources.
- **`/.parachute/*` endpoints** — the module protocol surface (see
  [`module-protocol.md`](./module-protocol.md)).
- **Inter-service contracts** — anything that crosses the
  vault↔scribe / hub↔service boundaries (see
  [`service-to-service-auth.md`](./service-to-service-auth.md),
  [`context-in-payload.md`](./context-in-payload.md)).

Skip the reviewer agent on:

- Pure-content edits (markdown, docs, README, blog posts).
- Test-only changes.
- Internal refactors where no caller-visible surface moves.
- UI-only frontend tweaks that don't change the data the backend
  emits.

When in doubt, run it. The cost is small; the catch is asymmetric.

## What the reviewer prompt should contain

A good reviewer-agent prompt is **specific and disposable** — it
describes the change at hand and the exact standards to check, then
exits.

Useful elements:

- **The diff or PR URL.** The agent should read the actual diff, not
  a summary.
- **Patterns the diff touches.** Name them by file (e.g.
  "compare against `parachute-patterns/patterns/oauth-scopes.md` and
  `hub-as-issuer.md`"). Don't trust the agent to guess.
- **The relevant RFC or external spec, if any.** Quoting the exact
  section saves the agent a search trip and pins the bar of review.
- **What was claimed in the PR description.** Reviewer should verify
  the claim against the diff, not just verify the diff in isolation.
- **What you specifically want eyes on.** "Is the conflict shape
  symmetric between HTTP and MCP?" is a better prompt than "review
  this diff."

A bad reviewer-agent prompt is a generic "review this PR" — no
standards, no reference points, no claim to verify. The agent's
output is correspondingly generic and doesn't catch the things the
steward already covered.

## What the reviewer agent reports back

A useful reviewer report is **specific and falsifiable**. The
team-lead reads it and either accepts or rejects each finding; vague
findings get rejected by default.

Good shape (use as a template — adapt as needed):

- **Verified**: claims in the PR that the agent checked and
  confirmed against the diff (e.g. "the new validator returns
  `{valid, scopes}` on the success path of the shared-secret branch
  — confirmed at line X").
- **Discrepancies**: where the diff diverges from the claimed
  patterns / RFCs / linked docs. Include line numbers.
- **Risks not addressed**: edge cases or invariants the diff doesn't
  cover. Don't speculate — only flag risks the agent can point at
  concretely.
- **Out of scope but adjacent**: nearby code the diff didn't touch
  that *probably* should have moved together. Flag, don't demand.

The team-lead's verification summary to the human merger should
quote (or distill) the reviewer's findings — the human gets the
benefit of the fresh-context pass without having to spawn another
agent themselves.

## Rules

- **Reviewer is fresh-spawn each PR.** No long-lived reviewer agent;
  no memory across PRs. Anchoring is what we're avoiding.
- **Reviewer reads the actual diff.** Pass the PR URL or the diff
  body, not a description-only summary.
- **Reviewer is informed by patterns, not just code.** Cite the
  specific pattern files the diff touches in the prompt.
- **Reviewer's findings are quoted in the team-lead's verification
  summary.** The human merger should know the reviewer ran and what
  it said. Hidden reviews don't compound into trust.
- **Reviewer is not a merge gate.** Findings get accepted or rejected
  by the team-lead. A non-blocking finding is still a worth-flagging
  finding — accept-with-note is fine.

## What this isn't

- **A CI step.** The reviewer agent is invoked manually by the
  team-lead during review, not on every push. CI gates are
  type-check, test, lint — those run regardless.
- **A second human reviewer.** When the team grows past one human
  contributor, branch-protection's required-review count goes to
  `≥1` (see [`governance.md`](./governance.md)). The reviewer agent
  doesn't substitute for that — it's a tool the human reviewer
  uses, the same way the team-lead uses it today.
- **A bug-finder.** The reviewer is best at *consistency* checks
  (does this match the pattern / RFC / surrounding code) and
  *coverage* checks (did the PR address what it claimed). It's not
  a fuzzer or a static analyzer. Don't ask it to find race
  conditions in concurrent code; ask it whether the diff matches
  the pattern doc.

## Open questions

- **Should reviewer findings be persisted on the PR?** Today the
  team-lead distills them into the verification summary. A "reviewer
  comment thread" on the PR itself would let the human merger see
  the raw output. Defer until the volume warrants it.
- **Reviewer for content-class PRs.** Pure-content patterns (this
  repo, blog posts, docs) currently skip the reviewer. If/when we
  hit a class of content-bug that the human-only pass keeps missing,
  the convention may grow.
- **Multi-pattern reviews.** A PR that touches three patterns at
  once — does each pattern get its own reviewer pass, or one
  combined? Today: combined, one reviewer with all three patterns
  cited. Revisit if combined reviewers start to miss things a
  per-pattern split would catch.
