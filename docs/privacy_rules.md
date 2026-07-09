# Privacy Rules

Local-first personal PKM. Meeting audio may contain sensitive corporate content.

## Defaults

| Path | Default | Notes |
|------|---------|--------|
| ASR | Local `whisper.cpp` | Cloud STT only if `features.cloud_stt` |
| LLM | Local `llama.cpp` | Cloud only if `features.cloud_llm` + per-meeting confirm recommended |
| Audio storage | `~/Knowledge/audio` machine-local | **Not** iCloud Drive / Obsidian Sync |
| Disk encryption | FileVault | App warns if FileVault off; no passphrase crypto in MVP |
| Notifications | Quiet | No success noise; no transcript body in notifications |

## Redaction preflight (cloud opt-in)

Before any cloud STT/LLM call:

1. Load `docs/redaction_patterns.json` (SoT patterns).
2. Scan transcript (and optional summary candidate).
3. If matches and not covered by `redaction_allowlist.json` → **block** or show rules + require typed `CONFIRM`.
4. Patterns and allowlist are policy code: change only with eval coverage (no ad-hoc regex expansion).

## Logging

- `pipeline_events`: meeting id, status, hashes, error codes — **not** quote text.
- Support bundle: redacted by default; user opt-in for transcript excerpts.

## Screen Recording overcapture

Display audio capture can include non-meeting UI audio. Onboarding must warn; prefer fullscreen meeting apps; retention limits apply.

## Notes mirror

FTS `body_text` is **derived for search**, not a second SoT. SoT remains Notes.app. Mirror is local SQLite only.
