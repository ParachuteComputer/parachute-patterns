# Bootstrap on first boot

> A host module that mounts user-installable units (UIs, jobs, plugins)
> auto-installs configured defaults the first time it starts against an
> empty state — so a fresh install runs something useful out of the
> box, not an empty dashboard. After that, the operator owns the state
> and the bootstrap stays out of the way.

## The principle

The friend-deploy story for a host module is "`parachute install
<module>` → `parachute start <module>` → open the URL and see
something". If the second click lands on a blank "no <thing> installed
yet" page, the operator has to know which package to install next and
how to install it before the module justifies its presence. That's a
discovery cliff at the worst possible moment.

Bootstrap-on-first-boot closes the gap. The module ships with a
*default* set of units it knows are the right starting point; on first
boot, if the operator hasn't curated their own set, it installs them
via the same code path the admin "add" verb uses. After that, the
operator's state takes over — the bootstrap is a one-shot, not a
running default.

## When to use

- **Host modules that mount user-installable units.** Apps host UIs;
  a hypothetical runner could host default jobs; an MCP-server host
  could ship default tools. The module's value is "host these things"
  and the empty-state default is "host nothing," which obscures the
  module's job.
- **Friend-deploy / fresh-install scenarios.** Self-hosters spinning up
  the ecosystem from `parachute install` should hit a working surface
  on the first page load. Bootstrap removes the "now go install Notes"
  step.
- **When the default is clearly the right starting point.** For apps,
  Notes is the canonical first UI — every Parachute install benefits
  from it. The bootstrap codifies that recommendation as behavior.

## When NOT to use

- **The empty state is meaningful.** Vault should NOT auto-create a
  vault on first boot — operators may want zero vaults, or want to
  create the first one with specific naming. Empty-state-is-the-point
  modules don't bootstrap.
- **The default install has cost.** A multi-hundred-MB download, a
  config that touches operator infrastructure, anything destructive on
  failure — these are deliberate operator decisions, not defaults.
- **The expected first-boot is "configure from scratch."** Modules
  whose primary surface is operator-authored content (e.g. a notes
  editor with no built-in defaults) shouldn't seed a placeholder.

## The contract

The shape is the same across host modules:

```jsonc
// <module>/config.json
{
  "bootstrap_default_<things>": {
    "enabled": true,
    "<things>": ["@openparachute/notes-ui"]
  }
}
```

- **`enabled: boolean`** — operator kill-switch. Defaults to `true`.
  Setting `false` is the "I'll curate this myself" knob.
- **`<things>: string[]`** — the canonical defaults the module ships
  with. For apps, this is `["@openparachute/notes-ui"]`; future
  committed-core UIs may join. The list is operator-overridable so
  forks / private deployments can swap in their own defaults.

**First-boot detection is state-based, not config-based.** The trigger
is "the target install dir is empty," not "a `first_boot_done` flag
hasn't fired yet." Reasoning: a flag-based trigger has subtle modes
the operator can't recover from — they install the default, delete
it deliberately, and on next restart the bootstrap re-fires (flag
already cleared) or doesn't (flag stuck), neither of which matches
intent. State-based is honest: "empty → bootstrap, non-empty →
operator owns it."

**Failures are best-effort.** Network down, package unpublished,
malformed bundle — each per-unit failure logs a warning and the rest
proceed. A failed bootstrap does NOT block daemon startup: the daemon's
primary job is "host whatever's in the install dir already," and the
empty-dir case degrades to "host nothing," which is the same state
the operator would see without the bootstrap feature at all.

## Reference implementation

[`parachute-surface/packages/app-host/src/bootstrap.ts`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/app-host/src/bootstrap.ts):

```ts
export type BootstrapOpts = {
  config: AppConfig;
  uisDir: string;
  add: BootstrapAddFn;          // closure over the admin add path
  npmFetch?: typeof fetchNpmPackage;
  logger?: Pick<Console, "log" | "warn" | "error">;
};

export type BootstrapResult = {
  bootstrapped: string[];                          // npm specs added
  skipped: Array<{ pkg: string; reason: string }>;
  failed: Array<{ pkg: string; error: string }>;
  skipReason?: string;                             // whole-pass skip
};

export async function maybeBootstrapDefaultApps(
  opts: BootstrapOpts,
): Promise<BootstrapResult>;
```

Three load-bearing properties:

- **Pure function.** Takes config + dir + an `add` closure; the closure
  is the seam that decouples bootstrap from the admin handler's mutable
  state. Tests inject a fake `add`; production wires it to
  `addUiInternal`.
- **Per-spec independence.** The loop catches each `add` rejection,
  records it in `failed`, and continues. One bad package can't take
  down the rest.
- **Returns a summary, doesn't throw.** The caller logs
  `bootstrapped.length` defaults installed and moves on. The summary
  shape supports tests asserting on the post-bootstrap state without
  having to read the filesystem.

Wired in [`index.ts`](https://github.com/ParachuteComputer/parachute-surface/blob/main/packages/app-host/src/index.ts)
under `serve()` *after* HTTP starts listening and self-register has
stamped its row — bootstrap is fire-and-forget; daemon serves whatever
exists today while the bootstrap installs whatever should exist
tomorrow, then the admin `add` flow's in-place state-swap picks up
the new UIs without a restart.

## Idempotency

Re-running `serve` doesn't re-bootstrap, because the directory is no
longer empty. The only way to re-trigger is for the operator to remove
every installed unit (`rm -rf uis/*`) and restart — which is exactly
when re-bootstrapping is desired. No flag to clear, no state to
migrate. The behavior is the same on every cold start.

## Failure modes

**Note**: `<things>` in the table below is the array key for the
module's default units, e.g. `apps` for parachute-surface, `jobs` for
a future parachute-jobs.

| Condition | Behavior |
| --- | --- |
| `enabled: false` | Whole pass skipped, logged as `skipReason: "config.bootstrap_default_apps.enabled is false"`. |
| `<things>: []` | Whole pass skipped, logged as `skipReason: "<things> is empty"`. |
| Install dir non-empty | Whole pass skipped, logged as `skipReason: "uisDir is non-empty"`. |
| Network down / registry timeout | Per-spec `failed` entry with the underlying error; rest of list continues. |
| Package not on registry (404) | Per-spec `failed` entry with `not_found`; rest continues. |
| Package malformed (no `dist/`, missing manifest) | Per-spec `failed` with the validator's reason; rest continues. |

The visible symptom of a fully-failed bootstrap is "I see an empty
dashboard on first boot." The operator's recovery is the explicit
admin verb (`parachute-surface add @openparachute/notes-ui` or the SPA
"add" button) — same code path the bootstrap was trying to run, so
the manual retry surfaces the same error in the operator's terminal.

## Cross-references

- Shipped in
  [parachute-surface#7](https://github.com/ParachuteComputer/parachute-surface/pull/7)
  (Phase 2.1) on 2026-05-22, alongside the auto-provision-schema work
  that makes Notes' DCR-required schema appear in the vault on the
  same first boot.
- See [`module-self-registration.md`](./module-self-registration.md) —
  bootstrap runs *after* self-register, so the services.json row exists
  before the bootstrap stamps the post-bootstrap `uis` map.
- See [`module-protocol.md`](./module-protocol.md) — the "host module"
  shape (storage / runtime / discovery contracts) is the precondition
  for this pattern; bootstrap layers on top.
