# Context in payload

## Convention

When one Parachute service triggers another and the receiving service
needs *contextual* knowledge (e.g. "who are the people the speaker
typically talks about?"), the **provider** pre-fetches that context
and ships it **inline in the payload**. The **consumer** is stateless
with respect to it — the consumer never calls back into the provider
to look anything up.

The reference example: vault → scribe transcription. Vault knows the
speaker's people / projects / aliases. Vault attaches a `context.json`
part to the audio upload. Scribe uses it as-is for proper-noun
correction in cleanup, then forgets about it.

## Why

- **No backchannel.** A consumer that calls back into the provider
  during request handling creates an inverted dependency, an extra
  round-trip per request, and a credential-management problem on
  the consumer side. Sending context inline collapses all three.
- **Stateless consumers.** Scribe doesn't know what a "vault" is.
  Future consumers (transcription from a microphone app, from a phone
  recording, from a browser extension) ship the same shape from
  whatever source they have. The receiver doesn't care where the
  entries came from.
- **Provider owns the predicate.** The provider (which has the data)
  decides what's relevant — by tag, by metadata whitelist, by recency
  if it grows that knob — and never exposes its query language to the
  consumer.
- **Caller-agnostic shape.** The shape is dumb on purpose:
  `{entries: [{name, ...whitelisted_fields}]}`. A receiver written
  for vault works for any future provider that emits the same shape.

## Shape

### What the provider sends

```json
{
  "entries": [
    { "name": "Margaret",         "summary": "Close friend",   "aliases": ["Marg"] },
    { "name": "Learn Vibe Build", "summary": "6-week cohort",  "aliases": ["LVB", "Learn by Build"] }
  ]
}
```

- `name` (required) — canonical display form, typically the source's
  basename (a note path's filename without extension, in vault's case).
- Other fields — whitelisted metadata carried through unchanged. The
  consumer treats these as opaque strings/values; only `name` has
  cross-service semantic meaning.

### How the provider attaches it

Multipart: a `context` part with `content-type: application/json`.

```ts
form.append(
  "context",
  new Blob([JSON.stringify(payload)], { type: "application/json" }),
  "context.json",
);
```

JSON-bodied requests inline `context: {...}` as a top-level field.
Trigger config in vault selects either shape via
`send: "attachment" | "json"`.

Empty payload → **no part attached**. Don't send a zero-entries part
the receiver would have to special-case.

Reference:
[`parachute-vault/src/context.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/src/context.ts)
(`fetchContextEntries`, `appendContextPart`).

### Provider predicate config

The provider's user-facing config picks what to include. Vault's
shape (in `vault.yaml` / trigger `action.include_context`):

```yaml
include_context:
  - tag: person
    exclude_tag: archived
    include_metadata: [summary, aliases]
  - tag: project
    include_metadata: [summary, aliases]
```

Each predicate is a query (scoped by `tag`, optionally excluding
`exclude_tag`) plus a metadata-key whitelist. Fields not in
`include_metadata` are dropped before send.

### How the consumer parses it

Tolerant parser. Malformed payload → log + fall through to "no
context", **not** 400 the whole request.

```ts
// parachute-scribe/src/context.ts
export function parseContextPayload(raw: unknown): ContextPayload | null {
  // Accepts string OR pre-parsed object; null on malformed.
  // Filters entries that lack a non-empty `name`.
}
```

Reference:
[`parachute-scribe/src/context.ts`](https://github.com/ParachuteComputer/parachute-scribe/blob/main/src/context.ts)
(`parseContextPayload`, `buildProperNounsBlockFromEntries`).

The consumer's job once parsed is shape-driven, not provider-aware.
Scribe renders entries into a "Known names in this context" prompt
block; a different consumer would render them differently. The
provider doesn't try to format for the consumer.

## Rules

- **Provider pre-fetches; consumer never calls back.** This is the
  core invariant. A consumer that reaches into the provider is
  outside the pattern — refactor or document why.
- **Empty payload → no part / no field.** Don't send `{entries: []}`.
  Don't send a multipart part with `null`. Absence is the empty case.
- **`name` is required, everything else is whitelisted opaque.**
  Adding a new field is allowed (consumers ignore unknown keys);
  removing or renaming `name` is a breaking change.
- **Provider config controls what's sent.** Don't bake "always send
  people + projects" into provider code. The trigger / worker config
  declares predicates explicitly so the operator can see it.
- **Consumer parser is tolerant.** Malformed entries are dropped; a
  malformed payload as a whole produces "no context" rather than a
  request failure. Transcription should not fail because some unrelated
  metadata key contained bad UTF-8.
- **Same shape across providers.** Whatever ships next as a
  context-providing service must ship the *exact* same JSON shape.
  Don't fork "vault context" into a vault-specific schema; the
  shape is the contract.

## Where this applies

- **`parachute-vault` → `parachute-scribe`** — reference pair. Vault
  PR
  [#156](https://github.com/ParachuteComputer/parachute-vault/pull/156)
  ("feat(scribe): vault is now the context provider for
  transcription"). Trigger config supports `include_context`; the
  transcription worker reads `transcription.context` from `vault.yaml`
  and includes the same payload.
- **`parachute-scribe`** — implements the consumer side. Knows
  nothing about vault. Any future module sending audio with a
  `context` part gets the same proper-noun-correction behavior.
- **Future modules** — any service that takes context-relevant
  free-text (cleanup, summarization, classification, retrieval) is a
  candidate consumer. Adopt the same `entries[]` shape; let any
  context-providing module front it.

## What this isn't

- **A general-purpose retrieval API.** This pattern carries
  pre-selected, narrowly-scoped entries (a few dozen names, not a
  whole vault). For arbitrary retrieval, use MCP — the consumer
  becomes an MCP client and pulls what it needs, with auth.
- **An auth or trust mechanism.** The context payload is in the
  request body, alongside the actual workload. It piggybacks on
  whatever inter-service auth
  ([`service-to-service-auth.md`](./service-to-service-auth.md))
  already protects the request.

## Open questions

- **Versioning.** Today there's no `version` field on the payload —
  shape is "v1 forever." If/when a v2 lands (e.g. typed entries,
  embedding vectors), we'll need a discriminator. Defer until the
  second shape is real.
- **Size limits.** No explicit cap today. A 500-entry vault is fine
  on loopback; 50,000-entry would be a problem. Provider-side
  predicates are the throttle for now (operators choose narrow tags).
  A future hard cap with truncation order may be needed.
- **Ordering / ranking.** Today predicates run in declaration order;
  duplicates dedupe by first match. No relevance scoring. If consumers
  start to care (most-recent-first, query-similarity-first), the
  predicate shape grows.
