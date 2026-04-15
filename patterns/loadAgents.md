# `loadX` source-tagged-union convention

## Convention

Any Parachute module that loads "a list of configurable things" from one of
several possible sources exposes the same shape: a tagged union on `type`,
with interchangeable implementations that return a common data form.

```ts
type Source<T> =
  | { type: "dir"; path: string }
  | { type: "vault"; tag: string; vault: VaultClient }
  | { type: "inline"; items: T };

async function loadX(source: Source<T>): Promise<T>;
```

## Why

- **Modularity stays opt-in.** A module works standalone (`dir` or `inline`)
  and gains vault powers by swapping the source value. No runtime imports
  change; no build-time dependency is added.
- **One handshake for every module.** Scribe's proper nouns, Agents'
  definitions, Daily's templates, Narrate's voice configs — all have the
  same decision ("where's this list coming from?") and same shape.
- **Composability with config.** The source is a plain data value, so it's
  trivially passed from CLI flags, env vars, or a runtime `config` object.

## Where this applies

| Module | `T` | Tag for vault source |
|---|---|---|
| `@openparachute/agent` | agent markdown map (`Record<path, md>`) | `agent-definition` |
| parachute-scribe | proper-noun list | `scribe/proper-noun` |
| parachute-narrate | voice configs | TBD |
| parachute-daily | capture templates | TBD |

Today the most complete implementation is in parachute-agents:
[`src/agent-sources.ts`](https://github.com/ParachuteComputer/parachute-agents/blob/main/src/agent-sources.ts).
Other modules should port that shape as they add vault integration.

## Rules

- **Common data shape.** Every source branch returns the same `Promise<T>`.
  The caller never knows which branch produced it.
- **Graceful degradation.** The `vault` branch must not hard-fail a boot —
  it logs and returns an empty-ish default so the module still starts.
  Hard failures belong to the caller that chose the vault source.
- **Default to standalone.** When no source is explicitly configured, pick
  the local one (`dir` or `inline`). No surprise network calls.
- **Type discriminant is `type`.** Don't invent `kind`, `source`, `from`.
  `type` matches every other tagged union in the codebase.

## Open questions

- Do we want a shared `@openparachute/sources` package that provides the
  tagged-union helpers? Tempting, but currently the duplication across 2–3
  modules is a few lines each. Revisit when it's 5+ modules.
