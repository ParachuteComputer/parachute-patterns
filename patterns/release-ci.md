# Release CI — tag-triggered publish to npm + ghcr.io

> Pre-1.0 Parachute repos publish via GitHub Actions on git tag push,
> not via manual `npm publish`. One workflow per repo, same shape
> across all of them. Pilot in [parachute-hub#359](https://github.com/ParachuteComputer/parachute-hub/pull/359);
> roll out to vault / scribe / app / runner follows.

## The convention (TL;DR)

Every committed-core Parachute repo has `.github/workflows/release.yml`
that triggers on `v*` tag push. Three jobs:

1. **`test`** — runs the repo's typecheck + test suite. Blocks publish.
2. **`publish-npm`** (depends on `test`) — publishes to npm with
   provenance attestation. Dist-tag auto-detected from tag string:
   `-rc.` substring → `rc`, else → `latest`.
3. **`publish-image`** (depends on `test`, runs in parallel with
   `publish-npm`; only where applicable — modules with a container
   image artifact) — builds the Dockerfile, pushes to
   `ghcr.io/parachutecomputer/<repo-name>` with tags `:rc` / `:stable` /
   `:v<X>.<Y>.<Z>[-rc.<N>]`.

Release flow becomes:

```sh
# 1. Code-touching PR merges to main with rc.N bump
# 2. Operator pulls latest main, pushes a matching tag
git pull --ff-only
VERSION="v$(bun -e "console.log(require('./package.json').version)")"
git tag "$VERSION" && git push origin "$VERSION"
# CI takes over: tests → publishes
```

## Why tag-triggered (not push-to-main)

- **Tag = explicit release signal.** Merges to main don't auto-publish;
  the tag is the unambiguous "ship this" trigger.
- **Tag itself is the audit trail.** What was released and when is
  visible via `git tag` + GitHub's tag UI. No need to cross-reference
  npm registry timestamps with git commits.
- **Preserves a deliberate human gate** (you push the tag when you mean
  to ship) **without the per-publish 2FA prompt** that gates remote
  work. Operators can release from anywhere.
- **Matches Render auto-deploy semantics:** Render watches main and
  redeploys on every commit. CI release is independent — only fires
  when a tag points at a commit.

## Why ghcr.io alongside npm

Image-based deploy targets (image-pinned `:stable` and `:rc` tags in a
Render blueprint, future cloud offerings, etc.) need pre-built container
images. ghcr.io is:

- **Free for public images.**
- **Integrated with GitHub Actions** — auth via the runner's
  auto-provisioned `GITHUB_TOKEN`, no separate secret.
- **Provenance-friendly** — image labels include source git ref + commit,
  auditable supply chain.

The image artifact exists even if no deploy target is currently using it.
Lets future image-pinned `render.yaml` variants land as a doc/yaml
change, not an infra change.

## Operator one-time setup per published package

1. **npm Trusted Publisher.** For each published package (one per `package.json` in the repo that isn't `private: true`):
   - npmjs.com → the package's Settings page → "Trusted Publishers" section
   - Add publisher: GitHub Actions
   - Organization `ParachuteComputer`, Repository = the repo it ships from, Workflow filename `release.yml`, Environment blank

   Multi-package repos (e.g. parachute-hub ships hub + scope-guard) configure ONE rule per published package, all pointing at the same `release.yml` file.

   No `NPM_TOKEN` secret needed — the workflow uses OIDC. Requires `permissions: id-token: write` at the job level (already in the canonical workflow) AND npm CLI 11.5+ (use `actions/setup-node@v4` with `node-version: '24'`; node 20 LTS ships only npm 10 which lacks OIDC support).

2. **ghcr.io permissions.** No secret needed (the workflow uses
   `GITHUB_TOKEN`), but the first push creates the package as **private
   by default**. Toggle visibility to **Public** at
   `https://github.com/orgs/ParachuteComputer/packages/container/<repo>/settings`
   after first push — otherwise unauthenticated `docker pull` (Render,
   etc.) 403s.

## Workflow shape (canonical)

The hub workflow is the reference. Other repos adapt:

- **Test command** matches the repo's `package.json` test script.
- **Build step.** If the package needs a build (e.g. hub builds the SPA
  via `prepack`), the `prepack` hook in `package.json` handles it
  automatically when `npm publish` runs — no explicit step in CI needed.
- **Image job is omitted** for modules that don't ship a container
  image (most don't — only hub does today, since it's the deploy
  surface). Vault, scribe, app, runner publish to npm only.

```yaml
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'
      - 'v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+'

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  test:
    # ... bun test ./src etc.

  publish-npm:
    needs: test
    permissions:
      contents: read
      id-token: write   # provenance
    steps:
      # ... bun install, setup-node, version-vs-tag guard, npm publish

  publish-image:   # hub only (for now)
    needs: test
    permissions:
      contents: read
      packages: write   # ghcr.io
    # ... docker buildx + push with :rc / :stable tag derivation
```

## The version-vs-tag guard

Every `publish-npm` job runs a guard before the publish step:

```sh
PKG_VERSION=$(node -p "require('./package.json').version")
TAG_VERSION="${GITHUB_REF_NAME#v}"
[ "$PKG_VERSION" = "$TAG_VERSION" ] || { echo "::error::drift" && exit 1; }
```

Prevents a "tagged `v0.5.13` but package.json still says `0.5.13-rc.32`"
mistake from silently publishing under the wrong version.

## Tag pattern details

The `on.push.tags` filter accepts:

- `v[0-9]+.[0-9]+.[0-9]+` — matches `v0.5.13`, `v1.0.0`, etc.
- `v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+` — matches `v0.5.13-rc.32`, etc.

The runtime bash check (`if [[ "$GITHUB_REF_NAME" =~ -rc\. ]]`)
disambiguates rc-vs-stable for the dist-tag and the image-tag derivation,
not the workflow trigger.

## Examples

- [`parachute-hub/.github/workflows/release.yml`](https://github.com/ParachuteComputer/parachute-hub/blob/main/.github/workflows/release.yml)
  — canonical reference implementation (three jobs incl. publish-image).
- [`parachute-hub/RELEASING.md`](https://github.com/ParachuteComputer/parachute-hub/blob/main/RELEASING.md)
  — operator-facing release flow doc (per-repo template).

## Interaction with other rules

This pattern operates under [`governance.md`](./governance.md) Rule 2
(RC versioning) and Rule 5 (CHANGELOG discipline). Specifically, the
doc-only-exemption in Rule 2 means some merges never produce a tag,
which per Rule 5 also means they produce no CHANGELOG entry — these
merges get rolled into the next rc.N or stable bump's CHANGELOG section.
No special-casing needed.

## Rollout

Pilot: parachute-hub (landed 2026-05-24, hub#359). Per-repo rollout
(vault / scribe / app / runner) tracked in
[parachute-patterns#91](https://github.com/ParachuteComputer/parachute-patterns/issues/91).

Each rollout adapts hub's workflow + RELEASING.md, plus an `NPM_TOKEN`
secret added by the operator before the first tag push. `parachute-app`
publishes from `packages/app-host` (multi-package workspace); other
modules are single-package. None except hub need the `publish-image`
job today.

## History

- **2026-05-24** — pilot landed in parachute-hub (hub#359). Rule 2
  updated to describe tag-triggered release instead of manual
  `npm publish`. Pattern doc landed alongside.
