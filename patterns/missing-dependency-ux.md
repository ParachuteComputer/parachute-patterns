# Missing-dependency UX

> When a module shells out to an external binary that isn't installed, the
> operator gets an **actionable install message** — never a raw `Executable
> not found in $PATH` crash. One wire shape, one message anatomy, three
> surfaces. The dependency registry + message formatter live in one shared
> lib (`@openparachute/depcheck`); every spawn site routes through it.

## The convention (TL;DR)

A Parachute module spawns external binaries (`git`, `tail`, `tar`,
`systemctl`, `launchctl`, `ffmpeg`, `whisper`, `claude`, …). When the binary
is absent, the module must:

1. **Preflight** existence before the spawn (`ensureExecutable`), AND
2. **Catch** post-spawn ENOENT (`rethrowIfMissing`) — belt-and-suspenders for
   the check-then-act race.

Both paths produce one `MissingDependencyError` carrying a `DepSpec`. That
error renders to the right surface:

- **CLI** → full install block + `Or ask your system administrator…` trailer
  on stderr, exit 1 (ANSI-coloured).
- **HTTP** → **503 Service Unavailable** with the
  [proxy-error-ui](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/proxy-error-ui.ts)
  wire shape, `error_type: "missing_dependency"`.
- **SPA** → the shared error component switches on `error_type` and renders a
  dedicated install card (copy-buttons, docs link).

