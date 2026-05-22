# SSRF-safe URL fetching

> Any Parachute module that fetches user-supplied URLs must defend
> against Server-Side Request Forgery — preventing the server from
> being weaponized to reach internal services, cloud metadata
> endpoints, link-local addresses, or private networks.

## The principle

Once a module accepts a URL from a caller (a `transcribe-url` payload,
a webhook target, a notification destination, an arbitrary "import this
file" tool), it stops being a passive responder and starts being a
client. Without explicit defenses, the module's network position
becomes the caller's network position: requests originate from inside
the Parachute deployment's trust boundary, which often reaches surfaces
the caller cannot — Tailscale-internal vaults, AWS instance metadata,
loopback admin SPAs, private RFC 1918 ranges, CG-NAT tailnet IPs.

The defense is a **single hardened fetch primitive** every consumer
goes through. No ad-hoc `fetch()` against caller-supplied URLs anywhere
in the module — exactly one chokepoint, every layer enforced before any
audio data flows.

## The 7-layer defense

Implemented in
[`parachute-scribe/src/url-fetch.ts`](https://github.com/ParachuteComputer/parachute-scribe/blob/main/src/url-fetch.ts):

| # | Layer | Enforcement | Failure code |
| --- | --- | --- | --- |
| 1 | **Scheme allowlist** | `http:` / `https:` only. Reject `file:`, `data:`, `gopher:`, `ftp:`, `javascript:`, anything else. | `400 unsupported_scheme` |
| 2 | **Hostname blocklist** | Literal IPs in private / loopback / link-local / CG-NAT / multicast / reserved ranges (see below); `localhost` and `*.localhost`. | `400 blocked_host` |
| 3 | **DNS resolve + re-check** | `dns.lookup(hostname)` → re-run the resolved IP through the blocklist. Catches DNS rebinding (`169-254-169-254.example.com` → `169.254.169.254`). | `400 blocked_host` / `400 dns_failed` |
| 4 | **Redirect revalidation** | `redirect: "manual"`. Every `3xx Location` re-runs layers 1–3 before following. Max 5 hops. | `400` per layer / `502 fetch_failed` ("too many redirects") |
| 5 | **Size cap** | Explicit byte limit (scribe: 100 MiB). Checked via `Content-Length` AND mid-stream during body read — chunked-transfer can't bypass. | `413 too_large` |
| 6 | **Timeout** | `AbortController` wrapping the whole fetch (DNS + connect + body read). Scribe: 5 min. | `504 timeout` |
| 7 | **Content-Type sniff** | Permissive but typed gate. Reject responses that aren't plausibly the expected content (scribe: `audio/*`, select `video/*` containers, `application/octet-stream` with audio extension). | `415 not_audio` (or domain-equivalent) |

The blocklist for layer 2 + 3, conservative:

```
IPv4:
  0.0.0.0/8        reserved
  10.0.0.0/8       private (RFC 1918)
  127.0.0.0/8      loopback
  169.254.0.0/16   link-local (AWS metadata: 169.254.169.254)
  172.16.0.0/12    private (RFC 1918)
  192.0.0.0/24     IETF protocol assignments
  192.168.0.0/16   private (RFC 1918)
  100.64.0.0/10    CG-NAT (RFC 6598; tailnet space)
  224.0.0.0/4      multicast
  240.0.0.0/4      reserved
  255.255.255.255  broadcast

IPv6:
  ::               unspecified
  ::1              loopback
  fc00::/7         unique-local
  fe80::/10        link-local
  ff00::/8         multicast
  ::ffff:a.b.c.d   IPv4-mapped (dotted form — defer to v4 blocklist)
  ::ffff:HHHH:HHHH IPv4-mapped (hex form — what Bun emits; decode + defer to v4)
```

## The Bun normalization gap

Bun's URL parser normalizes `[::ffff:127.0.0.1]` (dotted IPv4-mapped
IPv6) into `[::ffff:7f00:1]` (hex IPv4-mapped) before handing the
hostname back to the caller. A blocklist that only matches the dotted
form misses the hex form and allows the loopback hop.

The blocklist must handle **both** representations:

```ts
// parachute-scribe/src/url-fetch.ts isBlockedV6
const mappedDotted = lower.match(/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
if (mappedDotted) return isBlockedV4(mappedDotted[1]!);

const mappedHex = lower.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
if (mappedHex) {
  const hi = parseInt(mappedHex[1]!, 16);
  const lo = parseInt(mappedHex[2]!, 16);
  // Decode `hi:lo` into `a.b.c.d` and defer to v4.
  return isBlockedV4(`${(hi >> 8) & 0xff}.${hi & 0xff}.${(lo >> 8) & 0xff}.${lo & 0xff}`);
}
```

Pin this in tests with both literal forms of `::ffff:127.0.0.1`.

## Test-only escape

Real tests need to exercise the fetcher against a local server. The
escape is an env var **read per-call** (not module-scope), so it can't
accidentally persist across an import boundary and leak into
non-test code paths:

```ts
function loopbackBypassFor(hostname: string): boolean {
  if (process.env.PARACHUTE_SCRIBE_URL_FETCH_ALLOW_LOOPBACK !== "1") return false;
  if (hostname === "::1") return true;
  if (!hostname.includes(".")) return false;
  return hostname.startsWith("127."); // IPv4 loopback only.
}
```

Three properties make this safe:

- Per-call read — flipping the env after a test sets up the fetcher
  doesn't persist.
- Loopback only — bypass is the narrowest possible: `127.0.0.0/8` +
  `::1`. Other private ranges stay blocked.
- Hard-coded module-scoped name — the env var is module-prefixed
  (`PARACHUTE_SCRIBE_*`); a hypothetical second consumer doesn't share
  the bypass.

## What's not enough

- **`new URL()` parsing alone** — accepts the URL as well-formed but
  doesn't validate the host against private networks. The whole point
  is the URL is syntactically fine.
- **DNS lookup alone** — without re-checking the resolved IP and
  pinning it for the connect, a malicious DNS server can return a
  public IP for the check and a private IP for the actual fetch
  (DNS rebinding). Layer 2 + 3 work together.
- **User-Agent / Referer / origin header checks** — trivially
  bypassable by any caller. They're for telemetry, not defense.
- **Blocking by hostname string** — `localhost.evil.example.com`
  resolves to a public IP that lies inside one of the blocklisted
  ranges; only the post-resolve re-check catches it.
- **Trusting `Content-Length` for the size cap** — chunked-transfer
  responses can omit it. The streaming check (layer 5, second half) is
  the load-bearing piece.

## Reference implementation

See [`parachute-scribe/src/url-fetch.ts`](https://github.com/ParachuteComputer/parachute-scribe/blob/main/src/url-fetch.ts):

- `parseAndValidateUrl(input)` — layers 1 + 2.
- `resolveAndCheck(hostname)` — layer 3 (DNS + re-check).
- `fetchAudioFromUrl(input)` — wires layers 4 + 5 + 6 + 7 around the
  `fetch` call, with `redirect: "manual"` driving the per-hop
  revalidation loop and `AbortController` driving the timeout.
- `isBlockedAddress(ip, family)` / `isBlockedV4` / `isBlockedV6` — the
  blocklist primitives, plus the Bun normalization handling.

Tests in
[`parachute-scribe/src/url-fetch.test.ts`](https://github.com/ParachuteComputer/parachute-scribe/blob/main/src/url-fetch.test.ts)
(34 cases) cover: scheme rejection, the full IP-literal blocklist (v4 +
v6 + IPv4-mapped-v6 dotted + Bun-normalized hex), DNS resolution +
re-check, redirect revalidation across every layer, mid-stream size
cap, non-audio content-type rejection, the audio-ish fallback for
generic `application/octet-stream`.

## Rules

- **One chokepoint per module.** All caller-URL-bearing routes call
  the same fetcher function. Don't sprinkle `fetch()` into route
  handlers — the route handler accepts the URL string and hands it to
  the fetcher.
- **Reject early.** Layers 1 + 2 fire before any DNS or network
  traffic. A bad scheme or IP literal shouldn't cost a DNS lookup.
- **Pin the resolved IP — or accept the cost of resolving twice.**
  Resolving for the check then handing the hostname back to `fetch`
  lets the OS resolve again under the attacker's nose. Either pin
  (via undici dispatcher) or accept that the second resolve hits the
  OS cache and re-checks per layer 3.
- **Manual redirects, full re-validation per hop.** A 302 to
  `http://127.0.0.1:1939/admin` is the canonical attack — every
  Location runs the full gauntlet.
- **Streaming size enforcement.** `Content-Length` is a hint, not a
  contract. The mid-stream accumulation check is the binding one.
- **Test-only bypasses are env-gated and per-call.** Module-scope
  bypasses persist across imports and accidentally enable in
  production.

## When this applies

Today, scribe's `POST /v1/audio/transcriptions-url` and the
`transcribe-url` MCP tool. The pattern extends to any future
caller-URL surface:

- Webhook fan-out modules (channel-style) that POST to caller-supplied
  callback URLs.
- Notification senders that GET caller-supplied avatar URLs.
- Import-from-URL flows in vault (markdown / Obsidian / attachment
  imports).
- Module-to-module HTTP calls where the destination is operator-config
  rather than module-hardcoded (the destination is still operator-
  trusted, but defense in depth costs little).

Each new consumer should reuse the same fetcher (factored into a
shared library when scribe + a second module both need it) rather
than reimplementing the 7 layers. The blocklist is the kind of code
that's only correct on the third or fourth pass; sharing the
implementation amortizes the audit cost.

## History

Shipped in
[`scribe#48`](https://github.com/ParachuteComputer/parachute-scribe/pull/48)
on 2026-05-21 alongside the URL transcription endpoint and the MCP
server. 34 tests across the 7 layers pin the defense; reviewer dispatch
verified the IPv4-mapped IPv6 dual-form handling and the
mid-stream size cap as the two highest-leverage layers.

YouTube + general-purpose video extraction was punted from the same PR
— `yt-dlp` is a heavy runtime dep (~50MB Python + ffmpeg) AND a much
bigger SSRF surface (libcurl + every protocol handler yt-dlp speaks).
Direct-URL only is the narrow primitive; callers who want YouTube
extract audio outside scribe and POST the URL.

## Related patterns

- [`service-to-service-auth.md`](./service-to-service-auth.md) — the
  same "one validator function, one chokepoint" discipline applied to
  bearer tokens. SSRF-safe-fetch is its egress-side cousin.
- [`trust-gradient-isolation.md`](./trust-gradient-isolation.md) —
  why even owner-operated modules defend against SSRF: the trust
  gradient runs caller → module, and the caller authoring a
  URL is closer to a third party than to the operator.
- [`module-protocol.md`](./module-protocol.md) — modules accept
  caller input on their `/.parachute/*` and module-specific routes;
  caller-supplied URLs are a specific shape of caller input that needs
  this defense.
