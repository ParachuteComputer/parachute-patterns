# Tag-scoped tokens — industry survey

> Comparative survey of how mainstream auth systems handle token-scoped-by-data-slice authorization, written to validate or challenge the design in [`patterns/tag-scoped-tokens.md`](../patterns/tag-scoped-tokens.md) (patterns#24, merged 2026-05-02).

**Author:** patterns tentacle. **Date:** 2026-05-02. **Status:** advisory; recommendations should be triaged into either the patterns doc or follow-up issues.

---

## 1. TL;DR

- **The "subset rule" for delegated minting is universal good practice and patterns#24 already has it.** GitHub fine-grained PATs, GCP service-account impersonation, AWS `iam:PassRole`, OAuth 2 §3.3 scope-downgrade — every one converges on "you can only delegate a subset of what you hold." Keep it.
- **Tag-as-auth-boundary is unusual but not unprecedented.** AWS ABAC and GCP IAM tag-conditions both work this way; Salesforce Data Cloud's policy-based governance does too. They scale fine *if* the tag taxonomy is curated. The hazard is data drift — the tag is data, not policy, and writers can change it.
- **Hierarchical inheritance is the dominant pattern.** GCP IAM (org → folder → project), POSIX ACLs (default ACL → child), Notion (page → child page), Auth0 nested groups, LDAP nested groups — all converge on "grant at parent, descendants inherit." patterns#24 matches the consensus.
- **POSIX-ACL "inheritance at create time only" is a hazard worth considering.** When a child resource is created, does it snapshot the parent's allowlist or evaluate dynamically? patterns#24 should evaluate dynamically; clarify this in the doc.
- **Allow-list is the right default; deny-list is rarely needed and dangerous.** The denylist literature is unanimous — deny-by-default + explicit allow is the only secure pattern. Don't add denylist support without strong use-case evidence.
- **Read-list vs write-list separation is a real pattern in PostgreSQL RLS** (`USING` vs `WITH CHECK`), and worth considering as a future extension. Most agents will want to read more than they write.
- **The "tag-rename moves a note out of scope mid-session" hazard is real and underexplored.** Surface it explicitly in the doc; recommend either a denormalized `tag_root_index` for fast checks plus invalidation on rename, or accept eventual-consistency semantics.
- **Wildcards beat literal sub-tag enumeration.** Vault path policy `secret/health/*` is the canonical shape; patterns#24 already uses root-only allowlist with implicit subtree expansion, which is functionally equivalent and shorter.

---

## 2. Existing design recap (patterns#24)

A vault token (`pvt_*`) optionally carries a `scoped_tags` JSON array (immutable post-mint). The auth check is the intersection of the existing `vault:<name>:<action>` OAuth scope and tag-allowlist membership. A note matches if any of its tags has its root in the allowlist; root computed via `t.split('/')[0]`. Sub-tags inherit implicitly through the `_tags/<name>` config-note hierarchy. A tag-scoped admin can mint tokens only with subset allowlists. Token shape: `{label, scope, tags: ["health", "wellness"], expires_in}`. Single-vault, allowlist-only, no read/write separation, no time-bounded per-tag scope, no group abstraction.

---

## 3. Survey of slice-scoped authorization in mainstream systems

### 3.1 GitHub fine-grained Personal Access Tokens (PATs)

**Slice expression:** Repository-level. Token mint UI lets you pick "all repos / public repos / specific repos" within one user or organization owner. Permissions are 50+ granular keys (`contents`, `pull_requests`, etc.) at `read | write | admin` levels (write implies read; admin implies write).

**Sub-resource inheritance:** None — the slice is the repo. There's no sub-folder scoping inside a repo.

**Auth check at request time:** GitHub's API gateway maps the bearer token to its scoped-repo list, intersects with the requested resource, applies the permission level.

**Mint authority:** "A token cannot grant additional access capabilities to a user — if the owner lacks administrative access, the token won't provide it." Org-required-approval gate prevents PAT use against sensitive orgs without admin sign-off. **Subset rule is implicit but enforced.**

[Source: GitHub Docs — managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) | [GitHub Blog — fine-grained PATs](https://github.blog/security/application-security/introducing-fine-grained-personal-access-tokens-for-github/)

**Lesson for Parachute:** GitHub's slice = repo, ours = tag. The model maps well. The "owner can require approval" pattern is interesting — could be a future-Parachute feature where minting a token with sensitive tags requires Aaron's confirm step.

### 3.2 GCP IAM resource hierarchy + conditions

**Slice expression:** Tree of resources (Org → Folder → Project → individual resource). Roles bound to a node apply to the subtree.

**Sub-resource inheritance:** *Implicit, additive.* "The effective allow policy for a resource is the union of the allow policy set at that resource and the allow policy inherited from its parent." Granting at parent grants at all descendants automatically.

**Tag-based conditions:** Available in IAM Conditions via CEL, but **only in deny policies**:

```
resource.matchTag('123456789012/env', 'prod')
```

For prefix-style scoping in allow policies, the canonical shape is:

```
resource.name.startsWith('projects/_/buckets/exampleco-site-assets/')
```

**Auth check at request time:** Per-call evaluation against the union of inherited bindings + conditions. CEL-evaluated.

**Mint authority:** Service account impersonation governed by `iam.serviceAccountTokenCreator`. To impersonate, the principal must have the role explicitly granted on the SA. No automatic subset enforcement at the IAM-conditions level — the SA's permissions are independently configured. Audit logs preserve both impersonator + impersonated identities.

[Sources: [GCP IAM resource hierarchy](https://docs.cloud.google.com/iam/docs/resource-hierarchy-access-control) | [GCP IAM conditions](https://docs.cloud.google.com/iam/docs/conditions-overview) | [GCP service account impersonation](https://docs.cloud.google.com/iam/docs/service-account-impersonation)]

**Lesson:** GCP's hierarchy is implicit/additive — same as patterns#24 sub-tag inheritance. The fact that tag-conditions are *only* in deny policies (not allow) is telling: Google chose not to anchor positive grants to a mutable attribute. We're doing the opposite. That's a design choice worth flagging — if a tag is removed from a note, the writer's positive grant evaporates. Manageable because Aaron is the only operator and tag-edits are intentional, but document the asymmetry.

### 3.3 AWS IAM resource tags + ABAC

**Slice expression:** Tag-based via `aws:ResourceTag/<key>`, `aws:RequestTag/<key>`, `aws:PrincipalTag/<key>` condition keys in IAM JSON policies.

**Canonical pattern:**

```json
{
  "Effect": "Allow",
  "Action": ["ec2:StartInstances", "ec2:StopInstances"],
  "Resource": "arn:aws:ec2:*:*:instance/*",
  "Condition": {
    "StringEquals": {"aws:ResourceTag/Owner": "${aws:username}"}
  }
}
```

**Sub-resource inheritance:** None at the tag level — each resource carries its own tag set. But ARN prefix matching gives a path-flavor: `arn:aws:s3:::mybucket/health/*` works for hierarchical resource names.

**Auth check at request time:** Per-call, evaluator pulls the resource's current tags, evaluates conditions.

**Pitfalls** ([from AWS docs](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_tags.html) and [Tenable on PassRole](https://www.tenable.com/blog/auditing-iampassrole-a-problematic-privilege-escalation-permission)):

1. *Tag-key case sensitivity.* `Owner` and `owner` collide in conditions but can both exist as actual tags. AWS recommends `aws:TagKeys` to constrain.
2. *Don't gate `iam:PassRole` on `ResourceTag`* — AWS's docs explicitly warn this is unreliable.
3. `aws:RequestTag` controls what tags can be put *on* a resource — separate from `aws:ResourceTag` (read).

**Mint authority:** `iam:PassRole` is the canonical privilege-escalation vector — restrict to specific role ARNs with `iam:PassedToService` conditions; never wildcard.

**Lesson:** AWS's ABAC works at scale. Lessons we should adopt:
- Be careful with case; root tag names are case-sensitive in our hierarchy machinery, but document this.
- Distinguish *read-tag* (does the note carry the tag?) from *write-tag* (the new note is tagged with X). patterns#24 conflates these. AWS treats them as separate concerns and so should we — see edge cases below.

### 3.4 HashiCorp Vault path policies

**Slice expression:** Path patterns + capabilities.

```hcl
path "secret/health/*" {
  capabilities = ["read", "list"]
}
path "secret/health/private" {
  capabilities = ["deny"]
}
```

Wildcards: `*` only at end, `+` for single-segment match. **No automatic sub-path inheritance — you must explicitly list each pattern.**

**Capabilities:** `create`, `read`, `update`, `patch`, `delete`, `list`, `sudo`, `deny`, `subscribe`. Eight verbs vs our three-level hierarchy.

**Auth check:** Most-specific-match wins, with deny taking priority. Lexicographic + glob-priority ordering.

[Source: [Vault policies docs](https://developer.hashicorp.com/vault/docs/concepts/policies)]

**Lesson:** Vault is a strong reference for "tokens scoped to a path subtree" — exactly our shape. Two lessons: (1) wildcard at end of pattern is enough for hierarchical scoping (don't need recursive pattern syntax); (2) explicit deny overrides allow. patterns#24 is allow-only — if denylist becomes a future need, Vault's precedence model is the place to copy.

### 3.5 Kubernetes RBAC

**Slice expression:** `Role` (namespace-scoped) or `ClusterRole` (cluster-wide), bound via `RoleBinding`/`ClusterRoleBinding`. Resources × verbs × `resourceNames` (optional name allowlist).

**Sub-resource inheritance:** Sub-resources expressed by path notation: `pods/log`, `pods/exec`. Not hierarchical; explicit per sub-resource.

**Auth check:** Purely additive (no deny rules in core RBAC). Default deny.

[Source: [Kubernetes RBAC docs](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)]

**Lesson:** K8s deliberately rejected denylist — "RBAC has no deny rules — only allow." patterns#24 already aligns. The `resourceNames` field is interesting: it's a literal allowlist of names within a resource type. Maps weakly to our "specific tag list within a tag namespace." Validates the shape.

### 3.6 PostgreSQL Row-Level Security

**Slice expression:** SQL boolean predicate per-row, attached to a table:

```sql
CREATE POLICY user_sel_policy ON notes
  FOR SELECT
  USING (tag_root = ANY(current_setting('app.token_tags')::text[]));
```

**Read vs write separation:** **`USING` for visibility, `WITH CHECK` for modification.** This is the canonical pattern for "read more than you can write."

**Permissive vs restrictive:** Permissive policies OR'd; restrictive policies AND'd. Lets you compose layered scopes.

**Performance:** Simple per-row predicates scale fine. Sub-SELECT predicates can have race conditions and require `FOR SHARE` locks.

[Source: [PostgreSQL RLS docs](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)]

**Lesson:** RLS is the closest analog to what patterns#24 implements at the application layer. **Adopt the `USING`/`WITH CHECK` distinction** — it cleanly separates "what can I see" from "what can I write," addressing the read-list vs write-list alternative directly.

### 3.7 Notion API — page-level permission inheritance

**Slice expression:** Token grants on a workspace; page-share gates actual access. Internal connections must have pages explicitly shared; public OAuth uses a page-picker.

**Sub-page inheritance:** **Implicit and parent-driven.** "Parent pages can be selected to quickly provide access to child pages, as giving access to a parent page will provide access to all available child pages."

**Mint authority:** Users can only share pages where they have full access — the subset rule is the share-time check.

[Source: [Notion API authorization](https://developers.notion.com/docs/authorization)]

**Lesson:** Notion validates the "parent share → child auto-share" pattern, which patterns#24 mirrors via tag hierarchy. The mint-time check ("you can only share what you fully own") is identical to our subset rule.

### 3.8 Slack OAuth scopes

**Slice expression:** Workspace-wide scopes (`channels:read`, `chat:write`) — most tokens have full visibility into all public channels.

**Single-channel install:** `single_channel=true` query param at OAuth time prompts the installer to pick *one* channel. The token is then restricted to that channel only. Multi-channel install requires repeating the OAuth dance per channel.

[Source: [Slack OAuth docs](https://docs.slack.dev/authentication/installing-with-oauth/)]

**Lesson:** Slack's per-channel restriction is **token-attribute-based**, not OAuth-scope-string-based — same architectural choice patterns#24 made (tags as token attribute, not part of scope string). Validates §"Why not extend the OAuth scope string."

### 3.9 Auth0 organizations + nested groups

**Slice expression:** Organizations (top-level tenant), with optional Authorization Extension nested groups. Permissions bind to roles in groups; group nesting propagates.

**Inheritance:** "Adding a user to a sub-group also grants the user permissions granted to the groups that are parents (and grandparents) of that group." Note the direction: in Auth0 nested groups, child membership grants parent permissions (because "I'm in the engineering-frontend group, which is part of engineering, which has X"). This is *inverse* to patterns#24, where token-allowlist `[health]` grants access to `health/food`. Different model — Auth0's groups are about identity bundling; ours is about resource bundling.

[Source: [Auth0 community on hierarchies](https://community.auth0.com/t/how-do-i-handle-organizations-in-a-hirearchy/84811)]

**Lesson:** Confirm the directionality of inheritance. patterns#24 is *parent-grant → descendant-included*, which is the dominant pattern. Don't accidentally flip it.

### 3.10 Salesforce field-level security + Data Cloud ABAC

**Slice expression:** Multi-layered. Object-level (profiles), record-level (sharing rules + role hierarchy), field-level (FLS), and (in Data Cloud) attribute-based policies on tags + classifications.

**Tag-based policy example:** "Policies can be set at field, object, or record levels... attributes like tags and classifications determine access."

**Deny-overrides-allow:** Salesforce Data Cloud explicitly does deny-precedence-over-allow.

[Source: [Salesforce data governance](https://engineering.salesforce.com/scaling-data-cloud-governance-achieving-structured-security-across-300000-orgs/)]

**Lesson:** Salesforce shows tag-as-auth-boundary working at scale (300k orgs). The architectural pattern: RBAC for coarse access, ABAC (tags) for fine-grained. patterns#24 is in this lineage — `vault:<name>:<action>` is the RBAC layer, tag-allowlist is the ABAC overlay.

### 3.11 NIST ABAC / XACML hierarchical resource profile

**XACML** has a formal hierarchical-resource profile with `resource-parent`, `resource-ancestor`, `resource-ancestor-or-self` attributes — explicit policy-language support for "this rule applies to this node and all descendants."

[Sources: [XACML hierarchical resource profile](https://docs.oasis-open.org/xacml/3.0/xacml-3.0-hierarchical-v1-spec-cd-03-en.html) | [NIST ABAC project](https://csrc.nist.gov/projects/abac)]

**Lesson:** The XACML hierarchical-resource profile is the formal grandparent of what we're doing. We don't need its formality, but it validates the conceptual shape: hierarchical resource scoping is a recognized policy-language primitive.

### 3.12 Obsidian plugin model

For completeness: Obsidian's plugin API has **no permission model**. A plugin gets full vault access on install. The Local REST API plugin is a trust-the-token model with no per-note scoping. This is a deliberate non-feature of Obsidian that Parachute is *trying to solve*.

[Source: [Obsidian Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api)]

---

## 4. Hierarchical inheritance — comparison table

| System | Inheritance direction | Implicit or explicit | Inheritance at create-time or dynamic | Renames handled? |
|---|---|---|---|---|
| **patterns#24 (current)** | Parent → descendant (root tag → sub-tag) | Implicit (via `_tags/<name>` config) | Dynamic (read at request time) | **Open question** |
| GCP IAM hierarchy | Parent → descendant (org → project) | Implicit, additive | Dynamic | Resources move via API; bindings re-evaluate |
| POSIX default ACLs | Parent dir → child file | Implicit (via default ACL) | **Create-time snapshot only** | Renames preserve existing ACLs; default ACL change doesn't propagate to existing children |
| NTFS ACLs | Parent → child | Explicit inherit-flag per ACE | Dynamic by default; can be broken via "stop inheriting" | Inherited ACLs follow rename within tree |
| LDAP nested groups | Member group → containing group | Explicit (via membership) | Dynamic | Group rename affects DNs |
| Auth0 nested groups | Sub-group → parent group permissions | Implicit on membership-add | Dynamic | — |
| Notion pages | Parent page → child page | Implicit on parent-share | Dynamic | Page move re-evaluates share inheritance |
| Vault path policies | None; explicit per-pattern | Explicit | Dynamic per-request | Path renames break references |
| K8s RBAC | None (flat namespace) | N/A | N/A | N/A |
| AWS IAM tag conditions | None at tag-level; ARN-prefix gives path-flavor | Explicit | Dynamic | Tag-rename = atomic; ARN renames break references |
| XACML hierarchical resource profile | Parent → descendant via `ancestor-or-self` attribute | Explicit in policy | Per-evaluation | Profile-defined |

**Conclusions for patterns#24:**
- The dominant pattern is *implicit, dynamic inheritance with parent-grant-includes-children*. patterns#24 already matches.
- POSIX-style "create-time snapshot" is an outlier. Don't adopt it — dynamic re-evaluation is what Aaron wants.
- Document explicitly that tag rename is the rename-edge-case (analogous to LDAP DN rename, AWS ARN rename) and decide on semantics. See §5.

---

## 5. Edge cases the current design might miss

Each entry: **scenario** — *surfacing system* — *recommended action*.

### 5.1 Tag rename mid-life
A token with allowlist `[health]`. Operator renames `_tags/health` to `_tags/wellness`. What happens to the token?
- Surfacing system: LDAP DN renames, AWS ARN renames.
- **Hazard:** Token is now scoped to a tag that doesn't exist. Either it sees nothing (silent failure) or it errors.
- **Recommendation:** Treat tag-rename as breaking. On rename, find tokens whose allowlist references the old name; either auto-update (foreign-key style) or revoke. *Strongly prefer auto-update* with audit log entry. File as follow-up issue: vault tag-rename token-coherence.

### 5.2 Tag delete
A token allowlists `[health]`. Operator deletes `_tags/health`.
- **Hazard:** Token's allowlist references a deleted tag. Notes previously tagged `#health` may have orphaned tags.
- **Recommendation:** Block tag-delete if any token references it. Equivalent to a foreign-key-restrict pattern. Or: auto-revoke the affected tokens with a clear error message.

### 5.3 Note tag-edit removes the only matching tag
A `health-bot` is mid-write. Operator (or another agent) edits the note to remove `#health`. The bot's next read fails.
- Surfacing system: AWS `aws:ResourceTag` (the docs warn this is dynamic).
- **Hazard:** Race conditions, mid-session loss of access.
- **Recommendation:** Document explicitly. The race is acceptable — vault has no notion of "session" anyway. Auth check is per-request, the request after the tag-removal will fail. Behavior is correct but should be called out so users know `health-bot` losing access mid-conversation is *expected*, not a bug.

### 5.4 Cache invalidation when `_tags/*` hierarchy changes
patterns#24 says hierarchy expansion uses `getTagDescendants`. If that's cached, who invalidates when `_tags/health/food` is added or moved?
- Surfacing system: any system with computed access predicates (Salesforce, GCP IAM with tag-bindings).
- **Recommendation:** Either evaluate uncached on every request (simplest, scales fine for solo-operator vault), or invalidate on `_tags/*` writes. Confirm in vault implementation issue. Document the choice in patterns#24.

### 5.5 Performance with deep tag trees
patterns#24 expands `[health]` → all descendants. If `_tags/health/food/breakfast/cereal/oatmeal` exists, the descendant set may grow.
- Surfacing system: PostgreSQL RLS (sub-SELECT performance), GCP IAM (resource-tree depth).
- **Recommendation:** Probably a non-issue at Aaron's scale. But pre-compute `tag_root` on note write (denormalize) so the auth check is `noteTags.some(t => allowlist.includes(rootOf(t)))` — O(allowlist) × O(tags-on-note). No traversal needed. Document this denormalization as the implementation strategy.

### 5.6 Audit logging
patterns#24 doesn't mention audit. Which token did what?
- Surfacing system: AWS CloudTrail, GCP audit logs.
- **Recommendation:** Add to patterns#24 or sibling doc: every auth check + write op should log `{token_id, scope, scoped_tags, action, note_id, result}`. Especially important for parachute-agent — when a `#health` agent does something surprising, you want to know which token. File follow-up issue: vault audit log + token attribution.

### 5.7 Token revocation / scope reduction
patterns#24 says "allowlist immutable for life of token; editing means mint+revoke."
- Surfacing system: OAuth 2 has a soft "scope downgrade is allowed at refresh." GitHub fine-grained PATs are also immutable, you regenerate.
- **Verdict:** Immutability is the safer call (auditability, predictability). Keep it.
- Caveat: Operators may want to *narrow* a token without invalidating it (e.g., remove `#financial` from a bot's scope). Even that's a privilege change worth a fresh token + revocation. Don't add post-mint editing.

### 5.8 Multi-vault tokens
Aaron's note: "What if I want a token scoped to `default:health` AND `boulder:health`?"
- Surfacing system: GitHub PATs are single-owner. AWS IAM is account-scoped.
- **Recommendation:** Defer. Single-vault is simpler and Parachute's vault-per-life-area shape (`default`, `boulder`, `techne`) probably means cross-vault tokens are rare. If needed later, the natural extension is `scoped_tags: {"default": ["health"], "boulder": ["health"]}` — a per-vault map. File as a draft pattern with `[DEFERRED]` marker.

### 5.9 Sub-tag minted under a deleted parent
Token has allowlist `[health]`. While token is live, operator deletes `_tags/health/food`. What happens to a note tagged `#health/food`?
- The note's tag is now an orphan (no `_tags/<name>` config). The hierarchy expansion may or may not include it.
- **Recommendation:** Define orphan-tag behavior in vault: either fail-closed (orphan tags don't match anything) or fail-open (orphan tags fall through to `rootOf(tag)`). Fail-open is friendlier; fail-closed is safer. Solo-operator → fail-open is fine. Document.

### 5.10 Cross-vault tag collision
`default` vault has `#health`. `boulder` vault has `#health`. Same tag name, different vault. patterns#24 implicitly handles this since tokens are vault-scoped, but call it out — root tag names are namespaced by vault.

---

## 6. Alternative architectures

### 6.1 Allowlist vs denylist

**Pro denylist:** A "general purpose" agent could see everything except `#financial`.

**Con:** [Allowlist is more secure than denylist](https://www.illumio.com/blog/allowlist-vs-denylist) — universal consensus across security literature. Denylist requires you to enumerate every sensitive thing. Add a `#tax` tag later, and existing denylist tokens still see it.

**Recommendation:** **Don't add denylist.** The use case is real but the security model is wrong. Better solution: tag-groups (see 6.5) — define `personal-non-sensitive = [health, journal, family]` and minted as an allowlist. If denylist truly becomes essential, it can be a layered restriction policy à la PostgreSQL `RESTRICTIVE`, applied on top of a permissive allowlist.

### 6.2 Read-list vs write-list separation

**Pro:** Many real agents read more than they write. A `health-bot` may want to *read* `#journal` for context but only *write* to `#health`.

**Con:** Doubles the conceptual surface. Two allowlists per token.

**Surfacing system:** PostgreSQL RLS `USING` vs `WITH CHECK` — explicitly designed for this. Vault distinguishes read/write capabilities per path.

**Recommendation:** **Defer but design-for.** Keep `scoped_tags` as a single allowlist for v1. In v2, allow `{read_tags: [...], write_tags: [...]}`. Migration path: an existing single allowlist → both fields equal. Document this as a `[DRAFT]` future shape in patterns#24, or open a follow-up patterns issue.

### 6.3 Wildcards / pattern matching

**Status:** patterns#24 already does this — root-tag in allowlist matches all sub-tags. So `[health]` is functionally `health/*`. Good.

**The other direction**, where you allowlist `health/food` only (not all of `#health`), works automatically too — `rootOf(t)` resolves to `health` for a `health/food` allowlist entry. *Wait — does it?* The current pseudocode says `token.tagAllowlist.includes(rootOf(t))` which looks at the *note's tag root*, but the allowlist might contain `health/food`. If allowlist contains `health/food` and note has `#health/food`, `rootOf(#health/food) = health`, allowlist doesn't contain `health` → fail. **This is a bug in the current pseudocode** — or at least an under-specified case. Either:

- **Restrict allowlist to root tags only** (current §"Token issuance" hints at this: *"the values must be existing root-tag names (no path separators)"*). Tightens the rule and matches current pseudocode. Sub-tag granularity is denied.
- **Allow path-form allowlist** like `health/food` and change the auth check to "any of note's tags is a prefix-or-equal-or-descendant-of any allowlist entry." More flexible but more complex.

**Recommendation:** Pick one and document. If MVP: stick with root-only. Open issue: support path-form allowlist as a future enhancement once root-only proves limiting.

### 6.4 Time-bounded scope

**Pro:** "30-day write access to `#tax`" for a tax-season bot.

**Con:** patterns#24 already has `expires_in` on the whole token. Per-tag time-bounding is nice-to-have but the simple workaround is "mint a 30-day token with `[tax]` scope."

**Recommendation:** **Don't add per-tag expiry.** Token-level expiry is sufficient for the use cases described.

### 6.5 Tag groups / abstractions

**Pro:** Aaron mints multiple `#health` bots. Each token's `tags: ["health"]` is repeated. A named group `personal = [health, journal, family]` lets you mint with `groups: ["personal"]` and reference once.

**Surfacing system:** RBAC roles are exactly this — bundled permissions reference-by-name.

**Con:** Indirection. Group rename problem (same as tag rename). Adds a `_tag_groups/<name>` config-note concept.

**Recommendation:** **Defer until repetition becomes painful.** When Aaron has 5+ tokens with the same allowlist, file as a real need. Until then, allowlists are short enough to be literal. Document as a known evolution path.

### 6.6 Capability vs ACL framing

**Capability model:** the token IS the proof of access; no central ACL lookup.

**ACL model:** auth check at request time looks up token-id → permissions in a server table.

**patterns#24 is hybrid:** the token is opaque (capability-flavor), but auth-check reads `tokens.scoped_tags` from vault DB (ACL-flavor). This is fine — it's how most modern web auth works (bearer-token + server-side scope lookup).

**Recommendation:** No change. The hybrid is correct.

---

## 7. Recommendations — what to do with the doc

| # | Item | Recommendation |
|---|---|---|
| R1 | Subset rule for mint authority | Keep as-is. Universal pattern. ✓ |
| R2 | `USING` / `WITH CHECK` separation (read vs write tags) | **Defer to v2.** Mark in patterns#24 as `[DRAFT, future]`. File follow-up issue. |
| R3 | Tag rename / delete coherence (§5.1, §5.2) | **Update doc.** Add a "Lifecycle" section: rename auto-updates token allowlists; delete blocks if referenced. File implementation issue against vault. |
| R4 | Note-tag-edit-removes-scope race (§5.3) | **Update doc.** Add a "Semantics" note: race is intentional; auth is per-request, not per-session. |
| R5 | Cache invalidation on `_tags/*` writes (§5.4) | **Update doc.** Specify "uncached, per-request evaluation" or define invalidation. |
| R6 | Performance — denormalize `tag_root` (§5.5) | **Update doc.** Add to "Storage" or "How it composes": auth-check uses `rootOf(t)` against allowlist, no tree walk. |
| R7 | Audit logging (§5.6) | **File follow-up issue.** Out of scope for patterns#24 itself; vault implementation concern. Reference from doc. |
| R8 | Immutability of allowlist (§5.7) | Keep as-is. ✓ |
| R9 | Multi-vault tokens (§5.8) | **Defer.** Add `[DEFERRED]` paragraph to doc. |
| R10 | Orphan sub-tag behavior (§5.9) | **Update doc.** Specify fail-open or fail-closed. |
| R11 | Cross-vault tag collision (§5.10) | **Update doc.** One sentence — root tags are vault-namespaced. |
| R12 | Allowlist vs denylist (§6.1) | **Don't add.** Document the rejected alternative. |
| R13 | Wildcards / path-form allowlist (§6.3) | **Update doc.** Either lock to root-only (simpler) or extend pseudocode + validation to handle path-form allowlists. Currently pseudocode and §"Token issuance" disagree slightly. |
| R14 | Time-bounded per-tag scope (§6.4) | **Don't add.** Token-level expiry sufficient. |
| R15 | Tag groups / abstractions (§6.5) | **Defer.** Note in doc as known evolution. |

**Suggested patterns#24 doc edits:**
1. Tighten §"Token issuance" — clarify root-only allowlist (matches pseudocode), or extend pseudocode to handle path-form.
2. Add §"Lifecycle" — tag rename, delete, orphan handling.
3. Add §"Semantics" — per-request auth, no session affinity, race-on-tag-edit is intentional.
4. Add §"Storage" — note the `tag_root` denormalization or per-request hierarchy walk.
5. Add §"Future evolution" — tag-groups, read/write split, multi-vault, all marked `[DEFERRED]`.

---

## 8. Open questions for Aaron

1. **Tag rename — auto-rewrite or revoke?** When you rename `_tags/health` to `_tags/wellness`, should existing tokens with allowlist `[health]` (a) auto-update to `[wellness]`, (b) be revoked, or (c) silently see-nothing? My recommendation is (a). What's your call?
2. **Allowlist granularity — root-only or path-form?** patterns#24 §"Token issuance" implies root-only ("must be existing root-tag names, no path separators"). The pseudocode uses `rootOf(t)` which is consistent. Want to lock that down? Or want to support `tags: ["health/food"]` for finer scoping right now?
3. **Read/write split — defer or now?** Concrete use case: a `#journal` bot that *reads* dreams (`#journal/dream`) but only *writes* to `#journal/log`. Worth designing for now, or wait until you actually want it?
4. **Audit attribution — patterns concern or vault-impl concern?** Should patterns#24 mandate token-id in audit logs, or is that vault's call? My read is vault implementation; you say.
5. **Tag-delete blocking?** Should `delete-tag` fail-closed if any token references the tag, or auto-revoke the tokens? (Loud-fail vs auto-cleanup.)
6. **Orphan sub-tag — fail-open or fail-closed?** A note tagged `#health/food` after `_tags/health/food` is deleted: does the `[health]`-allowlisted token still see it via root-fall-through?
7. **Tag groups — when?** When you find yourself minting the third token with the same allowlist, want to revisit?

---

## Sources

- [GitHub Docs — Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [GitHub Blog — Introducing fine-grained PATs](https://github.blog/security/application-security/introducing-fine-grained-personal-access-tokens-for-github/)
- [GCP IAM — Resource hierarchy access control](https://docs.cloud.google.com/iam/docs/resource-hierarchy-access-control)
- [GCP IAM — Conditions overview](https://docs.cloud.google.com/iam/docs/conditions-overview)
- [GCP IAM — Service account impersonation](https://docs.cloud.google.com/iam/docs/service-account-impersonation)
- [AWS IAM — Controlling access using tags](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_tags.html)
- [Tenable — Auditing iam:PassRole](https://www.tenable.com/blog/auditing-iampassrole-a-problematic-privilege-escalation-permission)
- [HashiCorp Vault — Policy concepts](https://developer.hashicorp.com/vault/docs/concepts/policies)
- [Kubernetes — RBAC documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [PostgreSQL — Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [Notion — Authorization](https://developers.notion.com/docs/authorization)
- [Slack Developer Docs — Installing with OAuth](https://docs.slack.dev/authentication/installing-with-oauth/)
- [OAuth 2.0 RFC 6749 §3.3](https://www.rfc-editor.org/rfc/rfc6749#section-3.3)
- [NIST — ABAC project](https://csrc.nist.gov/projects/abac)
- [OASIS XACML — Hierarchical Resource Profile v3.0](https://docs.oasis-open.org/xacml/3.0/xacml-3.0-hierarchical-v1-spec-cd-03-en.html)
- [Salesforce Engineering — Data Cloud Governance](https://engineering.salesforce.com/scaling-data-cloud-governance-achieving-structured-security-across-300000-orgs/)
- [Auth0 Community — Organization hierarchies](https://community.auth0.com/t/how-do-i-handle-organizations-in-a-hirearchy/84811)
- [POSIX ACL inheritance — Red Hat docs](https://docs.redhat.com/en/documentation/red_hat_gluster_storage/3/html/administration_guide/sect-posix_access_control_lists)
- [Illumio — Allowlist vs Denylist](https://www.illumio.com/blog/allowlist-vs-denylist)
- [Storj — Capability-based access control](https://storj.dev/learn/concepts/access/capability-based-access-control)
- [Wikipedia — Ambient authority](https://en.wikipedia.org/wiki/Ambient_authority)
- [Obsidian Local REST API plugin](https://github.com/coddingtonbear/obsidian-local-rest-api)