The registry, the message formatter, and the ENOENT helpers are owned by
**`@openparachute/depcheck`** (built in `parachute-hub/packages/depcheck`,
mirroring the [`scope-guard`](https://github.com/ParachuteComputer/parachute-hub/tree/main/packages/scope-guard)
subpackage). Each module wires its own spawn sites; the strings live in one
place.

This pattern is **normative**. Even modules that don't (yet) adopt depcheck —
and external module authors — follow the wire shape, status code, and message
anatomy below.

## Why

Audit (2026-05-29, task #188) across the four committed-core repos + runner
found **77 external-binary spawn sites; 21 crash with a cryptic error when the
binary is missing.** Raw `Executable not found in $PATH: "git"` (HTTP 500,
`error_type: internal`) on a fresh Amazon Linux EC2 box; `tail` / `tar` /
`systemctl` / `launchctl` in the vault CLI; scribe's transcription providers
(`whisper` / `ffmpeg` / `parakeet` / `onnx`); the supervisor's `startCmd`
showing a bare "failed."

Two prior incidents established the shape this pattern generalizes:

- **vault#415** — `git` missing on a git-less server leaked the raw spawn
  error through the import / sync / mirror paths. The fix
  ([`git-preflight.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/git-preflight.ts))
  introduced `GitNotInstalledError`, `ensureGitAvailable`, the
  `isGitNotFoundSpawnError` belt-and-suspenders heuristic, and the **503
  `git_not_installed`** mapping ahead of the generic `internal` catch. This
  pattern is that fix, generalized across every binary and module.
- **cloudflared** — hub's `cloudflaredInstallHint`
  ([`src/cloudflare/detect.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/cloudflare/detect.ts))
  learned the hard way that `sudo dnf install cloudflared` returns *"No match
  for argument: cloudflared"* on Amazon Linux 2023 — so the static-binary
  `curl` recipe is the reliable cross-distro path, and an unknown arch drops
  to the docs URL rather than fabricating a 404ing download.

The product owner's requirement (Aaron, 2026-05-29): **every missing-dependency
path gives an actionable "install it via `<OS commands>` / or ask your
sys-admin" message.**

## The wire shape

Aligned with the `{ error, error_type, error_description }` snake_case
convention already used in
[`proxy-error-ui.ts`](https://github.com/ParachuteComputer/parachute-hub/blob/main/src/proxy-error-ui.ts)
(and `api-modules-config.ts` etc.). The SPA discriminates on `error_type`, not
the numeric status.

```ts
interface MissingDependencyWire {
  error: "missing_dependency";
  error_type: "missing_dependency";
  /** The full interactive:false install block — ANSI + sysadmin trailer STRIPPED.
   *  Always present; the universal fallback for any consumer that doesn't
   *  special-case error_type. */
  error_description: string;

  /** Structured fields so a rich consumer (SPA) can render its own card. */
  binary: string;                     // "git", "ffmpeg", "tail", …
  why: string;                        // "import a repo", "transcode audio", …
  docs_url: string;                   // ALWAYS present
  install: {
    darwin?: string;                  // e.g. "brew install git"
    linux?: string;                   // distro lines and/or a curl recipe
    generic?: string;                 // fallback when platform is unknown
  };
  /** Foundational deps only — replaced by an altHint for optional provider deps. */
  sysadmin_hint?: string;             // "Or ask your system administrator to install it for you."
}
```

### HTTP status = 503

**503 Service Unavailable**, not 424. This matches the `proxy-error-ui.ts`
precedent (upstream-starting / unreachable already use 502/503) and vault#415's
`git_not_installed` → 503 mapping. RFC 9110: 503 = "the request can't be served
right now; a dependency is missing — fix it and retry." The SPA and CLI
discriminate on `error_type`, never on the numeric code.

## The 5-part message anatomy

Every rendered message is built from these parts, in order. The formatter
(`formatMissingDependency`) owns the assembly so the shape never drifts:

1. **The problem line.**
   `<binary> is required to <why>, but it was not found on PATH.`
   e.g. `ffmpeg is required to transcode audio, but it was not found on PATH.`

2. **The install block.** An `Install it:` header, then OS-specific lines (see
   *show all distro lines* below).

3. **The docs URL.** Always present — the durable reference even when the
   install lines don't fit the operator's box.

4. **The sysadmin trailer** (foundational deps): the line Aaron explicitly
   asked for —
   `Or ask your system administrator to install it for you.`
   On **every foundational** dependency.

5. **For `optional: true` provider deps, part 4 is REPLACED by an `altHint`** —
   e.g. `…or switch transcription provider (PARACHUTE_SCRIBE_PROVIDER).` An
   operator who can't install `whisper` has a product-level escape hatch a
   sysadmin can't provide, so the sysadmin trailer would be the wrong advice.

## The "show all distro lines, don't detect" rule

When the platform is known, **lead with that OS's line but STILL list the
others.** Operators routinely SSH into a box the formatter mis-detects
(containers, cross-arch, an env that lies about `process.platform`); it's
cheaper to print three lines than to gamble on one. This is the vault
git-preflight precedent — `GitNotInstalledError`'s message names `dnf` /
`apt-get` / `brew` all at once rather than detecting the distro.

When the platform is **unknown**, show all families + the docs URL.

```
Install it:
  macOS:          brew install ffmpeg          ← led with (detected darwin)
  Debian/Ubuntu:  sudo apt-get install ffmpeg
  Fedora/RHEL:    sudo dnf install ffmpeg
  Docs:           https://ffmpeg.org/download.html
```

## The "static binary over distro package" rule

A `linuxBinaryUrl` curl recipe **WINS** over distro packages when the DepSpec
sets it. The cloudflared incident is the canonical lesson: `dnf install
cloudflared` returns *"No match for argument: cloudflared"* on Amazon Linux
2023, so a distro line that *looks* right actively misleads. When a static
binary release exists, prefer it:

```
Install it (static binary — works across distros):
  curl -L -o /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  sudo chmod +x /usr/local/bin/cloudflared
```

**Never fabricate a 404ing URL for an unknown arch.** If the DepSpec can't map
the host arch to a real release artifact, drop the curl recipe and fall back to
the docs URL — same as `cloudflaredInstallHint` returns the docs link for an
unrecognized arch.

## Belt-and-suspenders: preflight AND catch

Every spawn site does **both**:

```ts
// 1. Preflight — fail fast with the friendly error before spawning.
ensureExecutable(GIT_DEP);            // throws MissingDependencyError if `which git` is empty

// 2. Catch — covers the check-then-act race (binary removed between check and spawn,
//    or a nested spawn we didn't preflight).
try {
  await Bun.spawn(["git", "clone", url]);
} catch (err) {
  rethrowIfMissing(err, GIT_DEP);     // ENOENT → MissingDependencyError; else re-throw
  throw err;
}
```

`ensureExecutable` is the `ensureGitAvailable` shape generalized; `rethrowIfMissing`
is `isGitNotFoundSpawnError` generalized. Neither alone is sufficient: the
preflight gives the best error before any work starts; the catch closes the
race and covers spawn sites buried in libraries you can't preflight.

## Three-surface degradation

| Surface | How it renders | sysadmin trailer | ANSI |
|---|---|---|---|
| **CLI** | `formatMissingDependency(spec, { interactive: true })` → stderr, exit 1. Full 5-part block. | ✅ present | ✅ coloured |
| **HTTP** | 503 + `toWire(spec)`. `error_description` is the `interactive: false` block. | ❌ **stripped** | ❌ stripped |
| **SPA** | Shared error component switches on `error_type === "missing_dependency"` → dedicated install card (copy-buttons per OS line, docs link, muted hint). Falls back to `error_description` verbatim. | (rendered as muted hint) | n/a |

Why the HTTP wire **strips** the sysadmin trailer and ANSI: a daemon-log
reader **is** the sysadmin. Telling the person reading the server log to "ask
your system administrator" is circular; and ANSI escapes are noise in a log
file or a JSON field. The SPA re-adds the human-facing affordances (copy
buttons, the muted hint) from the structured fields.

**The SPA fallback is load-bearing.** The component renders the dedicated card
*only* when it recognizes `error_type`; for any unrecognized type — or an older
bundle that predates this pattern — it falls back to printing
`error_description` verbatim. That string is always a complete, human-readable
message, so a stale SPA degrades to "correct but plain," never to "blank box."

## Foundational vs optional

The `DepSpec` carries `optional?: boolean` + `altHint?: string`:

- **Foundational** (`git`, `tail`, `tar`, `systemctl`, `launchctl`, `ffmpeg`)
  — the operation cannot proceed without it; there's no product-level
  alternative. → **sysadmin hint** (message part 4).
- **Provider-style / optional** (`whisper`, `onnx`, `parakeet`, `claude`) — a
  swappable backend; the operator can pick a different one. → **altHint**
  replaces the sysadmin trailer (message part 5). `ffmpeg` is foundational
  *within* a provider that needs it even though the provider itself is
  optional — the distinction is "is there an alternative the operator
  controls," not "is the parent feature optional."

## The canonical implementation: `@openparachute/depcheck`

The shared lib owns:

- **`DepSpec`** — `{ binary, why, docsUrl, install: { darwin?, linux?, generic? }, linuxBinaryUrl?, optional?, altHint? }`.
- **The registry** — one `DepSpec` per known binary, keyed by binary name. The
  single source of truth for install strings. No module hand-syncs them.
- **`ensureExecutable(spec, which = Bun.which)`** — preflight; throws
  `MissingDependencyError`. `which` is a test seam.
- **`rethrowIfMissing(err, spec)`** — ENOENT heuristic; re-throws as
  `MissingDependencyError`, passes everything else through.
- **`formatMissingDependency(spec, { interactive })`** — the 5-part assembler.
- **`toWire(spec)`** — the `MissingDependencyWire` builder (503 body).

```ts
import { ensureExecutable, rethrowIfMissing, toWire } from "@openparachute/depcheck";
```

The lib is the **engine, not the policy** — same shape as scope-guard (the lib
matches scopes; per-service vocabularies stay in each service). DepSpecs for
binaries unique to one module live with that module and register at import; the
registry holds the cross-cutting foundational ones (`git`, `tail`, `tar`, …).

**Every NEW spawn site, in any module, must route through `ensureExecutable` +
`rethrowIfMissing`.** Hand-rolling a bespoke install string in a new spawn site
is the drift this pattern exists to prevent. The audit script
([`scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh)) flags
modules carrying their own `brew install` / `apt-get install` / `dnf install`
/ `Executable not found` literals outside depcheck.

## Patterns check (governance rule 3)

Reviewers: when a PR adds or touches an external-binary spawn site, verify it
(a) preflights with `ensureExecutable`, (b) catches with `rethrowIfMissing`,
(c) maps the HTTP path to 503 + `error_type: "missing_dependency"`, and (d)
adds no hand-synced install strings outside `@openparachute/depcheck`. A new
foundational binary needs a registry DepSpec, not an inline message.

## History

- **2026-05-29** — established (task #188). Generalizes vault#415's
  `git-preflight.ts` (the 503 `git_not_installed` shape) and the hub
  `cloudflaredInstallHint` static-binary-over-distro lesson. Adoption tracked
  in [`migrations/2026-05-29-missing-dependency-ux.md`](../migrations/2026-05-29-missing-dependency-ux.md).

## Related patterns

- [`service-to-service-auth.md`](./service-to-service-auth.md) — the other
  shared-lib precedent (`@openparachute/scope-guard`); depcheck mirrors its
  packaging shape.
- [`report-contract.md`](./report-contract.md) — structured-not-narrative
  shape, the same instinct applied to agent reports.
- [`design-system.md`](./design-system.md) — the SPA error card lives in the
  shared error component this pattern hooks `error_type` into.
