# Report contract

## [DRAFT] — `/report` slash command is in flight (octopus-polish)

## Convention

When a tentacle (or any agent) finishes a unit of work, it reports back in
a structured shape — not narrative. The shape is the same whether the
consumer is Uni's central source, the Octopus UI, or the vault.

```
## TL;DR
<1–2 sentences: what changed>

## Details
- <bullets of concrete outcomes, with file paths or PR links>

## Decisions / open questions
- <anything that needs a human to steer>

## Follow-ups
- <work that's queued but not done>
```

## `/report` slash command

The intended ergonomic surface: a tentacle types `/report` and is prompted
(by the harness) to fill in the above sections. The harness then:

1. Sends the structured block back to the team-lead via `SendMessage`.
2. Optionally persists to vault as `uni/handoff` (path
   `Uni/Handoffs/<YYYY-MM-DD>-<slug>`), controlled by the spawn brief.
3. Optionally forwards a TL;DR to Telegram, controlled by the spawn brief.

"Controlled by the spawn brief" means the tentacle's spawn prompt includes
a `Report contract:` section with `persistToVault: yes|no` and
`telegram: yes|no` so the tentacle knows its report discipline without
asking each time.

Implementation tracked in the octopus-polish work. Until it lands, tentacles
produce the same structured shape manually in their SendMessage response.

## Why

- **Synthesis stays cheap.** A parent agent ingesting structured markdown
  can skim it in one pass. Narrative responses force re-reading.
- **Vault-friendly.** The same block drops into a handoff note with zero
  reformatting.
- **Stops drift.** Without a contract, each tentacle invents its own shape
  and the team-lead's context fragments.

## Rules

- Reports are **structured, not narrative.** If you catch yourself writing
  more than a paragraph in prose, you're missing the sections.
- **TL;DR first, always.** The team-lead and Aaron may read nothing else.
- **Link, don't paste.** Reference PR URLs, commit SHAs, file paths. Don't
  quote diffs into the report.
- **No emoji or decoration** unless the audience explicitly wants it
  (rarely). Match Parachute's tone: precise, not precious.

## Spawn-brief section

The block that goes into every tentacle spawn prompt, inherited from
UnforcedAGI conventions:

```markdown
## Report contract
- When done (or blocked), SendMessage team-lead with a structured report.
- Persist to vault: yes | no  (path: Uni/Handoffs/<date>-<slug>, tag: uni/handoff)
- Telegram: yes | no  (TL;DR only)
```

## Open questions

- Push vs pull: should the team-lead explicitly request a report, or should
  the tentacle send one unprompted at each work-block boundary? Current
  practice is the latter. Keep until it causes noise.
