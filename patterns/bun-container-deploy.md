# Bun + container deploy

> Running bun-based modules in containers with persistent disks (Render,
> Fly, Railway, generic Docker) has four non-obvious env-var
> requirements. Missing any one → install fails with cryptic `EACCES`.
> Plus a separate `Bun.spawn` env-inheritance gotcha that the env-var
> fix doesn't help with.

## The convention (TL;DR)

A bun-based module deployed to a container + persistent-disk setup
MUST set all four of these env vars, all pointing at paths on the
persistent disk:

| Var | What it controls | Default | Required value |
|---|---|---|---|
| `BUN_INSTALL` | Where `bun add -g` puts PACKAGES | `$HOME/.bun` | A path on your persistent disk (e.g. `/parachute/modules`) |
| `BUN_INSTALL_BIN` | Where `bun add -g` puts BIN SYMLINKS | `/usr/local/bin/` (system path) | Same root as `BUN_INSTALL` (e.g. `/parachute/modules/bin`) |
| `TMPDIR` | Where bun extracts tarballs before move-into-place | `/tmp` (container overlay) | A path on the SAME filesystem as `BUN_INSTALL` (e.g. `/parachute/tmp`) |
| `PATH` | Where the shell looks for installed binaries | system PATH | Extended with `$BUN_INSTALL_BIN` so installed modules are findable |

And separately: every `Bun.spawn` site that runs a child process which
needs env vars MUST pass `env: process.env` explicitly. Bun does not
inherit by default.

## Why each one matters

**`BUN_INSTALL`** — without it, bun installs packages to `$HOME/.bun/`
which lives on the container's overlay filesystem. Every redeploy
wipes user-installed modules. Failure mode: modules disappear on
redeploy.

**`BUN_INSTALL_BIN`** — separate from `BUN_INSTALL`; controls where
bin symlinks land. Defaults to `/usr/local/bin/` (root-owned system
path). Non-root container user can't write there → `symlinkat() = -1
EACCES`. Surfaces as `Failed to link <package>: EACCES`. This was the
first load-bearing bug for hub on Render. (A second load-bearing bug —
the `mkdir`-as-root pitfall, see below — was found later via live SSH
into a fresh Render deploy.)

**`TMPDIR`** — bun extracts tarballs into `TMPDIR`, then `rename()`s
files into `$BUN_INSTALL/install/global/node_modules/`. If `TMPDIR`
and `BUN_INSTALL` are on different filesystems (Render's persistent
disk vs container overlay), `rename()` fails with `EXDEV`
(cross-mount). Bun has a fallback path but it's unreliable. Failure
mode: `info: cannot move files from tempdir: RenameAcrossMountPoints,
using fallback` → `EACCES`.

**`PATH`** — hub + spawned children resolve module binaries via PATH.
If `BUN_INSTALL_BIN` isn't in PATH, calls like `parachute-vault serve`
fail with command-not-found. Failure mode: child spawn fails with
`ENOENT` or "command not found."

## The `Bun.spawn` env-inheritance gotcha

Separate from the env-var setup: `Bun.spawn` doesn't inherit
`process.env` by default. Pass `env: process.env` at every spawn site
if your child process needs any env vars (which it almost always
does). Without this, even with the four env vars above set in the
parent, subprocess `bun add` doesn't see them and falls back to
defaults.

```typescript
// Wrong — child has empty env
Bun.spawn(["bun", "add", "-g", pkg]);

// Right
Bun.spawn(["bun", "add", "-g", pkg], { env: process.env });
```

This was hub#352 specifically. The previous four PRs in the chain set
all the right env vars in the Dockerfile, but the child `bun add`
process didn't see them — so they had no effect until the spawn-site
fix landed.

## Diagnosis flow when an install fails

1. `bun add -g --verbose <package>` from a shell on the container —
   see if `RenameAcrossMountPoints` appears (`TMPDIR` issue) or which
   syscall fails.
2. `strace -f -e trace=openat,symlinkat,linkat bun add -g <package>` —
   find the `EACCES` syscall and what path it's targeting.
3. Check `BUN_INSTALL_BIN` — `echo $BUN_INSTALL_BIN`. If unset or
   pointing at `/usr/local/bin/`, that's the issue.
4. Confirm `TMPDIR` is on the same filesystem as `BUN_INSTALL` via
   `df -T $BUN_INSTALL $TMPDIR`.

## Reproducing locally (faster than the deploy platform)

```bash
docker volume create test-disk
docker run --rm \
  -v test-disk:/parachute \
  --entrypoint /bin/sh \
  your-image -c "bun add -g cowsay"
