# Trust-gradient determines isolation level

> Same-operator vaults + same-operator automation = no isolation needed
> = lightweight primitive. Hosted multi-tenant + third-party prompts =
> steep trust gradient = container isolation. The same module shouldn't
> try to span both.

## The pattern

For every Parachute primitive that runs work against a vault — schedulers,
agent runners, webhook reactors, anything that takes input and acts on
storage — **the level of isolation it needs is set by the trust gradient
between the actor and the resource, not by aesthetic preference for
"safety."** A flat gradient (the operator writes the prompts, owns the
vault, runs the runner on their own box) needs no sandbox; a subprocess
with a scrubbed environment is sufficient. A steep gradient (third-party
prompts against tenant-owned data on shared infrastructure) needs real
isolation: containers, network policy, per-tenant resource limits.

Design the primitive for one end of the gradient. Don't try to span both.

## Why this matters

Getting it wrong is expensive in both directions.

**Over-isolating a trusted context** is a complexity tax operators don't
want to pay. parachute-agent is the canonical example: Docker images,
slug-keyed image names, supervisor coordination, image-per-project
lifecycle, container restart loops. Every one of those mechanisms solves
a problem that owner-operators — the people who in practice run
parachute-agent — don't have. The runner ran their prompts against their
vault on their machine; there was nothing to sandbox from. The
operational surface was pure overhead. The Gitcoin Brain prototype
(May 2026) reached the same use case with a ~200-line Python runner that
spawns `claude -p` from cron, and the lighter primitive proved
strictly better for the audience.

**Under-isolating an untrusted context** is a security failure. A
multi-tenant runner that lets one tenant's job touch another tenant's
filesystem, exhaust the host's CPU budget, or read another tenant's
secrets is one bad prompt away from a data leak. The cost of containers
is real, but in a steep-gradient context they're load-bearing — not
ceremonial.

The principle is simple and the failure modes are loud once you look for
them. The hard part is naming the audience before you start building.

## How to apply

**Name the audience first.** Before writing a line of code in a new
runtime primitive, declare which gradient it serves:

- **Owner-operated** (flat gradient) — the operator writes the prompts,
  owns the vault, and runs the primitive on hardware they control.
- **Hosted multi-tenant** (steep gradient) — many tenants, untrusted
  prompts, shared infrastructure. The platform is responsible for
  preventing tenant-to-tenant blast radius.
- **Both, but different modes** — see below; almost always means *two
  primitives*, not one.

**If both audiences are real, ship two primitives.** A single module
with `--mode lightweight` vs `--mode container` becomes two codebases
glued together at the CLI. The operational surfaces diverge fast: logs,
restart semantics, lifecycle hooks, secret handling, debugging stories.
Better to ship two narrower modules that each do their job well
(`parachute-jobs` for owner-operated, `parachute-cloud` for hosted)
than one wide module that does both poorly.

**Default to the lightest viable primitive.** For owner-operated
work — which is most of what Parachute users will actually run today —
the right shape is:

- Subprocess with a scrubbed environment (only the vars the runner
  needs).
