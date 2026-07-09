# Knowledge Curation (on-demand + quarterly)

Adapted from harness memory governance for a personal PKM.

## Index vs body

| Layer | Content |
|-------|---------|
| SQLite / FTS index | One row / pointer per unit; short metadata |
| Vault markdown / Notes.app | Full body (SoT) |
| Candidates under `summaries/` | Ephemeral until commit |

Do not paste full note bodies into “index-only” surfaces (AP-06).

## What does **not** belong as durable knowledge

- Ephemeral UI state and task checklists already in a tracker
- Pure re-derivable facts from live code / git (if engineering notes)
- Duplicate copies of the same meeting summary in Notes **and** vault without a pointer relationship
- Raw audio after retention (unless legal hold — out of scope)

## Types (scope field)

| Scope | Use |
|-------|-----|
| `personal` | Default personal knowledge |
| `project:<id>` | Project-bounded facts and meetings |

Avoid scope leakage: project skills/notes must not be promoted to personal defaults without explicit move.

## Cadence

- **On-demand:** Settings → Run curation report (default UX; no nagging).
- **Quarterly optional:** Mar/Jun/Sep/Dec first week — prune stale uncommitted candidates, consolidate duplicate action items, review project scopes.

## Cross-layer trace

- Action items link to `meeting_id` + vault path + evidence timestamps.
- Pipeline failures link to `pipeline_events` error codes (not free-form cheerleader text).
