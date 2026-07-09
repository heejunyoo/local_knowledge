# Glossary (wire format)

All JSON, DB columns, and log fields use **snake_case** unless noted.

| Term | Wire value | Meaning |
|------|------------|---------|
| Pipeline statuses | `recording`, `recorded`, `transcribing`, `transcribed`, `summarizing`, `summarized_candidate`, `critic_running`, `critic_failed`, `review_needed`, `commit_pending`, `committed`, `record_failed`, `transcribe_failed`, `summary_failed`, `commit_failed`, `abandoned` | Default-deny graph in KnowledgeCore |
| Summary sections | `one_line_summary`, `key_discussion_points`, `decisions`, `action_items`, `unresolved_items` | MeetingSummaryV1 |
| Stage2 outcomes | `pass`, `pass_with_warnings`, `fail` | Evidence gate |
| Feature flags file | `~/Knowledge/config/features.json` only | Never in `app.json` |
| Thresholds | `docs/thresholds.md` + `Thresholds` struct | AP-12 parity |
| Source types | `meeting`, `obsidian`, `notes` | Search / index |
| Scope | `personal` \| `project:<id>` | KD-14 |
| Notifications | `failure`, `review_needed`, `action_due` | Only allowed notify kinds |
| Knowledge root | `knowledge_root` | Machine-local `~/Knowledge` |
| Vault path | `vault_path` | Separate Obsidian directory |
| Notes mirror | `body_text` + `mirror_not_sot=true` | Derived FTS; SoT = Notes.app |

`KnowledgeKind` enum: **deferred post-MVP**.
