# Vault + Index Commit Protocol

There is **no** atomic cross-filesystem transaction between Obsidian vault files and SQLite.
We use an explicit two-phase protocol with a durable pipeline status.

## States

| Status | Meaning |
|--------|---------|
| `review_needed` | Human has not accepted |
| `commit_pending` | Accept started; vault and/or index may be mid-write |
| `committed` | Final vault path exists **and** index row is `committed` |
| `commit_failed` | Protocol failed after retries; reconcile needed |

## Steps (happy path)

1. **Precondition:** `review_needed`, human Accept, Stage1 OK (re-run if summary edited). Stage2 fail blocks unless future explicit flag (default off).
2. Transition → `commit_pending`.
3. Write vault file to `{vault}/Meetings/YYYY/MM/{id}.md.tmp`.
4. `fsync` + atomic `rename` → `{id}.md` (final).
5. Upsert SQLite meeting row: `status=committed`, `vault_path`, content hash, FTS.
6. Transition → `committed`. Delete or retain candidate JSON per retention policy.
7. **No success notification** (Quiet by Default).

## Failure / crash

| Observation | Reconcile action |
|-------------|------------------|
| `commit_pending`, tmp exists, final missing | Retry rename or rewrite tmp |
| `commit_pending`, final exists, index not committed | Upsert index only |
| `commit_pending`, neither final nor good tmp | → `commit_failed` or back to `review_needed` |
| Final exists and index committed but status stuck | → `committed` |

Drift scenario **S13** asserts: no permanent `commit_pending` without recoverable markers.

## Non-goals

- Do not claim “transactional” FS+SQLite.
- Do not write meeting body only into SQLite as SoT.
- Transcripts/audio stay under `knowledge_root`, not vault (multi-device: machine-local).