```

The docker volume mount creates a separate filesystem at `/parachute`
— same shape as Render's persistent disk. Iterating locally is ~10×
faster than iterating on the actual deploy. The hub#349-#354 chain
was bisected in ~5 minutes locally once the docker-volume reproduction
was set up. (The final load-bearing bug, hub#355, was a class of
failure the local repro missed — see the mkdir-as-root pitfall below
— and required live SSH into a fresh Render deploy to catch.)

## Reference: parachute-hub's Dockerfile env block

```dockerfile
ENV PARACHUTE_HOME=/parachute \
    BUN_INSTALL=/parachute/modules \
    BUN_INSTALL_BIN=/parachute/modules/bin \
    TMPDIR=/parachute/tmp \
    PATH=/parachute/modules/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Plus an entrypoint script that recursively chowns these paths to the
non-root user at every startup (so the persistent disk, which mounts as
root-owned, becomes writable by the runtime user).

## Pitfall: `mkdir` as root leaves the parent root-owned

The entrypoint runs as root, then `exec gosu bun "$@"` drops privileges.
The temptation: an early version of this pattern chowned `/parachute`
only on first boot (when it's still root-owned), then ran `mkdir -p
/parachute/modules/bin` and `chown -R bun:bun /parachute/modules/bin`.

Looks fine. Isn't. The `mkdir -p` runs **as root**, so it creates
`/parachute/modules` (the parent) AS ROOT. The subsequent `chown -R` on
`/parachute/modules/bin` only fixes the leaf. The `/parachute/modules`
parent stays `drwxr-sr-x root:bun` permanently — bun-user can list it
but can't `mkdir /parachute/modules/install`, which is exactly what
`bun add -g` needs to do. The first install fails with
`error: An internal error occurred (AccessDenied)`.

The fix: never trust the conditional-chown shortcut. **Always recursive-
chown the bun-write paths on every start**, no guards:

```sh
mkdir -p /parachute/tmp /parachute/modules/bin
chown -R bun:bun /parachute/tmp /parachute/modules
```

Cheap on a 1GB persistent disk (no measurable startup latency),
idempotent (chown on an already-correct tree is a no-op), and catches
both this pitfall AND any other root-write that an operator's debug
attempts might have introduced (e.g. a shell `bun add` without `gosu`).

Diagnostic when this is the bug: `ls -la /parachute/modules` shows the
parent owned by root, not bun.

## Cross-references

- [`parachute-hub/Dockerfile`](https://github.com/ParachuteComputer/parachute-hub/blob/main/Dockerfile)
  — canonical implementation of the env block.
- [`parachute-hub/docker-entrypoint.sh`](https://github.com/ParachuteComputer/parachute-hub/blob/main/docker-entrypoint.sh)
  — the entrypoint chown pattern.
- [hub#349](https://github.com/ParachuteComputer/parachute-hub/pull/349)
  — the issue trail; chain of six PRs to land the full fix:
  - #349 — opening issue
  - #350 — entrypoint chown stub
  - #351 — `TMPDIR` on persistent disk
  - #352 — `Bun.spawn { env: process.env }` (env-inheritance fix)
  - #353 — bootstrap-token banner (UX polish surfaced during diagnosis)
  - #354 — `tini -g` for signal forwarding, plus `BUN_INSTALL_BIN`
    folded in (was the first load-bearing fix)
  - #355 — `mkdir`-as-root pitfall (the second + final load-bearing fix)
- [hub#352](https://github.com/ParachuteComputer/parachute-hub/pull/352)
  — the `Bun.spawn { env: process.env }` fix specifically.
- [hub#355](https://github.com/ParachuteComputer/parachute-hub/pull/355)
  — the mkdir-as-root pitfall fix; diagnosed via live SSH into a fresh
  Render deploy.
- [patterns#85](https://github.com/ParachuteComputer/parachute-patterns/issues/85)
  — open audit: verify `Bun.spawn` passes `env: process.env` across
  vault / scribe / app / runner.

## History

- **2026-05-23 → 2026-05-24** — bugs discovered + fixed across
  hub#349-355. Each PR fixed a real bug but missed the load-bearing
  one; the final root cause (mkdir-as-root leaves parent root-owned)
  was found via live SSH into a fresh Render deploy after the env-var
  chain had landed.
- **2026-05-24** — pattern doc landed so the next module deployed to
  a container + persistent disk doesn't walk the same path. Updated
  same day with the mkdir-as-root pitfall callout.
