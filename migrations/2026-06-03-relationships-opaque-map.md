---
title: relationships loosened to an opaque vocabulary map
date: 2026-06-03
status: active
originating-pr: ParachuteComputer/parachute-vault#431
---

# relationships loosened to an opaque vocabulary map

vault#431 loosened the tag-schema `relationships` field from a strict
`{target_tag, cardinality}` validator to an **opaque vocabulary map**: any plain
JSON object (relationship-name → arbitrary JSON value), stored verbatim and
**not** enforced at write time. The validator now rejects only a top-level
array, primitive, `null`, or empty-string key — it does not look at the inner
shape of each value. The old typed `{target_tag, cardinality}` shape is still
fully accepted (it's a valid opaque map), so the new contract is a
backwards-compatible **superset** of the old one.

Motivation: the Weaver/UI needs to store a freeform relationship vocabulary like
`{"works-on":{"from":"person","to":"project"}}` directly on the tag, rather than
being boxed into the typed-link declaration shape. The
[`tag-data-model.md`](../patterns/tag-data-model.md) doc already noted that
"Phase 1 is informational — declarations not enforced at write time"; this aligns
the SHAPE validation with that stance. The `{target_tag, cardinality}` shape
survives as a **recommended convention** for typed-link declarations, not a
requirement.

This file is the propagation checklist for the doc + code surfaces that quoted
the strict shape.

## Code references

- [x] `parachute-vault:core/src/tag-schemas.ts` `validateRelationships` — loosened to accept any plain-object map (rejects array/primitive/null/empty-key only). (vault#431)
- [x] `parachute-vault:core/src/mcp.ts` `update-tag` schema — `relationships` accepts an opaque map. (vault#431)

## Doc references

- [x] `parachute-patterns:patterns/tag-data-model.md` — one-line summary, `relationships` column comment, the relationships section (reframed to lead with the opaque-map contract as canonical, `{target_tag, cardinality}` demoted to recommended convention), migration-history entry, footer. (this PR)
- [ ] `parachute-vault:docs/HTTP_API.md` relationships section — needs the opaque-map update (the strict shape was added here in vault#427); a concurrent vault docs PR addresses this.

## Operator-facing references

None significant. The change is a validation-loosening, not a surface change —
operators who authored the typed `{target_tag, cardinality}` shape see no
behavior difference (still accepted); the new freedom is additive. The vault
admin SPA / Notes tag editor surface the relationships JSON as-is and need no
copy change for the loosening.

## External references

None.

## Cross-references

- [`../patterns/tag-data-model.md`](../patterns/tag-data-model.md) — the canonical contract; §Relationships carries the opaque-map definition + the recommended typed-link convention.
- [`../scripts/audit-canonical-refs.sh`](../scripts/audit-canonical-refs.sh) — grep-based audit for stale canonical refs.
