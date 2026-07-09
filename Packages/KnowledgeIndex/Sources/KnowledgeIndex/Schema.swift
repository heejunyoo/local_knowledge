import Foundation

/// Schema version and migrations for knowledge.db.
public enum IndexSchema {
    public static let currentVersion = 1

    public static let migrationV1 = """
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS meeting (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT,
      mode TEXT NOT NULL DEFAULT 'offline_mic',
      status TEXT NOT NULL,
      scope TEXT NOT NULL DEFAULT 'personal',
      audio_path TEXT,
      audio_sha256 TEXT,
      audio_duration_ms INTEGER,
      transcript_path TEXT,
      transcript_segment_count INTEGER DEFAULT 0,
      asr_model_id TEXT,
      candidate_path TEXT,
      stage1_ok INTEGER NOT NULL DEFAULT 0,
      stage2_outcome TEXT,
      vault_path TEXT,
      vault_content_hash TEXT,
      accepted_at TEXT,
      stage_attempts INTEGER NOT NULL DEFAULT 0,
      error_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_meeting_status ON meeting(status);
    CREATE INDEX IF NOT EXISTS idx_meeting_scope ON meeting(scope);

    CREATE TABLE IF NOT EXISTS action_item (
      id TEXT PRIMARY KEY NOT NULL,
      meeting_id TEXT NOT NULL REFERENCES meeting(id) ON DELETE CASCADE,
      text TEXT NOT NULL,
      owner TEXT,
      due_on TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      evidence_json TEXT,
      created_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_action_meeting ON action_item(meeting_id);

    CREATE TABLE IF NOT EXISTS note_mirror (
      notes_id TEXT PRIMARY KEY NOT NULL,
      folder TEXT,
      title TEXT,
      body_text TEXT,
      content_hash TEXT,
      body_status TEXT NOT NULL DEFAULT 'ok',
      mirror_not_sot INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS source_pointer (
      id TEXT PRIMARY KEY NOT NULL,
      source_type TEXT NOT NULL,
      external_id TEXT NOT NULL,
      title TEXT,
      scope TEXT NOT NULL DEFAULT 'personal',
      meeting_id TEXT REFERENCES meeting(id) ON DELETE SET NULL,
      notes_id TEXT,
      vault_rel_path TEXT,
      updated_at TEXT NOT NULL,
      UNIQUE(source_type, external_id)
    );

    CREATE TABLE IF NOT EXISTS pipeline_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      meeting_id TEXT,
      ts TEXT NOT NULL,
      from_status TEXT,
      to_status TEXT,
      event TEXT NOT NULL,
      error_code TEXT,
      detail_json TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_events_meeting ON pipeline_events(meeting_id);

    -- FTS over search documents. Meeting body SoT remains vault markdown (S06).
    -- content is DERIVED index text only (title + summary one-liner + action texts).
    CREATE VIRTUAL TABLE IF NOT EXISTS fts_docs USING fts5(
      doc_id UNINDEXED,
      source_type UNINDEXED,
      title,
      body,
      tokenize = 'unicode61'
    );
    """
}
