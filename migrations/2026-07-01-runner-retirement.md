---
title: parachute-runner retirement (full)
date: 2026-07-01
status: active
originating-pr: parachute-patterns#132 (decision is Aaron's, 2026-07-01; no code PR originates it)
---

# parachute-runner retirement

**Decided:** 2026-07-01 (Aaron): `parachute-runner` is **fully
retired**. The **module set of record** is: **vault, hub, agent,
scribe, surface** (committed core = vault / hub / scribe / surface;
agent ships as an experimental preview).

## Context

Runner was the lightweight "vault-as-job-substrate" primitive (cron
daemon polling `tag:job` notes, spawning `claude -p`; Phase 1 complete
2026-05-21, v0.2.0 2026-06-09). It was superseded by the
**parachute-agent scheduler**: a scheduled job is a `#agent/job` note —
"an automated human" — riding the existing vault-trigger → agent-turn →
outbound flow. The retirement arrived in stages:

- 2026-06-19 — runner repo gains `DEPRECATED.md` ("superseded by
  parachute-agent's scheduled jobs").
- 2026-06-25 — hub focus-tier marks runner `deprecated` ("not for new
  installs" per Aaron; still resolvable for existing installs).
- **2026-07-01 — full retirement (this file).** Runner drops out of the
  module set of record entirely.

## Code references

- [x] `parachute-runner/DEPRECATED.md` — exists (landed 2026-06-19,
      pre-dating this decision).
- [ ] GitHub: **archive** the `ParachuteComputer/parachute-runner` repo
      (verified 2026-07-01: not yet archived) + update the repo
      description to say retired/superseded. *(Aaron's hand)*
- [ ] npm: **deprecate `@openparachute/runner`** (currently `0.2.0`,
      not deprecated) with a message pointing at the parachute-agent
      scheduler (`#agent/job`). *(Aaron's hand / CI)*
- [ ] `parachute-hub/src/service-spec.ts` — remove/retire the `runner`
      entry in `SERVICE_SPECS`, the `runner: "deprecated"` focus-tier
      row, and its `KNOWN_MODULES` install resolution (decide: hard
      removal vs. keep-resolvable-for-existing-installs for one cycle,
      mirroring the notes precedent — notes kept a deprecated
      resolution path). Comments referencing runner as a live
      self-registering module (lines ~261, ~325, ~336, ~453, ~649)
      update in the same PR. *(PR: — parachute-hub, pending)*
- [ ] `parachute-hub` audit: `scripts/audit-canonical-refs.sh`'s
      install-string block still searches `$WORKSPACE/parachute-runner`
      — harmless (dir will stop changing), but drop it on next script
      touch. *(low priority)*

## Doc references

- [x] `patterns/canonical-ports.md` — 1945 row → **retired** (slot held
      for historical reference); prose updated to the 2026-07-01 module
      set of record. *(PR: parachute-patterns#132 — this batch)*
- [x] `scripts/audit-canonical-refs.sh` — new grep block flags
      live/promoted `parachute-runner` framing outside historical docs.
      *(PR: parachute-patterns#132 — this batch)*
- [ ] Workspace `CLAUDE.md` — committed-core/explorations table: the
      `parachute-runner` row ("shipped; not yet promoted") → retired
      2026-07-01, superseded by agent scheduled jobs; also the
      "trust-gradient" paragraph that names runner as "the lightweight
      successor primitive" needs a retirement note.
      *(parachute-workspace, pending)*
- [ ] `parachute-patterns/patterns/missing-dependency-ux.md` — audit
      scope named "the four committed-core repos + runner"; annotate on
      next touch. *(low priority — historical audit narration)*
- [ ] `parachute-patterns` live docs flagged by the new audit block
      (first run, 2026-07-01) — follow-up sweep, not this batch:
      `patterns/trust-gradient-isolation.md` ("Future: parachute-runner"
      §; the successor is now the agent scheduler),
      `guides/multi-writer-workspace.md` (recommends runner for 3+
      scheduled jobs — actively stale guidance),
      `patterns/module-self-registration.md` ("runner is currently
      exploration-tier" note + reference links),
      `patterns/module-surfaces.md` (runner row),
      `patterns/services-json-row-conventions.md` (runner as reference
      impl — links stay valid as historical example),
      `patterns/governance.md` (repo list naming runner). *(PR: —
      pending)*
- [ ] `parachute-hub/README.md` port table — 1945 row still says
      "shipped; exploration-tier"; → retired. *(bundle into the hub
      service-spec PR)*
- [ ] Dated design docs (`parachute.computer/design/2026-05-21-parachute-runner-design.md`,
      etc.) — historical record, **no edits** (covered by the audit
      script's historical-docs exception).

## Operator-facing references

- [ ] `parachute-runner/README.md` — top banner already implied by
      DEPRECATED.md; verify the README points at DEPRECATED.md before
      the repo is archived (archive freezes it). *(Aaron's hand, with
      the archive step)*
- [ ] Hub `help.ts` / setup-wizard copy — verify no "install runner"
      guidance remains once the service-spec PR lands. *(bundled into
      the hub PR above)*

## External references

- [ ] Team vault (`parachute-parachute`): the Canon/Modules note for
      Runner (and `Current/Parachute` if it names runner as live) →
      status retired, superseded-by pointer to agent `#agent/job`.
      *(vault write — uni/aaron)*
- [ ] npm package description for `@openparachute/runner` — covered by
      the deprecate step above.

## What this batch (parachute-patterns#132) covers vs. pending

**Covered here:** canonical-ports.md row + prose; the audit-script
runner block; this checklist file.

**Pending elsewhere:** repo archive + npm deprecate (Aaron), the hub
service-spec/KNOWN_MODULES/focus PR, workspace CLAUDE.md table, the
team-vault note.

## Cross-references

- [`../patterns/canonical-ports.md`](../patterns/canonical-ports.md) —
  1945 held-retired.
- [`2026-06-17-channel-to-agent.md`](./2026-06-17-channel-to-agent.md)
  — the module whose scheduler superseded runner.
- [`../patterns/trust-gradient-isolation.md`](../patterns/trust-gradient-isolation.md)
  — the insight that produced runner (the pattern doc itself uses
  "runner" generically and needs no edit; the "runner is the lightweight
  successor" framing lives in the workspace `CLAUDE.md`, tracked above).
