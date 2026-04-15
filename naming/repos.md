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
- `ParachuteComputer/parachute-agents` (plural repo, singular package `@openparachute/agent`)
- `ParachuteComputer/parachute-daily`
- `ParachuteComputer/parachute-scribe`
- `ParachuteComputer/parachute-patterns` (this repo)
- `ParachuteComputer/openparachute-cli` — the umbrella, named after the npm scope since the repo is the CLI itself

## Why

- One GitHub org surface for everything that makes up the Parachute Computer.
- `parachute-` prefix makes the family obvious from a bare repo list.
- Matching the filesystem layout under `~/UnforcedAGI/Code/ParachuteComputer/`
  means repo-name == folder-name everywhere.

## Rules

- Repo name must match the folder checked out under
  `~/UnforcedAGI/Code/ParachuteComputer/<repo>`. (Octopus tentacle spawn
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
