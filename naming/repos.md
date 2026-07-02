# Repo names

## Convention

Public Parachute repos live under the `ParachuteComputer` GitHub org, and are
named `parachute-<module>` (plural is fine where it reads better than
singular — the npm package stays singular; see `packages.md`).

```
ParachuteComputer/parachute-<module>
```

Examples:

- `ParachuteComputer/parachute-vault`
- `ParachuteComputer/parachute-daily`
- `ParachuteComputer/parachute-scribe`
- `ParachuteComputer/parachute-notes`
- `ParachuteComputer/parachute-agent` (renamed from `parachute-channel`
  2026-06-17; package `@openparachute/agent`)
- `ParachuteComputer/parachute-hub` — the umbrella; ships the `parachute` bin
- `ParachuteComputer/parachute-patterns` (this repo)
- `ParachuteComputer/parachute.computer` — the website (kept literal, matching
  the domain)

## Why

- One GitHub org surface for everything that makes up the Parachute Computer.
- `parachute-` prefix makes the family obvious from a bare repo list.
- Matching the on-disk layout under `ParachuteComputer/<repo>` means
  repo-name == folder-name everywhere.

## Rules

- Repo name must match the folder checked out under
  `ParachuteComputer/<repo>` on the workstation. (Octopus tentacle spawn
  prompts rely on this.)
- License: AGPL-3.0 by default, matching the family. If a module needs a
  different license, open an issue here first so we discuss it once rather
  than per-repo.
- README must point back to this repo from its top section: "Parachute
  conventions live in [parachute-patterns](...)".

## Open questions

- Are there private or unreleased Parachute repos that should stay outside
  the `ParachuteComputer` org? Currently: UnforcedAGI is private but lives
  under a personal namespace. Decision not urgent.
- The `ParachuteComputer/openparachute-cli` repo predated the
  `parachute-` prefix decision; it's no longer the active CLI source
  (active source is `parachute-hub`). Archive or redirect — tracked but
  not urgent.
