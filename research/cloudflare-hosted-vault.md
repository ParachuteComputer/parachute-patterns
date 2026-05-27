# Cloudflare-hosted vault — research

> **Note (2026-05-09):** this doc predates vault v14 (2026-05-03). References to `_tags/*` notes as the source of `getTagDescendants` and to cache invalidation firing on `_tags/*` writes describe the pre-v14 architecture. The current data source is the `tags.parent_names` column; see [`patterns/tag-data-model.md`](../patterns/tag-data-model.md). The cloud-deployment reasoning here (DO-per-tenant + R2) is unaffected — the post-v14 cache mechanics are simpler, not different in shape. Preserved as research history.

> Companion research for Aaron's reconsideration of the cloud path: could we host the vault itself on Cloudflare's edge platform (Workers + D1 + Durable Objects + R2) as a low-cost, low-friction gateway to Parachute, instead of (or alongside) the "managed control plane + per-user Cloudflare Tunnel" v1 currently recommended in vault#199 / cloud-offering-sketch.md?
>
> Author: vault tentacle (Uni). Date: 2026-05-02.
>
> **Status:** research. Aaron decides; this surfaces options.

---

## 1. TL;DR

- **CF-hosted vault is technically viable today**, and one CF primitive — SQLite-backed Durable Objects — is an unusually clean fit. Per-DO SQLite is synchronous, in-thread, supports FTS5, GA in 2026. Maps onto vault's `BunSqliteStore` nearly line-for-line.
- **D1 is the wrong primitive.** D1 does not support FTS5 (no virtual tables). Vault's `searchNotes` depends on `notes_fts`. Picking D1 = rebuild search.
- **The right shape is "DO-per-tenant + R2 for attachments"** — what this doc calls **Shape γ**, what vault PR #99 prototyped before being parked.
- **Unit cost at 1k users: ~$0.015–0.05/user/month all-in** (Workers + R2 + DO duration + storage). At 100 users mostly inside the free tier; at 10k roughly $0.01–0.04/user/mo. Order-of-magnitude cheaper than every alternative considered.
- **Bun→V8-isolate is the load-bearing porting cost, not SQLite→DO or FS→R2.** Each has a Worker analog (fetch-handler, `crypto.subtle`, env bindings, Cron Triggers, DO storage), but the diff across `src/` is non-trivial. The just-shipped tag-scope cache (vault#241) actually fits *better* on per-DO state than it does on a stateless Worker.
- **Two parked PRs did most of the abstraction work.** PR #99 (`SqlDb` + `DoSqliteStore`) and PR #101 (`BlobStore` FS+R2). Closed without merge, branches preserved. Reviving them is Phase-0.
- **Product vs technical questions come apart.** CF-hosted-vault is a strong technical answer to "give early users a vault cheap and fast." It's a weaker answer to "preserve your-data-on-your-machine as the brand promise." Whether to pursue is positioning, not feasibility. The v3 plan (cloud hub first, cloud vault later) and "host vault on CF" answer different *when* questions.
- **Self-hosted parity preserved** via export/import — vault's Obsidian-import path becomes the migration tool. No lock-in.
- **Hub-offline = system-offline (vault#199 v2 §7.3) does not apply** if vault runs on CF. CF-hosted vault is always-reachable for agent calls regardless of the user's laptop. This *is* the win Aaron's framing implies.
- **Hidden costs are operational shape change** (Wrangler, Miniflare, CI/CD for Workers) **and a per-tenant DO management surface** (routing, provisioning, DO migration, backup-via-export). Modest numerically; meaningfully different from "ship a Bun binary."

---

## 2. Existing-research synthesis

### Settled

vault#199 v3 (the active recommendation): cloud is a paid Parachute Computer LLC tier; one billing relationship; provider-abstraction across VM-on-cheap-cloud (Hetzner/Render/Fly); **Phase 1 = Cloud Hub**, not Cloud Vault; multi-IDP from day one; parked PRs (#99 + #101) merge as ecosystem hygiene regardless of cloud shape.

cloud-offering-sketch (April-20): tenant-per-subdomain shape; lossless export/import (no vendor lock); vault's Store interface is the seam to swap engines; Notes PWA is static on CDN; identity federates from each origin to centralized `auth.parachute.computer`.

### Deferred / unresolved

- **Whether the cloud-vault data plane is D1 or DO-SQLite.** The April-20 sketch said "D1," vault#199 v1 §2 said DO-SQLite — they contradict. **This doc resolves it: DO-SQLite, not D1** (§3.2).
- **Multi-tenant routing concrete shape inside CF.** Mentioned at the level of "front-door Worker dispatches by hostname → DO ID = hash(user)"; Workers for Platforms not needed.
- **Cloud-hub → cloud-vault interaction once both exist.** v2 §7.4 named the shapes but didn't sequence them.
- **Pricing for Cloud Vault.** $20/mo Pro estimate not COGS-modelled for a CF-hosted vault.
- **"Your machine, your data" preservation via opt-in local replica.** Shape 4 (CRDT) assessed and parked.
- **Migration tooling specifics.** Asserted lossless; not designed.

This doc sharpens "concrete shape and cost of CF-hosted vault if we ship it" — i.e., Phase 3 (or earlier — see §8).

---

## 3. Cloudflare surface evaluation

### 3.1 Workers (the request handler)

Workers run as V8 isolates, not Node or Bun. Per-isolate memory cap **128 MB**; CPU per request **30s** on Paid (5 min upper bound); subrequest cap **10,000 per invocation** on Paid (vs 50 free); request body up to **100 MB** on Free/Pro plans, more on Business+. ([Workers limits](https://developers.cloudflare.com/workers/platform/limits/))

Pricing: **$5/mo minimum on Paid**, then 10M requests + 30M CPU-ms included; **$0.30/M requests** + **$0.02/M CPU-ms** beyond. Free tier is 100k requests/day. ([Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/))

Bun-specific APIs (`Bun.serve()`, `Bun.password`, `Bun.$`, `bun:sqlite`) do **not** run on Workers. Workers do support `node:fs` (in-memory virtual FS) and `node:http` since 2025-08-15+ compat dates with `nodejs_compat` flag. ([Node.js compat](https://developers.cloudflare.com/workers/runtime-apis/nodejs/), [npm packages on Workers](https://blog.cloudflare.com/more-npm-packages-on-cloudflare-workers-combining-polyfills-and-native-code/))

**Fit for vault**: Good as a request handler; bad as a stateful runtime. The CPU/memory caps are fine for vault's workload (an MCP query is microseconds; a vault-info call is ms). The hard constraint is *no persistent state between requests in the Worker itself* — which is why the vault's process must move to a Durable Object, not stay in the Worker.

### 3.2 D1 (SQLite-on-Cloudflare, managed)

D1 is SQLite at the SQL layer, but accessed over HTTP from the Worker (network roundtrip per query). Storage cap: **10 GB per database** on Paid (500 MB on Free), and "this limit cannot be increased." Statement size: **100 KB**. Concurrent connections per Worker invocation: **6**. ([D1 limits](https://developers.cloudflare.com/d1/platform/limits/))

Pricing: 5 GB free + **$0.75/GB-month** beyond. 25B rows-read + 50M rows-written/month free at Paid; **$0.001/M** rows-read and **$1/M** rows-written above. ([D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/))

**Critical incompatibility**: D1 import explicitly does **not support virtual tables — including FTS5 full-text search**. ([D1 import docs](https://developers.cloudflare.com/d1/best-practices/import-export-data/)) Vault's schema includes `notes_fts` as an FTS5 virtual table; `core/src/notes.ts` `searchNotes()` runs against it. Picking D1 means either (a) drop full-text search, (b) reimplement search on top of `LIKE` queries (slow), or (c) build an external search index (Pages-hosted Lunr, Vectorize, etc.). All three are bad.

**Migration path**: `wrangler d1 execute --file=schema.sql` after dumping local SQLite as SQL. **5 GiB max file** for a single import; larger requires splitting. Foreign keys + standard triggers + collations are supported. FTS5 is not.

**Fit for vault**: poor. The 10 GB cap is fine; FTS5 incompatibility is the dealbreaker.

### 3.3 Durable Objects + DO-SQLite

A Durable Object is a stateful per-instance compute primitive that lives in a single colo and can hold persistent storage. Each DO has its own isolate, its own storage, and runs at most one request at a time per object (input gates).

The **SQLite storage backend** (`ctx.storage.sql`) is **GA since 2025**, includes the **FTS5 module** (and `fts5vocab`), and runs **synchronously, in-thread, in-process** with the Worker code — "the database code runs not just on the same machine as the DO, not just in the same process, but in the very same thread" — yielding microsecond query latency. ([SQLite-in-DO blog](https://blog.cloudflare.com/sqlite-in-durable-objects/), [Storage API](https://developers.cloudflare.com/durable-objects/api/sql-storage/))

Limits:
- **10 GB SQLite per DO** (was 1 GB during beta).
- **2 MB per row/string/BLOB**.
- **100 KB per SQL statement**.
- **1,000 req/sec soft limit per DO** before "overloaded."
- 30s default CPU per request, configurable to 5 min.
- Class definitions per account: **500 on Paid, 100 on Free**. (Each tenant is one *instance* of a class, not a class — instances are unlimited.)
([DO limits](https://developers.cloudflare.com/durable-objects/platform/limits/))

Pricing on Paid: **$0.15/M requests** (1M free), **$12.50/M GB-seconds** (400k free), and **$0.20/GB-month SQLite storage** (5 GB free) — storage billing **starts January 2026**. ([DO pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/))

**Fit for vault**: excellent. The synchronous in-thread SQLite means vault's `BunSqliteStore` ports almost verbatim — `bun:sqlite`'s `Database.prepare().run()` becomes `ctx.storage.sql.exec()`, both synchronous. FTS5 works. 10 GB per tenant covers the heaviest realistic vault (Aaron's `default` is ~50 MB at 2280 notes; 10 GB is ~400k notes equivalent). The 1000 req/s ceiling is irrelevant for personal vaults. Hibernation when idle means scale-to-zero per tenant.

### 3.4 R2 (object storage)

R2 is S3-compatible, charges **$0.015/GB-month** standard storage (Infrequent Access $0.01), **zero egress charges**, **$4.50/M Class A ops** (writes) and **$0.36/M Class B ops** (reads). Free tier: 10 GB-month, 1M Class A, 10M Class B. ([R2 pricing](https://developers.cloudflare.com/r2/pricing/))

**Fit for vault**: ideal. Vault attachments are write-rare-read-rare (transcribed audio, images), 50 MB/user typical. Zero-egress means notes app on a phone can stream attachments without R2 bandwidth costs. The parked PR #101 already ships an `R2BlobStore` against a structurally-typed `R2BucketLike` interface.

### 3.5 Pages (static hosting)

Pages serves static `dist/` from CDN with custom domains, free TLS, free deploys. Free tier: 500 builds/month, 20 min/build, 20k files/site, 25 MiB/asset, 100 custom domains. Functions billed as Workers. ([Pages limits](https://developers.cloudflare.com/pages/platform/limits/))

**Fit for vault**: great for the Notes PWA (already supported by parachute-notes' build), and great for the vault Admin SPA (`src/admin-spa.ts`). One Pages site can serve the SPA bundle for all tenants; each tenant origin (`<user>.parachute.computer`) routes static asset requests to Pages and dynamic API/MCP requests to the Worker → DO chain.

### 3.6 Cloudflare Tunnel

`cloudflared` establishes an outbound-only secure tunnel from a private origin (the user's Mac, a VPS) to Cloudflare's edge, exposing the origin under a Cloudflare-managed hostname. **Free for up to 50 users**, $7/user/month above. No published bandwidth cap on the free tier; pricing is per-seat, not per-GB. ([Free tunnels announcement](https://blog.cloudflare.com/tunnel-for-everyone/))

**Fit for vault**: irrelevant for the "host vault on CF" question (vault is on CF, no tunnel needed); central for vault#199 Shape 3 / γ where vault stays local. The "low-cost low-friction" framing Aaron is now reconsidering specifically argues that tunnel-fronting still requires a user machine to be on, which is the friction CF-hosted-vault eliminates.

---

## 4. The vault → Cloudflare transformation

What concretely changes in vault to deploy on Cloudflare?

### 4.1 Runtime: Bun → V8 isolate

Vault's `src/server.ts` boots `Bun.serve()` and supervises a transcription worker, trigger handlers, and a stop-signal sentinel. On Workers:

- `Bun.serve(handler)` → `export default { fetch(req, env, ctx) }`. Routing in `src/routing.ts` ports unchanged.
- `Bun.password.hash/verify` (bcrypt) → `crypto.subtle` (PBKDF2 or scrypt). Single-file swap; existing hashes need both-verifiers + re-hash-on-next-login.
- `process.env.X` → `env.X` Worker bindings via `wrangler.toml`. ~30+ one-line swaps across `src/`.
- `setInterval` (stop-signal, transcription poller) → Cron Triggers + Queues. Stop-signal pattern goes away entirely.
- `node:fs` config writes → DO storage; Workers Secrets for global env.
- Daemon supervision (`launchd`, `systemd`) → kept for self-hosted, omitted from CF bundle.

**Estimated effort**: 1–2 weeks for one steward to land a Workers-runnable build that passes the existing test suite under DO. Wide-but-shallow diff.

### 4.2 Storage: SQLite → DO-SQLite

The `Store` interface is already async (every method returns `Promise<T>`). PR #99 introduced `SqlDb` — a `prepare/exec/iterate` adapter — and `DoSqliteStore` against `ctx.storage.sql`. The ops modules (`notes.ts`, `links.ts`, `wikilinks.ts`, `tag-schemas.ts`) consume `SqlDb`, so they run unchanged on either backend.

What's *not* yet handled in the parked PR:
- **FTS5 trigger SQL has embedded semicolons.** PR #99 included a BEGIN/END-aware splitter because DO's `sql.exec()` only accepts one statement per call. This works but needs the smoke test `migrateToV4` referenced in PR #99's test plan.
- **`PRAGMA table_info(notes)` calls** (used by `migrateToV4`) need to be redirected to `.prepare().all()` shape on DO; the adapter's PRAGMA-skip applies only to schema-init PRAGMAs.
- **`transactionSync()` semantics** — DO storage exposes synchronous transactions designed for this exact pattern (rolls back on throw). Vault's `createNotes` bulk path needs to wrap in `ctx.storage.transactionSync()`.

**Migration from local SQLite to DO**: not a wrangler import — DO storage is per-instance, not a database in the D1 sense. Migration is "open the DO, replay an export." The natural shape: vault's existing Obsidian-import endpoint, fed an export zip generated from the user's local install. PR #99 doesn't ship this; it's the next missing piece.

### 4.3 Filesystem → R2 + DO storage

Vault writes two kinds of state to disk today:
- **Attachments** at `~/.parachute/vault/assets/<vault>/<id>` — file blobs uploaded via `/api/storage/upload` and served via `/api/storage/<id>`. PR #101's `BlobStore` interface + `FsBlobStore` (local) + `R2BlobStore` (CF) covers this. Wire up: pass `R2BlobStore(env.ATTACHMENTS_BUCKET, prefix=tenantId)` into the DO.
- **Config** in `~/.parachute/vault/.env`, `vault.yaml`, `config.yaml`, `services.json`, token-store JSON files. These move to DO storage (small, per-tenant, transactional with the SQLite they sit alongside) — except global env (Workers Secrets) and the static hub JWKS-cache (Workers KV with TTL).

**Tokens table is already in SQLite.** No change.

### 4.4 The tag-scope auth check (vault#241)

vault#241 (rc.30, just merged) ships tag-scoped tokens Phase 1. The auth check runs on every read and uses two mechanisms:

1. **Schema-driven `getTagDescendants` cache** — built from `_tags/<name>` config notes via `loadTagHierarchy(db)` in `core/src/tag-hierarchy.ts`. Cached on the store as `_tagHierarchy`, invalidated on writes to `_tags/*` paths.
2. **String-form fallback** — for each note tag `t`, check `t.split("/")[0] === scopedRoot`. Pure string ops, no I/O.

Both ports cleanly to DO:

- The cache is **per-store-instance**, and on DO each tenant *is* one store instance (one DO = one BunSqliteStore-equivalent). The cache is naturally per-tenant and lives across requests within the DO's lifetime — better than on a stateless Worker where caches die with each isolate. Hibernation drops the cache, but the next request rebuilds it (single SQL query against `_tags/*` notes).
- `getTagDescendants` is pure compute; the cache uses a memoization map. No environment dependencies.
- The `loadTagHierarchy` function uses `db.prepare(...).all()` — runs on `SqlDb`, hence on DO via `ctx.storage.sql.exec()`.

**Net**: the just-shipped tag-scope work *helps* the CF port, doesn't hurt it. The DO model is exactly the right home for per-tenant caches.

### 4.5 MCP transport

Vault exposes MCP over Streamable HTTP at `/vault/<name>/mcp`. The transport is implemented in `src/mcp-http.ts` using `Bun.serve`'s response-stream API. Workers support the same Web Streams API natively (`ReadableStream`, `Response` with stream body), and the Streamable HTTP MCP transport is well-suited to Workers (see [MCP Servers on Cloudflare](https://developers.cloudflare.com/agents/model-context-protocol/) for the canonical pattern). Stdio MCP is irrelevant in cloud; clients connect over HTTP.

Hub-issued JWT validation via JWKS already uses `fetch()` (`src/hub-jwt.ts`); ports without modification. JWKS cache lives in DO storage with a TTL; no behavioral change.

### 4.6 Multi-tenant routing

A single Worker serves all tenants. Routes resolve as:

- `<user>.parachute.computer/api/...` → Worker → forward to DO with ID `idFromName(user)`.
- `<user>.parachute.computer/notes/...` → Pages (static asset).
- `<user>.parachute.computer/admin/...` → Pages (admin SPA bundle) + Worker for API calls.

For custom domains (`notes.aarongabriel.com`), Cloudflare for SaaS handles per-tenant TLS automation. Workers for Platforms is *not* needed (no per-customer code execution); the dispatch Worker pattern (route by hostname) is sufficient.

---

## 5. Cost modeling

Workload assumption (per the brief): per user, **~2000 notes**, **~300 attachments / 50 MB**, **~50 requests/day average + bursts**.

For 1000 users, that's: 1.5M monthly requests, 50 GB attachments, 50 GB hot SQLite (50 MB × 1000), modest CPU.

### 5.1 Cloudflare cost model (DO + R2 shape)

| Component | Free included | At 1k users | Pricing | Net |
|---|---|---|---|---|
| Workers requests | 10M/mo | 1.5M | $0.30/M | within free |
| Workers CPU-ms | 30M/mo | ~3M (assume 2ms avg) | $0.02/M | within free |
| DO requests | 1M/mo | 1.5M (each user request = ≥1 DO req) | $0.15/M | $0.08 |
| DO duration GB-s | 400k/mo | hibernation-dependent; assume 2s avg-active per req × 128MB = 0.25 GB-s × 1.5M = 375k | $12.50/M | within free |
| DO SQLite storage | 5 GB/mo | 50 GB | $0.20/GB-mo | $9.00 |
| R2 storage | 10 GB/mo | 50 GB | $0.015/GB-mo | $0.60 |
| R2 Class A (writes) | 1M/mo | 0.3M (one write per attachment created) | $4.50/M | within free |
| R2 Class B (reads) | 10M/mo | 1M (occasional attachment reads) | $0.36/M | within free |
| Pages | unlimited | — | — | $0 |
| **Workers Paid base** | — | — | $5/mo | $5 |
| **Total** | | | | **~$15/mo at 1k users** |

**Per-user/month at 1k users: ~$0.015.** That's not a typo. **At 10k users, scaling linearly**: storage dominates, ~$110/mo (DO storage 500 GB ≈ $99 + R2 500 GB ≈ $7.50 + DO requests 15M ≈ $2 + Workers Paid base $5) → **~$0.01/user/mo**. **At 100 users**: comfortably within free tier; ~$5/mo (just the Workers Paid base) → **~$0.05/user/mo**.

A more conservative model (DO duration scales worse than linearly because cold-start hibernation gives way to warm-instance billing as request rate climbs): factor **3× for headroom** still puts 1k users under $50/mo and 10k users under $400/mo.

### 5.2 Comparison: alternative shapes (per-user/month at 1k users)

| Shape | Infra at 1k users | Per-user/mo | Notes |
|---|---|---|---|
| **CF Workers + DO + R2** (Shape γ) | ~$15–50/mo | $0.015–0.05 | This research; scale-to-zero, FTS5 native |
| **Fly.io 1-container-per-tenant** (vault#199 Shape 2) | ~$2,000/mo | $2 | $1.94/mo machine × 1000 + volumes. Idle machines dominate. |
| **Fly.io shared-container, multi-tenant SQLite** | ~$50/mo | $0.05 | A handful of beefy machines hosting many tenants' SQLite via vault's existing `getVaultStore` cache. Single-region. |
| **AWS Lambda + S3 + Aurora Serverless** | ~$200–500/mo | $0.20–0.50 | Aurora min ACUs alone is $40+/mo; per-tenant Postgres-RLS schema; Lambda colder than Workers. |
| **Render / Railway** | ~$400–800/mo | $0.40–0.80 | $7/mo entry containers; PostgreSQL add-on starts at $20/mo. Multi-tenant required to be cheap; same RLS bug-surface as AWS option. |
| **Self-hosted by user** (Shape 3 from vault#199 v1) | tunnel + scribe pool only | $0.50–2 | Free for vault itself; Parachute pays for tunnel-CF-Access ($7/user above 50) + scribe pool. The user-machine-must-be-on cost is paid in user retention, not dollars. |

**Cheapest viable option = CF DO + R2** by a factor of 30–100× over containerized alternatives, because scale-to-zero per tenant + zero idle cost. Self-hosted by user is the cheapest in absolute dollars to Parachute but pays the cost in user-friction.

(Caveats: these are ballpark; real billing depends on bursty patterns, attachment-read distribution, and DO duration which scales with how often DOs hibernate. The order-of-magnitude finding is robust; the exact dollar figures within an order of magnitude are not.)

---

## 6. Three architectural shapes

The brief asks evaluation of three shapes specific to "hosted vault on Cloudflare." All three are within the CF-hosted family — they differ in tenant-isolation strategy.

### Shape α — Worker + D1 (single DB, multi-tenant via app-layer RLS)

One D1 database; rows tagged with `tenant_id`; queries filter by tenant.

**Pros**:
- Simplest infrastructure — one database, one schema, one migration path.
- D1 is "batteries included" with backup/export tooling, query insights, point-in-time recovery.
- Cross-tenant analytics is trivial (we're the operator; we may want this for billing/usage).

**Cons**:
- **No FTS5.** Hard incompatibility with vault's `notes_fts` table. Reimplement search externally or accept LIKE-only search.
- **App-layer-RLS is bug-surface.** Every query needs `WHERE tenant_id = ?`; one missing clause = data leak. The current vault SQL doesn't have that pattern (it's single-tenant).
- 10 GB cap per database is fine for 1k users at our workload (50 GB needed), so we'd shard across N D1 databases anyway — at which point the "one DB" simplicity is gone.
- 100 KB statement size; 6 concurrent connections per Worker invocation. Tight for some bulk-import flows.

**Verdict**: Don't pick this. The FTS5 incompatibility alone disqualifies it for vault.

### Shape β — Worker + DO + D1-per-DO

Each tenant gets a Durable Object that owns its own D1 binding. Vault state lives in D1; the DO is just a router.

**Pros**:
- Physical per-tenant DB (one D1 per tenant). Strong isolation.
- D1 backup/export tooling per tenant.
- Hibernation-friendly: DO is cheap to spin up; D1 is the durable layer.

**Cons**:
- **Still no FTS5** — D1 still doesn't support virtual tables.
- D1 is accessed by HTTP from the DO — adds 1–10ms latency per query that DO-SQLite avoids.
- Per-DO D1 binding requires platform support that's awkward at present. Workers normally can't "create a new D1 database when a new tenant signs up" without a control-plane API call.
- Two storage layers to manage (DO local for transient state + D1 for durable) doubles the moving parts.

**Verdict**: Don't pick this. Inherits D1's FTS5 problem without offsetting it.

### Shape γ — Worker + DO with embedded SQLite (the natural fit)

Each tenant is one Durable Object instance. The DO holds its own SQLite via `ctx.storage.sql`, runs vault's per-store ops in-thread, and exposes the same HTTP/MCP routes the Bun-host vault exposes today.

**Pros**:
- **FTS5 supported.** Full vault schema ports verbatim.
- **Synchronous SQLite calls in-thread** — vault's `BunSqliteStore` ports almost line-for-line. PR #99's `SqlDb` adapter is the abstraction.
- **Per-tenant isolation is physical.** Each DO has its own storage; no cross-tenant data even possible at the SQL layer.
- **Scale-to-zero per tenant.** A user who hasn't logged in this week costs nothing in DO duration (only storage).
- 10 GB SQLite per DO covers 99.9% of personal vaults indefinitely.
- Zero-egress from R2 means notes-PWA can stream attachments without bandwidth costs.
- The just-shipped tag-scope cache lives naturally per-DO.

**Cons**:
- Still on Cloudflare — vendor coupling. (`SqlDb` mitigates by making the SQL layer portable.)
- One DO per tenant means **provisioning is a code action** (create DO instance, run schema migration) rather than a "row in a database." The control plane for this is small but new.
- DO migrations across class versions need Cloudflare's migration tooling (rename class, versioned schema). Vault already has `migrateToV4`-style versioned migrations — they fit, but each migration becomes a per-DO replay.
- DO storage backup is by code (export + write to R2) rather than declarative — we control backups, which means we operate them.
- **DO "owns the tenant"** — moving a tenant to a different colo or off CF requires explicit migration code (export from DO, import to new home). Not free.

**Verdict**: This is the shape. PR #99 prototyped it; PR #101 prototyped the attachment side; together they're 70-80% of the work.

### Note on the brief's "Shape γ — KV-on-DO blob"

The brief sketched a variant where the tenant's full SQLite is stored as a blob in DO KV, loaded into wasm-sqlite per request. That's not necessary — `ctx.storage.sql` is a real SQLite running in the DO's thread, not a blob you serialize. The real Shape γ above subsumes it; no blob-shuffle needed.

---

## 7. Required vault changes — concrete checklist

### Already done (no action)
- Async `Store` interface (`core/src/types.ts`).
- `BunSqliteStore` is an `async` wrapper over sync internals — interface contract is met.
- Tag-scope auth cache is per-store, hierarchy-driven, sync-pure (vault#241 / rc.30).
- Per-vault MCP routing in `src/routing.ts` is hostname-agnostic.
- Hub-JWT validation uses `fetch()` (`src/hub-jwt.ts`).
- Notes PWA is static; runs on Pages with no change.
- Admin SPA (`src/admin-spa.ts`) is static markup + Worker-facing API; ports.

### Small effort (1–3 days each)
- **`Bun.password` → `crypto.subtle`** for password hashing; keep both verifiers for migration. Touches `src/auth.ts`, `src/owner-auth.ts`.
- **`process.env.X` → Worker `env.X`** mechanical pass across `src/`. Wrangler bindings declared in `wrangler.toml`. Search for `process.env` (~30+ sites).
- **`Bun.serve()` → `export default { fetch }`** in `src/server.ts`. Routing already extracted.
- **Stop-signal sentinel removal** (`src/stop-signal.ts`). Workers don't need a kill signal.
- **Wrangler config + Miniflare local dev** — new file `wrangler.toml`, dev workflow change. Steward needs to learn Wrangler.
- **Daemon wrappers** (`src/launchd.ts`, `src/systemd.ts`, `src/backup-launchd.ts`) — keep for self-hosted, omit from CF bundle.

### Medium effort (3–7 days each)
- **Filesystem config → DO storage / Workers Secrets**. Per-tenant config (`vault.yaml`, token-store) → DO storage. Global env (Anthropic key, R2 bucket name) → Secrets. Touches `src/config.ts` heavily.
- **`R2BlobStore` integration** beyond what PR #101 shipped — wire into `src/routes.ts` `handleStorage`, ensure path-traversal guard transports correctly to opaque-key R2 path.
- **MCP HTTP transport on Workers Streams** — verify `src/mcp-http.ts` works with Workers' `ReadableStream`. Probably 1-line diff but needs end-to-end tested.
- **Cron Triggers + Queues** for the transcription worker — replace `setInterval` polling. Defines a new ops surface but the existing queue logic in `src/transcription-worker.ts` translates.
- **`migrateToV4`-style migrations on DO** — ensure each schema bump runs per-DO on first request after deploy. Probably needs a "schema_version on DO storage" check + replay.
- **`SqlDb` adapter completion** — PR #99 didn't ship the BEGIN/END splitter for FTS triggers in production-ready form. Smoke test against real DO via Miniflare or remote.

### Major effort (1–3 weeks each)
- **Per-tenant DO routing + provisioning control plane.** A Worker that, given a hostname, finds-or-creates a DO; signup flow that triggers DO creation; tenant-rename / tenant-delete code paths. New service surface that doesn't exist today. **This is the dominant cost** — it's where vault's per-tenant lifecycle becomes a thing we operate.
- **Migration tooling** — export from local Bun-vault → import into CF DO. Reuse vault's existing Obsidian-import path; wrap as a CLI command (`parachute-vault cloud-migrate`). This is what makes "no lock-in" honest.
- **Cloudflare for SaaS custom domains** — per-tenant TLS automation, hostname management, DNS API. The April-20 cloud-offering-sketch mentions this; no code yet.
- **Backup-via-export pipeline** — DO storage doesn't have native external backup; we run a periodic export to R2 with PITR-style retention. Operational-grade backup is its own thing.
- **CI/CD for Workers** — Wrangler deploys, environment promotion (dev/stage/prod), versioned DO migrations. Different shape from `bun run build && docker push`.

---

## 8. Recommendation

Aaron's framing — "really low cost way of getting people a vault really quickly … gonna let us have a lot of early users" — points at user-acquisition friction, not steady-state COGS. Both numbers favor CF-hosted-vault.

Three plausible re-sequencings (Aaron decides):

- **(i) Stay with vault#199 v3.** CF-hosted vault is Phase 3, after Cloud Hub validates with paying users. Pick this if the goal is to validate the managed-Parachute value prop independent of where data lives, and you'll absorb the "your-machine-must-be-on" friction for v1.
- **(ii) Re-sequence: CF-hosted vault as Phase 1.** Skip tunnel-fronting; ship vault directly on CF DO from day one. Pick this if the goal is genuinely-zero-friction onboarding and you accept the brand-shift toward "managed by Parachute" first, "self-host as backstop" second. MVP: 4–6 weeks for one steward to revive PR #99 + #101, add per-tenant DO routing, signup, billing, and migration tooling.
- **(iii) Both, layered.** Cloud Hub for the 5 existing self-hosted users (stable URL + identity, data stays local); Cloud Vault for new signups (zero-machine-required). Each path is 3–4 weeks; they share `auth.parachute.computer` and the notes PWA. Most defensible long-term, more attention-cost.

The CF technical evaluation supports any of the three — Shape γ is feasible at low cost regardless of when it ships.

---

## 9. Open questions for Aaron

These are the calls only Aaron can make. The brief's "Aaron decides; don't decide for him" is honored.

1. **Re-sequence the roadmap?** Cloud Hub-first (vault#199 v3) vs Cloud Vault-first vs both-parallel. The single load-bearing strategic decision. The vault#199 v3 §8.7 phase plan was settled 2026-04-29; this research surfaces a credible reason to revisit the order.

2. **Brand-positioning shift.** "Your data on your machine" was the promise; "your data on a Cloudflare DO that we operate, exportable at any time" is a different promise. Both are coherent, but they appeal to different users. Are we explicitly making this shift, or threading the needle (CF-hosted as one tier, self-host as another, equal billing)?

3. **Pricing posture for CF-hosted vault.** Unit cost is ~$0.05/user/month all-in; a $5/mo Starter tier has 100× margin. Do we price for early-volume (cheap) or for sustained margin (defensive against Anthropic/CF surprises)? The vault#199 v3 $15/Starter $30/Pro tiers were anchored on Hetzner-VM costs that don't apply here.

4. **How much vendor coupling to Cloudflare are we comfortable with?** Shape γ doesn't preclude later moves (the `SqlDb` + `BlobStore` abstractions keep the SQL/blob layer portable). But the per-tenant DO + per-tenant routing + DO migration tooling are CF-specific code. We'd be doing real work to leave if CF prices change. AWS-equivalent (Aurora Serverless + Lambda + S3 + per-tenant Cognito) is 4-5× more expensive for the same workload, so the lock-in is "we paid CF prices to get CF prices."

5. **What's the migration-from-self-hosted UX?** A current self-hosted user wants to move to cloud. Options: (a) run-an-export-then-upload (manual), (b) `parachute-vault cloud-migrate` CLI command (one-shot), (c) ongoing-replication (hard — that's vault#199 Shape 4). The brief asks about volume; (c) is overkill, (b) is the right call, but it's a new piece of code.

6. **Does the cloud-hosted vault still expose an MCP endpoint clients can connect to directly?** Today's design says yes (`https://<user>.parachute.computer/vault/default/mcp`). That means agents (Claude Desktop, Claude Code, third-party MCP clients) hit Cloudflare on every read. Is that the intent, or do we want to mediate through hub on the cloud side too? The current routing already supports both.

7. **DO storage billing starts January 2026.** It hasn't actually billed yet — January 7, 2026 was the announced target. Has it activated? If it has, the cost model in §5.1 stands. If billing has been delayed, costs are even lower for early launch.

8. **What's the FTS5-vs-D1 tension's escape hatch?** This research recommends DO-SQLite explicitly because of FTS5. If Cloudflare adds FTS5 to D1 in 2026 (no announcement at writing), Shape α and β become viable too — D1 is cheaper-per-byte at small scale. Worth tracking, not worth waiting for.

---

## Companions

- vault PR [#99](https://github.com/ParachuteComputer/parachute-vault/pull/99) (closed, branch preserved): `feat/do-sqlite-store` — `SqlDb` + `DoSqliteStore`. Revive as Phase 0 if pursuing Shape γ.
- vault PR [#101](https://github.com/ParachuteComputer/parachute-vault/pull/101) (closed, branch preserved): `feat/r2-blob-store` — `BlobStore` FS + R2. Same.
- vault `docs/cloud-shape-research` branch: `docs/design/2026-04-29-parachute-cloud-shape.md` — vault#199's three-version research doc. v3 §8 is the active recommendation.
- `parachute.computer/design/2026-04-20-cloud-offering-sketch.md` — earlier north-star sketch.
- `parachute-patterns/research/parachute-data-model-shape.md` — current vault data model (2280 notes / 46 tags / 945 links / 295 attachments on Aaron's `default`).

## Cloudflare docs cited

- [Workers limits](https://developers.cloudflare.com/workers/platform/limits/)
- [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Workers Node.js compatibility](https://developers.cloudflare.com/workers/runtime-apis/nodejs/)
- [D1 limits](https://developers.cloudflare.com/d1/platform/limits/)
- [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/)
- [D1 import / export (FTS5 unsupported)](https://developers.cloudflare.com/d1/best-practices/import-export-data/)
- [Durable Objects limits](https://developers.cloudflare.com/durable-objects/platform/limits/)
- [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)
- [Durable Objects SQL Storage API](https://developers.cloudflare.com/durable-objects/api/sql-storage/)
- [Durable Objects best-practices: storage](https://developers.cloudflare.com/durable-objects/best-practices/access-durable-objects-storage/)
- [SQLite-in-DO blog announcement](https://blog.cloudflare.com/sqlite-in-durable-objects/)
- [R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- [Pages limits](https://developers.cloudflare.com/pages/platform/limits/)
- [Cloudflare Tunnel free tier announcement](https://blog.cloudflare.com/tunnel-for-everyone/)
- [Workers for Platforms overview](https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/)
- [More NPM packages on Workers (node:fs, node:http)](https://blog.cloudflare.com/more-npm-packages-on-cloudflare-workers-combining-polyfills-and-native-code/)