- Restricted `PATH` (so the spawned binary can't accidentally find
  something it shouldn't).
- Token minted by the operator, scoped via OAuth scope strings (see
  [`oauth-scopes.md`](./oauth-scopes.md)).
- Scheduled by `cron` or invoked on demand.
- No containerization, no image build, no supervisor.

Reach for container isolation only when the gradient genuinely demands
it — and when you do, commit fully (per-tenant network policy, image
discipline, the whole architecture). Don't half-isolate.

## Worked examples

### parachute-jobs (lightweight, owner-operated) — TBD

The future home of the Gitcoin-Brain-style runner. Trust gradient: flat.
The operator wrote the prompts, owns the vault, runs the cron entry on
their own host. Architecture:

- A small script (Python or TypeScript — the language doesn't matter)
  spawned by `cron`.
- Reads "job notes" from vault via REST using an operator-minted token.
- For each job: spawns `claude -p` as a subprocess with the inline
  MCP config from `parachute-vault mcp-config <name>`.
- Writes outputs back to vault via REST.
- No container, no sandbox. The operator is the actor and the
  resource-owner; there is nothing to isolate from.

### parachute-cloud (steep gradient, hosted multi-tenant) — TBD

When demand for hosted Claude-against-vault automation materializes,
parachute-cloud is the right home for it. Trust gradient: steep. Many
tenants, prompts authored by tenants, shared infrastructure. Architecture
reuses the parachute-agent isolation ideas because they're correct *for
this audience*:

- Each tenant's work runs in its own container.
- Per-tenant network policy; tenants cannot reach each other's vaults or
  the host's control plane.
- Image-per-task or image-per-tenant lifecycle, supervisor-coordinated.
- Resource limits enforced at the container layer, not by the
  application.

The same container mechanics that are overhead for parachute-jobs are
load-bearing here.

### parachute-agent (deprecated 2026-05-20)

parachute-agent built the heavy architecture for an audience that turned
out to be the light-architecture audience. The container isolation,
slug-keyed images, supervisor lifecycle — all of it was real engineering
work, but the audience it shipped to (owner-operators running prompts
they wrote against vaults they own) didn't need any of it. Documented in
retrospect as the wrong tradeoff in
[`parachute-agent/DEPRECATED.md`](https://github.com/ParachuteComputer/parachute-agent/blob/main/DEPRECATED.md).
The lessons land here as a pattern so the next runtime primitive starts
from "name the audience first" instead of "build the safest thing."

## Anti-patterns

- **"Make the runner configurable"** — `--mode lightweight` vs
  `--mode container` on one binary. Tempting (one codebase, both
  audiences). Pays off only on paper. Operational complexity of
  supporting both modes — logs, restarts, debugging, lifecycle hooks,
  secret handling, cross-mode test matrices — exceeds the cost of
  shipping two narrower modules. The seam between modes is where
  bugs live.
- **"Add container support to the lightweight runner later"** —
  architecture diverges fast once isolation enters the picture.
  Network namespacing, image build pipeline, supervisor, resource
  enforcement — these aren't bolt-ons. Better to ship a separate
  cloud primitive when that audience actually materializes than to
  retrofit isolation into a runner that didn't budget for it.
- **"Add lightweight mode to the container runner"** — same problem
  in reverse. The container runner's complexity surface is sized for
  isolation; stripping it down to subprocess-on-cron means
  re-implementing half the runner.
- **"Isolate just in case"** — defensive over-isolation in a flat
  trust gradient. The cost is paid every day by operators who have to
  manage the isolation machinery; the benefit accrues to a threat
  model that doesn't apply to them.

## Related patterns

- [`oauth-scopes.md`](./oauth-scopes.md) — `vault:<name>:<read|write|admin>`
  scope inheritance is the same "least privilege at the resource"
  instinct expressed at the auth layer. Trust-gradient-isolation is the
  runtime-layer cousin.
- [`service-to-service-auth.md`](./service-to-service-auth.md) — the
  trust axis between Parachute services. Today flat (loopback +
  shared secret); tomorrow JWT-mediated, but still distinct from
  user-prompt trust. Different gradients, different mechanisms.
- [`governance.md`](./governance.md) — the rules these patterns live
  inside. Naming the audience belongs to the same family of
  decisions as RC-versioning and the patterns check.

## History

**Origin.** The Gitcoin Brain prototype (May 2026) was the moment the
insight landed: a ~200-line Python cron runner spawning `claude -p`
turned out to be a complete solution for owner-operated automation
against a vault. Everything parachute-agent layered on top of that
shape — containers, supervisor, slug-keyed images, per-project image
lifecycle — was solving for a trust gradient that didn't exist for
the audience actually using it.

**Consequence.** parachute-agent was deprecated 2026-05-20.
[`parachute-agent/DEPRECATED.md`](https://github.com/ParachuteComputer/parachute-agent/blob/main/DEPRECATED.md)
captures the per-module narrative; this pattern doc captures the
generalizable lesson so the next runtime primitive doesn't repeat it.

**Future.** `parachute-jobs` (TBD) implements the lightweight
primitive for owner-operated automation — the Gitcoin Brain shape
graduated into a committed module. `parachute-cloud` (TBD) handles
the hosted-multi-tenant case if and when that demand materializes,
reusing the container-isolation ideas where they're load-bearing.
Two modules, two audiences, two clearly-distinct trust gradients —
which is the whole point.
