---
title: Missing-dependency UX — actionable install messages across all spawn sites (task #188)
date: 2026-05-29
status: active
originating-pr: parachute-patterns (this normative-contract PR)
---

# Missing-dependency UX

Every external-binary spawn site that can crash with a cryptic `Executable
not found in $PATH` must instead give an **actionable install message** —
"install it via `<OS commands>` / or ask your system administrator." The
normative contract is [`patterns/missing-dependency-ux.md`](../patterns/missing-dependency-ux.md):
one wire shape (`error_type: "missing_dependency"`, HTTP 503), one 5-part
message anatomy, three surfaces (CLI / HTTP / SPA). The registry + formatter +
ENOENT helpers live in a shared lib, **`@openparachute/depcheck`** (built in
`parachute-hub/packages/depcheck`, mirroring the `scope-guard` subpackage);
each module wires its own spawn sites.

## Why the shift

Audit (2026-05-29, task #188) across the four committed-core repos + runner:
**77 external-binary spawn sites; 21 produce cryptic crashes when the binary is
missing.** This generalizes two prior point-fixes into one ecosystem contract:

- **vault#415** — `git`-not-installed leaked the raw spawn error on a git-less
  server; the fix (`git-preflight.ts`: `GitNotInstalledError`,
  `ensureGitAvailable`, `isGitNotFoundSpawnError`, 503 `git_not_installed`) is
  the shape depcheck generalizes across every binary.
- **cloudflared (hub)** — `dnf install cloudflared` returns "No match for
  argument: cloudflared" on Amazon Linux 2023; `cloudflaredInstallHint` taught
  us the static-binary curl recipe wins over distro packages, and an unknown
  arch drops to docs rather than fabricating a 404ing URL.

## Adoption checklist

Each line gets a PR-number slot, filled as it lands.

- [ ] **depcheck lib publish** — `@openparachute/depcheck` in
  `parachute-hub/packages/depcheck`: `DepSpec`, registry, `ensureExecutable`,
  `rethrowIfMissing`, `formatMissingDependency`, `toWire`. Published to npm `rc`
  dist-tag so siblings can depend on it. — _PR TBD (parachute-hub)_
- [ ] **hub adoption** — wire hub's own spawn sites + the shared SPA error
  component switch on `error_type === "missing_dependency"`. — _PR TBD (parachute-hub)_
- [ ] **vault adoption** — route the vault gap sites through depcheck; fold the
  existing `git-preflight.ts` into the shared lib (or have it re-export). —
  _PR TBD (parachute-vault)_
- [ ] **scribe adoption** — wire the transcription-provider spawn sites
  (`whisper` / `parakeet` / `onnx` / `ffmpeg`) with `optional` + `altHint`. —
  _PR TBD (parachute-scribe)_
- [ ] **runner adoption** — wire the `claude` spawn site (`optional` + altHint:
  install Claude Code). — _PR TBD (parachute-runner)_

## The 21 gap sites (adopter work list)

Grouped by repo. Each adopter routes these through `ensureExecutable` +
`rethrowIfMissing` (belt-and-suspenders) and maps the HTTP path to 503 +
`error_type: "missing_dependency"`.

### parachute-hub

- [ ] `tailscale` — `src/.../run.ts:12`
- [ ] supervisor `startCmd` (the bare "failed") — `src/.../lifecycle.ts:81`
- [ ] `tail` — `src/.../lifecycle.ts:949`
- [ ] `install.ts:739` — `parachute-vault` spawn

### parachute-vault

- [ ] `tail` — `src/cli.ts:1647`
- [ ] `git` (mirror credentials) — `src/mirror-credentials.ts:646`, `:657`, `:680`, `:687`
- [ ] `launchctl` — `src/launchd.ts:105`
- [ ] `systemctl` — `src/systemd.ts:57`–`:77`
- [ ] `tar` (backup) — `src/backup.ts:249`, `:252`

### parachute-scribe

- [ ] `parakeet` — `src/.../parakeet-mlx.ts:12` (optional / altHint)
- [ ] `whisper` — `src/.../whisper.ts:16` (optional / altHint)
- [ ] `onnx` — `src/.../onnx-asr.ts:25` (optional / altHint)
- [ ] `ffmpeg` — `src/.../onnx-asr.ts:15` (foundational within the provider)

### parachute-runner

- [ ] `claude` — `src/spawn.ts:160` (optional / altHint)

> Line numbers are from the 2026-05-29 audit snapshot; adopters should confirm
> against the live tree before wiring (the spawn sites may have drifted).

## Code references

- [ ] `parachute-hub/packages/depcheck/**` — the shared lib (NEW package). —
  _PR TBD_
- [ ] hub / vault / scribe / runner spawn sites above — _per-repo PRs TBD_
- [ ] `parachute-vault/src/git-preflight.ts` — reconcile with depcheck (fold or
  re-export so vault doesn't carry a parallel registry). — _PR TBD_
- [ ] hub's shared SPA error component — add the
  `error_type === "missing_dependency"` branch (install card). — _PR TBD_

## Doc references

- [x] `parachute-patterns/patterns/missing-dependency-ux.md` — the normative
  contract (this PR).
- [x] `parachute-patterns/scripts/audit-canonical-refs.sh` — drift block for
  hand-synced install strings outside depcheck (this PR).
- [ ] `@openparachute/depcheck` README — usage + registry shape. — _PR TBD (with the lib)_

## Operator-facing references

- None today. The operator-visible change is *better error messages*, not a
  command/flag change; no README install-step or blog copy references these
  spawn sites by name. (Adopter PRs may update per-repo troubleshooting docs.)

## External references

- [ ] npm: `@openparachute/depcheck` package description (set when first
  published). No GitHub repo description change — the lib lives inside
  parachute-hub.

## Cross-references

- [`../patterns/missing-dependency-ux.md`](../patterns/missing-dependency-ux.md)
  — the normative contract.
- [`../patterns/service-to-service-auth.md`](../patterns/service-to-service-auth.md)
  — the `@openparachute/scope-guard` precedent depcheck's packaging mirrors.
- vault#415 (`git-preflight.ts`) — the point-fix this generalizes.
- hub `cloudflaredInstallHint` (`src/cloudflare/detect.ts`) — the
  static-binary-over-distro lesson.
