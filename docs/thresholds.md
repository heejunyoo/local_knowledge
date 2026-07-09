# Thresholds (Single Source of Truth)

Numeric policy for pipeline timing, evidence, retention, and concurrency.

**Parity rule (AP-12 / scenario S05):** every key below MUST exist as a property on
`KnowledgeCore.Thresholds` with the same default. Change docs and code in the same PR.

Wire / code names use `snake_case` in JSON configs and `camelCase` in Swift where idiomatic;
the **string key** in this table is the SoT name for scenarios.

| Key | Default | Unit | Meaning |
|-----|---------|------|---------|
| `max_meeting_audio_minutes` | `180` | minutes | Hard fail at stop if longer |
| `asr_timeout_multiplier_rt` | `4.0` | × duration | ASR timeout = `max(120, duration_s * multiplier)` |
| `asr_timeout_floor_s` | `120` | seconds | Floor for ASR timeout |
| `asr_rtf_target_p50` | `0.4` | RTF | Tuning target on T16 turbo (not hard gate) |
| `llm_timeout_s` | `600` | seconds | Per summarize or critic call |
| `llm_json_repair_max_attempts` | `2` | count | Stage1 repair loop max |
| `evidence_fuzzy_min` | `0.82` | 0–1 | Stage2 quote fuzzy match minimum |
| `evidence_max_warnings` | `5` | count | Above → Stage2 `fail` |
| `max_stage_attempts` | `2` | count | Crash recovery R3 before `*_failed` |
| `capture_heartbeat_interval_s` | `5` | seconds | UI heartbeat while recording |
| `capture_orphan_grace_s` | `120` | seconds | R2: stale recording without heartbeat |
| `fsevents_debounce_ms` | `1500` | ms | Vault reindex coalesce |
| `pipeline_events_max_bytes` | `52428800` | bytes | ~50 MiB log rotate |
| `raw_audio_retention_days` | `90` | days | Delete policy |
| `derived_audio_retention_days` | `90` | days | Or delete after transcribed |
| `uncommitted_candidate_retention_days` | `14` | days | Then suggest abandoned |
| `committed_candidate_retention_days` | `30` | days | After vault commit |
| `critic_json_retention_days` | `30` | days | After commit |
| `max_one_line_summary_chars` | `280` | chars | Schema + UI |
| `decision_cue_patterns_version` | `1` | int | Heuristic library pin for empty-decisions critic |
| `single_flight_heavy_workers` | `1` | count | ASR **or** LLM, never both |
| `max_concurrent_recordings` | `1` | count | KD-18 |
| `commit_retry_max` | `3` | count | commit_pending retries before commit_failed |
| `notes_page_size` | `50` | count | JXA paging default |
| `support_bundle_event_tail` | `500` | count | Last N pipeline events in bundle |

## Hardware tiers (reference)

| Tier | RAM | ASR default | LLM default |
|------|-----|-------------|-------------|
| T16 | 16 GB | `large-v3-turbo` (or `medium` under pressure) | 7–8B Q4 GGUF |
| T24 | 24 GB | `large-v3-turbo` | 7–8B Q5 or light 14B Q4 |
| T32+ | 32 GB+ | `large-v3-turbo` | 14B Q4/Q5; optional Mode A critic |

Owner machine baseline (2026-07-09): **16 GB** → T16.
