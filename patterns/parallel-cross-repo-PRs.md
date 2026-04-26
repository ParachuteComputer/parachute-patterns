# Parallel cross-repo PRs

## Convention

When a single conceptual change spans multiple Parachute repos
(OAuth Phase 0 was 4 simultaneous PRs across vault / cli / notes /
scribe; stateless-scribe was a similar fan-out), the team-lead
**briefs each steward in parallel** and each steward opens its own
PR independently. The change composes when the PRs land in any
order. There is no master PR, no orchestration branch, and no
"please merge mine first."

This is the dominant shipping shape for ecosystem-wide changes. It
trades a bit of upfront thinking (designing the change to be
landing-order-independent) for a lot of parallelism (each steward
moves at full speed without blocking on the others).

## Why parallel

- **Ordering dependencies are a coordination tax.** A "merge X
  before Y" rule means someone — the team-lead or the human merger
  — has to remember the order, hold one PR while reviewing the
  other, and re-verify after the first lands. That tax compounds
  across 3–4 PRs and breaks down entirely when one PR needs a
  revision.
- **Stewards are repo-scoped, not task-scoped.** Each tentacle is
  the long-lasting steward of one repo. A multi-repo change
  naturally fans out one PR per steward; coordinating them as
  separate independent PRs respects the steward boundary. See
  [`octopus`](https://github.com/ParachuteComputer/parachute-octopus)
  and the per-repo CLAUDE.md spawning convention.
- **The human merger is the serializer.** The single human (Aaron
  today) reviews and merges in whatever order they reach the queue.
  If the changes are designed parallel-safe, that order doesn't
  matter.
- **Failures isolate.** A PR that needs a revision doesn't block
  the others. The author iterates in their own repo; the rest of
  the change still ships.

## How to design parallel-safe scope

Before briefing the stewards, the team-lead asks: **does each
repo's change make sense at every state of the others?**

- ✅ **Additive contracts** — adding a new endpoint, a new optional
  field, a new env var with a fallback. The new thing exists
  whether or not the consumer has shipped yet. The consumer-side
  PR can land before, after, or interleaved with the producer side.
- ✅ **Backwards-compatible shape changes** — accepting both old and
  new shapes on the receiving side, then later dropping the old.
  Shape co-existence is the bridge.
- ✅ **Symmetric contracts that already exist on both sides** —
  e.g. RFC 8414 path-insertion adopted by vault, with hub picking
  it up later when hub becomes the IdP. Both sides eventually meet;
  neither needs the other to ship today.
- ❌ **Breaking renames** — renaming a field from `foo` to `bar`
  across producer and consumer. If the producer ships first,
  consumers break; if consumers ship first, they get nothing.
  Either bridge with both-shapes-accepted (and split into a deprecate-
  then-remove sequence) or accept that this is **not** a parallel
  change and serialize it.
- ❌ **Tightly-coupled code moves** — moving a function from one
  repo to another. The old location can't disappear before the new
  location is ready, and vice versa. Stage the move: PR 1 adds the
  new location, PR 2 (after merge) removes the old.

When in doubt, ask whether you'd be comfortable with each PR
landing alone. If "no," redesign the change.

## Shape

A typical parallel cross-repo brief looks like:

1. **Team-lead writes the design once** — the cross-cutting context,
   the conformance criteria, the test plan. This goes once into a
   shared place (the design doc, a `Current/Parachute` note in the
   vault, or the team-lead's working scratchpad).
2. **Team-lead briefs each steward** with a self-contained scope:
   "your repo's part is X; here are the file references; here's
   how to verify; here's how to know you're done." Each steward
   gets a brief that does **not** require talking to the other
   stewards mid-flight.
3. **Stewards work in parallel.** Each opens its own PR with its
   own description. They cite the design doc / shared brief.
4. **Team-lead reviews each PR independently** with the standard
   verification summary (see [`governance.md`](./governance.md)
   Rule 1).
5. **Human merges in whatever order they reach.** Stewards don't
   coordinate merge order.

## Rules

- **One PR per repo per change.** Don't try to bundle changes from
  multiple repos into a "monorepo-style" megaPR — Parachute is
  multi-repo on purpose.
- **No `merge X first, then Y` instructions.** If the change has a
  required order, redesign the scope until it doesn't, or split
  into a sequence of parallel-safe waves.
- **Each PR description references the shared design.** Reviewers
  shouldn't have to reconstruct the cross-cutting picture from a
  single repo's diff. Link to the design doc, the team-lead's
  brief note, or a sibling PR.
- **Conformance is per-repo.** If repo A's PR ships and repo B's
  doesn't, repo A is still in a working state — that's what
  parallel-safe scope means. The full-system behavior may not yet
  be live, but no single repo is broken.
- **Migration notes carry the cross-cutting story.** When the
  pattern doc lands in `parachute-patterns/`, the
  [`adoption/migration-notes.md`](../adoption/migration-notes.md)
  entry is the place that names *all* affected repos. Each
  individual PR's description is repo-scoped; the cross-cutting
  index lives here.

## Examples

### OAuth Phase 0 (2026-04-23)

Four parallel PRs:

- `parachute-vault` — implement `/oauth/authorize`, `/oauth/token`,
  `resolveOAuthCoordinates`, advertise hub as `iss`. PR
  [#147](https://github.com/ParachuteComputer/parachute-vault/pull/147).
- `parachute-cli` — derive hub origin in `src/hub-origin.ts`, pass
  `PARACHUTE_HUB_ORIGIN` to vault on `expose up` / `start`.
- `parachute-notes` — register OAuth client, request consent, store
  PKCE state. PR
  [#49](https://github.com/ParachuteComputer/parachute-notes/pull/49)
  and follow-ups.
- `parachute.computer` — design doc, blog post material, scope
  vocabulary documentation.

Each PR landed independently. Hub-origin awareness landed on the CLI
side before vault advertised hub-as-issuer; vault's discovery
endpoint worked correctly in both worlds (with and without the env
var). Notes' OAuth flow worked against vault-as-issuer first, hub-as-
issuer after. Parallel-safe by construction.

### Stateless scribe (2026-04 launch week)

Similar fan-out:

- `parachute-vault` — pre-fetch context, attach as multipart part,
  send to scribe with `transcribe: true`. Vault PR
  [#156](https://github.com/ParachuteComputer/parachute-vault/pull/156).
- `parachute-scribe` — drop the `vault:` config block; accept inline
  `context` part; tolerant parser falls through to "no context" on
  malformed payload.
- `parachute-cli` — `auto-wire` mints `SCRIBE_AUTH_TOKEN` and
  installs it on both ends.
- `parachute-patterns` — write down `context-in-payload.md`,
  `service-to-service-auth.md`.

The scribe-side change shipped without immediately requiring the
vault-side payload to land — old `vault:` config was simply removed,
and scribe defaulted to "no context" until vault started sending one.
Parallel-safe.

## What this isn't

- **A monorepo argument.** Parachute is multi-repo because each
  module is independently deployable and independently authored.
  Parallel cross-repo PRs are how you coordinate multi-repo without
  losing parallelism.
- **A scheduling tool.** This pattern is about *shape* (parallel-
  safe scope) and *brief* (self-contained per-steward), not about
  who works when. Stewards are spawned and run on their own
  cadence.
- **A workaround for "real" coordination.** Sometimes a change
  *does* need ordering — a breaking rename across two repos. In
  that case, design the bridge (accept both shapes, deprecate, then
  remove) so the bridge-half is parallel-safe, and the removal-half
  is also parallel-safe. The serial moment shrinks to "the
  deprecation window," not "the merge sequence."

## Open questions

- **Multi-human team.** Today the human merger is a single person
  (Aaron). When a second human contributor with merge authority
  joins, parallel cross-repo merges may interleave with their work.
  The pattern still holds; the team-lead's brief just goes through
  the human merger's queue with whatever priority the work needs.
- **Cross-repo CI.** No cross-repo CI today — each repo's CI runs
  in isolation. If/when an integration test needs `vault@N +
  scribe@M` to be valid together, the parallel-safe rule may need
  to extend to "and CI passes against any sibling-repo HEAD." Out
  of scope for now.
